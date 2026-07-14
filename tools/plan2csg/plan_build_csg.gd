extends SceneTree

# 由 level_trace.json 生成 CSG 白盒场景并保存为 .tscn(场景内=真实 CSG 节点,可编辑,无运行时脚本):
#   Floors = CSGCombiner3D(外环 CSGPolygon3D 并集 + 洞环 差集,带碰撞)
#   Walls  = 沿每条轮廓边的 CSGBox3D 墙段(外侧偏移,不侵占地面,带碰撞)
#   PlayerSpawn Marker3D + EntranceLight(右上入口传送门)
# Run: Godot --headless --path . --script res://tools/plan2csg/plan_build_csg.gd

const CFG_PATH := "res://tools/plan2csg/plan_config.json"
const WALL_H := 3.0
const WALL_T := 0.5
const WALL_GAP := 0.0   # 墙内面与可走区边缘齐平贴合(路径偏移法保证不压地面)

func _init() -> void:
	var cfg: Dictionary = _load_json(CFG_PATH)
	var tr: Dictionary = _load_json(String(cfg["trace_json"]))
	if tr.is_empty():
		printerr("FAIL: trace json 缺失,先跑 plan_trace.gd"); quit(1); return
	var loops: Array = tr["loops"]

	var root := Node3D.new()
	root.name = "Level03CSG"

	var dl := DirectionalLight3D.new()
	dl.name = "DirectionalLight3D"
	dl.rotation_degrees = Vector3(-50, -30, 0)
	dl.light_color = Color(1, 0.878, 0.698)
	dl.light_energy = 0.55
	root.add_child(dl)

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.09, 0.08)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.4
	we.environment = env
	root.add_child(we)

	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.85, 0.83, 0.79)
	floor_mat.roughness = 0.95
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.12, 0.115, 0.11)
	wall_mat.roughness = 0.95

	# ── 地面(外环独立多边形) + 岩体(洞环=实心深色体块,即平面图内墙) — 零布尔,最稳 ──
	# 形态学平滑:外环闭运算(填梯桥横档/阴影留下的发丝凹缝)、洞环开运算(去发丝凸须)。
	const SMOOTH := 0.45
	var floors := Node3D.new()
	floors.name = "Floors"
	root.add_child(floors)
	var rocks := Node3D.new()
	rocks.name = "RockMasses"
	root.add_child(rocks)
	var n_outer := 0
	var n_hole := 0
	var outer_smoothed: Array = []   # 平滑后的外环(供墙生成)
	for li in loops.size():
		var lp: Dictionary = loops[li]
		var hole: bool = lp["hole"]
		var pv := PackedVector2Array()
		for p in lp["pts"]:
			pv.append(Vector2(p[0], p[1]))
		var smoothed: Array = _morph(pv, -SMOOTH, SMOOTH) if hole else _morph(pv, SMOOTH, -SMOOTH)
		if smoothed.is_empty():
			print("  ⚠ 环 %d 平滑后消失(发丝级伪影),跳过" % li)
			continue
		for si in smoothed.size():
			var sp: PackedVector2Array = smoothed[si]
			if sp.size() < 3 or absf(_poly_area(sp)) < 0.5:
				continue
			if not hole:
				# 地板不在此建:由墙体中线再外扩生成(垫到墙底下),见墙生成段
				outer_smoothed.append(sp)
				continue
			var poly := CSGPolygon3D.new()
			poly.name = "Rock%d_%d" % [li, si]
			poly.polygon = sp
			poly.mode = CSGPolygon3D.MODE_DEPTH
			poly.rotation_degrees = Vector3(90, 0, 0)   # 局部XY→世界XZ,挤出向 -Y
			poly.depth = WALL_H
			poly.position = Vector3(0, WALL_H, 0)   # 从 y=3 挤到 y=0:实心岩体
			poly.material = wall_mat
			poly.use_collision = true
			poly.collision_layer = 4
			poly.collision_mask = 0
			rocks.add_child(poly)
			n_hole += 1

	# ── 墙:外环轮廓经 offset_polygon(圆角)外扩 → Path3D + CSGPolygon3D 沿路径连续挤出 ──
	# 一体成型:转角圆滑、无缝隙、无凸起;外扩量=间隙+半墙厚,数学上保证不压地面。
	# 洞环不建墙:实心岩体的侧面即墙。
	var walls := Node3D.new()
	walls.name = "Walls"
	root.add_child(walls)
	var n_seg := 0
	var profile := PackedVector2Array([
		Vector2(-WALL_T * 0.5, 0.0), Vector2(WALL_T * 0.5, 0.0),
		Vector2(WALL_T * 0.5, WALL_H), Vector2(-WALL_T * 0.5, WALL_H),
	])
	for li in outer_smoothed.size():
		var pv: PackedVector2Array = outer_smoothed[li]
		var delta := WALL_GAP + WALL_T * 0.5
		var off: Array = _offset_signed(pv, delta)
		# 闭运算(先胀后缩 0.5):反折角(发卡口)也圆滑,消除挤出折叠凸刺;只向远离地面方向动
		var closed: Array = []
		for q in off:
			for g in _offset_signed(q, 0.5):
				for s in _offset_signed(g, -0.5):
					closed.append(s)
		off = closed
		for qi in off.size():
			var q: PackedVector2Array = off[qi]
			if q.size() < 3:
				continue
			var path := Path3D.new()
			path.name = "WallPath%d_%d" % [li, qi]
			var curve := Curve3D.new()
			for p2 in q:
				curve.add_point(Vector3(p2.x, 0, p2.y))
			path.curve = curve
			walls.add_child(path)
			var wp := CSGPolygon3D.new()
			wp.name = "Wall%d_%d" % [li, qi]
			wp.mode = CSGPolygon3D.MODE_PATH
			wp.polygon = profile
			wp.path_joined = true
			wp.path_rotation = CSGPolygon3D.PATH_ROTATION_PATH_FOLLOW
			wp.path_interval_type = CSGPolygon3D.PATH_INTERVAL_SUBDIVIDE
			wp.path_interval = 1.0
			wp.smooth_faces = false
			wp.material = wall_mat
			wp.use_collision = true
			wp.collision_layer = 4
			wp.collision_mask = 0
			path.add_child(wp)
			wp.path_node = NodePath("..")
			n_seg += 1
			# 地板:墙中线再外扩(半墙厚+0.02) → 地板完整垫在墙底下,略超墙外侧面,无缝无洞
			for fp in _offset_signed(q, WALL_T * 0.5 + 0.02):
				if (fp as PackedVector2Array).size() < 3:
					continue
				var fl := CSGPolygon3D.new()
				fl.name = "Floor%d_%d" % [li, qi]
				fl.polygon = fp
				fl.mode = CSGPolygon3D.MODE_DEPTH
				fl.rotation_degrees = Vector3(90, 0, 0)
				fl.depth = 0.5
				fl.material = floor_mat
				fl.use_collision = true
				fl.collision_layer = 4
				fl.collision_mask = 0
				floors.add_child(fl)
				n_outer += 1

	# ── 出生点 + 入口传送门灯 ──
	var sp: Array = tr["spawn_world"]
	var mk := Marker3D.new()
	mk.name = "PlayerSpawn"
	mk.position = Vector3(sp[0], 0, sp[1])
	root.add_child(mk)
	var ent: Array = tr["entrance_world"]
	var ol := OmniLight3D.new()
	ol.name = "EntranceLight"
	ol.position = Vector3(ent[0], 2.5, ent[1])
	ol.light_color = Color(1.0, 0.65, 0.3)
	ol.light_energy = 2.0
	ol.omni_range = 12.0
	root.add_child(ol)

	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, String(cfg["scene_out"]))
	print("[build] 外环 ", n_outer, " / 洞环 ", n_hole, " / 墙段 ", n_seg,
			" / 出生点 (", sp[0], ",", sp[1], ") → ", cfg["scene_out"], " err=", err)
	quit(0 if err == OK else 1)

# 形态学开/闭:r1 后 r2(闭=+r,-r 填凹缝;开=-r,+r 去凸须)
func _morph(pv: PackedVector2Array, r1: float, r2: float) -> Array:
	var out: Array = []
	for g in _offset_signed(pv, r1):
		for s in _offset_signed(g, r2):
			out.append(s)
	return out

# 带号语义的 offset:正=膨胀(面积增),负=收缩(面积减);自动探测 Clipper 绕向修正符号
func _offset_signed(pv: PackedVector2Array, want: float) -> Array:
	var a0 := absf(_poly_area(pv))
	var res: Array = Geometry2D.offset_polygon(pv, want, Geometry2D.JOIN_ROUND)
	var a1 := 0.0
	for r in res:
		a1 += absf(_poly_area(r))
	var grew := a1 > a0
	if (want > 0.0) != grew:
		res = Geometry2D.offset_polygon(pv, -want, Geometry2D.JOIN_ROUND)
	return res

func _poly_area(pv: PackedVector2Array) -> float:
	var s := 0.0
	for i in pv.size():
		var a := pv[i]
		var b := pv[(i + 1) % pv.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		c.owner = root
		_own(c, root)

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}
