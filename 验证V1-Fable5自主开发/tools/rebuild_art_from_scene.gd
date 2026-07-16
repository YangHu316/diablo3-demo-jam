extends SceneTree

# 验证V1 · 美术重建 v3:几何真相 = 场景内的 CSG 多边形(支持用户手动编辑后重跑跟随)
#   来源:副本场景的 Floor0_0 多边形(外扩地板,回缩0.52=可走边界) + Rock*.polygon(含节点XZ变换)
#   墙体:直接**骑在边界线上**逐边精确铺满(零多边形偏移→零碎片零杂散),
#        每个顶点立柱封缝;短边(<1.6m)改用碎砖/骨堆/岩块等杂物封堵;砖面朝可走侧
#   就地重建:删除旧美术子树(ArtFloors/BrickWalls/Torches/Landmarks/Scatter/Nav)后按当前几何重建
#   同时导出 scene_walk.json 供生成器/校验使用(敌人生成边界跟随编辑)
# Run: Godot --headless --path . --script res://验证V1-Fable5自主开发/tools/rebuild_art_from_scene.gd

const SCENE := "res://验证V1-Fable5自主开发/scenes/level_03_csg_art.tscn"
const WALK_JSON := "res://验证V1-Fable5自主开发/tools/scene_walk.json"
const ADAPTER := "res://验证V1-Fable5自主开发/scripts/dh_level_adapter.gd"
const CATALOG := "res://验证V1-Fable5自主开发/tools/asset_catalog.json"
const B := "res://assets/PolygonDungeon/Models/"
# 0.13→0.02:碰撞地面是隐藏 CSG(顶面 y=0),角色站在 y=0 上;砖面高出 13cm 会把
# 玩家/敌人的脚埋进砖里(v7 透视剪影把埋脚照成青斑后暴露)。压到 +2cm 视觉齐脚面。
const TILE_TOP := 0.02    # 全部地砖顶面统一对齐到此高度(消除变体厚度差 0.10~0.19 造成的台阶)
const DECOR_TOP := 0.035  # 地面装饰的落地面(地砖顶面 +1.5cm,防闪面)

const SEED := 715
const WALL_LEN := 5.24
const WALL_YS := 0.8
const FLOOR_TO_WALK := 0.52   # 地板板缘 → 可走边界 的回缩量(建造期常量)
const TORCH_STEP := 14.0
const MAX_TORCH_LIGHTS := 30
const ART_NODES := ["ArtFloors", "BrickWalls", "Torches", "Landmarks", "Scatter", "DecorClusters", "NavigationRegion3D"]

var rng := RandomNumberGenerator.new()
var catalog: Dictionary = {}
var missing_cat := {}
var wall_sites: Array = []          # 每片砖墙 {mid, facing, yaw} → 挂幅位
var torch_pts: PackedVector2Array = PackedVector2Array()
var keepouts: Array = []            # [中心 Vector2, 半径] → 装饰群避让地标/入口
var loops: Array = []
var raster := PackedByteArray()
var rx0 := 0.0
var rz0 := 0.0
var rw := 0
var rh := 0
const RCELL := 0.5
var light_count := 0

func _init() -> void:
	rng.seed = SEED
	var cf := FileAccess.open(ProjectSettings.globalize_path(CATALOG), FileAccess.READ)
	if cf != null:
		var cd = JSON.parse_string(cf.get_as_text())
		cf.close()
		if cd is Dictionary:
			catalog = cd
	var root := (load(SCENE) as PackedScene).instantiate() as Node3D
	# 小地图/迷雾适配器(level 组数据契约)
	if root.get_script() == null:
		root.set_script(load(ADAPTER))

	# ① 从场景 CSG 读几何(含节点变换 → 用户编辑跟随)
	if not _scene_loops(root):
		quit(1); return
	_build_raster()
	_export_walk_json()

	# ② 删除旧美术子树,就地重建
	for nm in ART_NODES:
		var old := root.get_node_or_null(nm)
		if old != null:
			root.remove_child(old)
			old.free()

	var n_tiles := _build_floor_tiles(root)
	var counts := _build_brick_walls(root)
	_build_landmarks(root)
	var n_scatter := _build_scatter(root)
	var n_decor := _build_decor(root)
	var n_nav := _build_navmesh(root)

	_own(root, root)
	var ps := PackedScene.new()
	ps.pack(root)
	var err := ResourceSaver.save(ps, SCENE)
	print("[rebuild] 地砖 ", n_tiles, " / 砖墙 ", counts[0], " / 转角柱 ", counts[1], " / 杂物封堵 ", counts[2],
			" / 火把 ", counts[3], " / 散布 ", n_scatter, " / 装饰群 ", n_decor, " / 导航面 ", n_nav, " / 灯 ", light_count,
			" / 未编目 ", missing_cat.size(), " err=", err)
	quit(0 if err == OK else 1)

# ══════════════ ① 场景几何直读 ══════════════
func _acc_xf(n: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t

func _poly_world(n: CSGPolygon3D, root: Node) -> PackedVector2Array:
	var xf := _acc_xf(n, root)
	var out := PackedVector2Array()
	for p in n.polygon:
		var w := xf * Vector3(p.x, p.y, 0)
		out.append(Vector2(w.x, w.z))
	return out

func _scene_loops(root: Node3D) -> bool:
	var floors := root.get_node_or_null("Floors")
	var rocks := root.get_node_or_null("RockMasses")
	if floors == null:
		printerr("FAIL: 场景缺 Floors"); return false
	for c in floors.get_children():
		if c is CSGPolygon3D:
			var slab := _poly_world(c, root)
			# 地板外扩板 → 回缩得到可走边界
			for wb in _offset_signed(slab, -FLOOR_TO_WALK):
				if absf(_poly_area(wb)) > 30.0:
					loops.append({"hole": false, "pts": _dp_closed(wb, 0.28)})
	if rocks != null:
		for c in rocks.get_children():
			if c is CSGPolygon3D:
				var fp := _poly_world(c, root)
				if absf(_poly_area(fp)) > 3.0:
					loops.append({"hole": true, "pts": _dp_closed(fp, 0.22)})
	print("[rebuild] 场景几何: ", loops.size(), " 环(外墙+Rock墙体)")
	return not loops.is_empty()

func _export_walk_json() -> void:
	var out := {"loops": []}
	for lp in loops:
		var pts: Array = []
		for p in lp["pts"]:
			pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
		(out["loops"] as Array).append({"hole": lp["hole"], "pts": pts})
	var f := FileAccess.open(ProjectSettings.globalize_path(WALK_JSON), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()

# ══════════════ 几何基础 ══════════════
func _poly_area(pv: PackedVector2Array) -> float:
	var s := 0.0
	for i in pv.size():
		s += pv[i].x * pv[(i + 1) % pv.size()].y - pv[(i + 1) % pv.size()].x * pv[i].y
	return s * 0.5

func _offset_signed(pv: PackedVector2Array, want: float) -> Array:
	var a0 := absf(_poly_area(pv))
	var res: Array = Geometry2D.offset_polygon(pv, want, Geometry2D.JOIN_ROUND)
	var a1 := 0.0
	for r in res:
		a1 += absf(_poly_area(r))
	if (want > 0.0) != (a1 > a0):
		res = Geometry2D.offset_polygon(pv, -want, Geometry2D.JOIN_ROUND)
	return res

func _build_raster() -> void:
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for lp in loops:
		for p in lp["pts"]:
			mn = mn.min(p); mx = mx.max(p)
	rx0 = mn.x - 1.0
	rz0 = mn.y - 1.0
	rw = int((mx.x - mn.x + 2.0) / RCELL) + 1
	rh = int((mx.y - mn.y + 2.0) / RCELL) + 1
	raster.resize(rw * rh)
	for gy in rh:
		var zc := rz0 + (gy + 0.5) * RCELL
		var xs: Array[float] = []
		for lp in loops:
			var pv: PackedVector2Array = lp["pts"]
			for i in pv.size():
				var a := pv[i]
				var b := pv[(i + 1) % pv.size()]
				if (a.y <= zc) == (b.y <= zc):
					continue
				xs.append(a.x + (zc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var i2 := 0
		while i2 + 1 < xs.size():
			var g0 := int(ceil((xs[i2] - rx0) / RCELL - 0.5))
			var g1 := int(floor((xs[i2 + 1] - rx0) / RCELL - 0.5))
			for gx in range(maxi(g0, 0), mini(g1, rw - 1) + 1):
				raster[gy * rw + gx] = 1
			i2 += 2

func _walk(p: Vector2) -> bool:
	var gx := int((p.x - rx0) / RCELL)
	var gy := int((p.y - rz0) / RCELL)
	if gx < 0 or gx >= rw or gy < 0 or gy >= rh:
		return false
	return raster[gy * rw + gx] == 1

func _clearance(p: Vector2) -> float:
	var best := INF
	for lp in loops:
		var pv: PackedVector2Array = lp["pts"]
		for i in pv.size():
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, pv[i], pv[(i + 1) % pv.size()]))
			if d < best:
				best = d
	return best

func _dp_closed(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 8:
		return pts
	var far := 0
	var best := -1.0
	for i in pts.size():
		var d := pts[i].distance_squared_to(pts[0])
		if d > best:
			best = d; far = i
	var a_half := PackedVector2Array()
	var b_half := PackedVector2Array()
	for i in range(0, far + 1):
		a_half.append(pts[i])
	for i in range(far, pts.size()):
		b_half.append(pts[i])
	b_half.append(pts[0])
	var ra := _dp_line(a_half, eps)
	var rb := _dp_line(b_half, eps)
	var out := PackedVector2Array()
	for i in ra.size() - 1:
		out.append(ra[i])
	for i in rb.size() - 1:
		out.append(rb[i])
	return out

func _dp_line(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack: Array = [[0, pts.size() - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var s: int = seg[0]
		var e: int = seg[1]
		if e - s < 2:
			continue
		var a := pts[s]
		var b := pts[e]
		var ab := b - a
		var ab_len := ab.length()
		var fi := -1
		var fd := eps
		for i in range(s + 1, e):
			var d: float
			if ab_len < 0.0001:
				d = pts[i].distance_to(a)
			else:
				d = absf(ab.cross(pts[i] - a)) / ab_len
			if d > fd:
				fd = d; fi = i
		if fi >= 0:
			keep[fi] = 1
			stack.append([s, fi])
			stack.append([fi, e])
	var out := PackedVector2Array()
	for i in pts.size():
		if keep[i] == 1:
			out.append(pts[i])
	return out

func _place(parent: Node, rel: String, pos: Vector3, yaw_deg: float = 0.0, scl: Vector3 = Vector3.ONE) -> Node3D:
	var inst = (load(B + rel) as PackedScene).instantiate() as Node3D
	parent.add_child(inst)
	inst.position = pos
	inst.rotation.y = deg_to_rad(yaw_deg)
	inst.scale = inst.scale * scl
	return inst

# 编目条目;缺失时打警告(缺目=落地/对中不准的根源,必须显式暴露而非静默)
func _cat(rel: String) -> Dictionary:
	var e = catalog.get(rel, null)
	if e is Dictionary:
		return e
	if not missing_cat.has(rel):
		missing_cat[rel] = true
		printerr("[rebuild] WARN 未编目资产(落地/对中将不准,请补 catalog_assets.gd): ", rel)
	return {}

# 网格几何中心相对节点原点的偏移(编目 center_xz × 附加缩放)
func _center_off(rel: String, extra: Vector3) -> Vector3:
	var e := _cat(rel)
	if e.is_empty():
		return Vector3.ZERO
	var c: Array = e.get("center_xz", [0, 0])
	return Vector3(float(c[0]) * extra.x, 0.0, float(c[1]) * extra.z)

# 地面装饰落地:按素材编目的 min_y × 缩放,把底部搁在地砖表面(DECOR_TOP)上,不埋进地里
func _ground_y(rel: String, sy: float) -> float:
	var e := _cat(rel)
	return DECOR_TOP - float(e.get("min_y", 0.0)) * sy

func _place_grounded(parent: Node, rel: String, x: float, z: float, yaw_deg: float = 0.0, scl: Vector3 = Vector3.ONE) -> Node3D:
	return _place(parent, rel, Vector3(x, _ground_y(rel, scl.y), z), yaw_deg, scl)

func _light(parent: Node, pos: Vector3, col: Color, energy: float, rng_m: float) -> void:
	light_count += 1
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng_m
	l.shadow_enabled = false
	parent.add_child(l)

# ══════════════ 地砖 ══════════════
func _build_floor_tiles(root: Node3D) -> int:
	var holder := Node3D.new()
	holder.name = "ArtFloors"
	root.add_child(holder)
	var variants := ["Environment/Floors/SM_Env_Tiles_01.fbx", "Environment/Floors/SM_Env_Tiles_02.fbx",
			"Environment/Floors/SM_Env_Tiles_03.fbx", "Environment/Floors/SM_Env_Tiles_04.fbx",
			"Environment/Floors/SM_Env_Tiles_05.fbx", "Environment/Floors/SM_Env_Tiles_06.fbx"]
	var total := 0
	var gx0 := snappedf(rx0, 5.0)
	var gz0 := snappedf(rz0, 5.0)
	var nx := int((rw * RCELL) / 5.0) + 2
	var nz := int((rh * RCELL) / 5.0) + 2
	for iz in nz:
		for ix in nx:
			var cx := gx0 + ix * 5.0 + 2.5
			var cz := gz0 + iz * 5.0 + 2.5
			var c := Vector2(cx, cz)
			# 地砖网格原点在角部(编目 center_xz=[2.5,2.5]),必须按 yaw 反向补偿,
			# 否则随机旋转会把砖甩进相邻格(v6 审计根因:漏铺+叠砖+越界)。
			# 判定余量 1.8/0.9:地板本就要延伸到墙裙之下(FLOOR_TO_WALK),允许砖缘压进墙底。
			if _cell_ok(c, 1.8):
				total += _lay_tile(holder, variants[rng.randi() % variants.size()], c, 1.0)
			else:
				for hz in 2:
					for hx in 2:
						var h := Vector2(cx - 1.25 + hx * 2.5, cz - 1.25 + hz * 2.5)
						if _cell_ok(h, 0.6):
							# 半格也用带纹理的大砖 ×0.5(旧版 Tile_Simple 是素面平片,铺出来一片"光地")
							total += _lay_tile(holder, variants[rng.randi() % variants.size()], h, 0.5)
						else:
							# 弧形墙缘再补 1/4 砖,消除"贴墙一圈裸地"(墙裙下方允许压边)
							for qz in 2:
								for qx in 2:
									var q := Vector2(h.x - 0.625 + qx * 1.25, h.y - 0.625 + qz * 1.25)
									if _cell_ok(q, 0.32):
										total += _lay_tile(holder, variants[rng.randi() % variants.size()], q, 0.25)
	return total

func _lay_tile(holder: Node3D, rel: String, at: Vector2, s: float) -> int:
	var yaw := (rng.randi() % 4) * 90.0
	var e := _cat(rel)
	var sz: Array = e.get("size", [5.0, 0.1, 5.0])
	var scl := Vector3(s, 1.0, s)
	var ty := TILE_TOP - (float(e.get("min_y", 0.0)) + float(sz[1]))   # 顶面统一对齐
	var t := _place(holder, rel, Vector3.ZERO, yaw, scl)
	var toff := Basis(Vector3.UP, deg_to_rad(yaw)) * _center_off(rel, scl)
	t.position = Vector3(at.x, ty, at.y) - toff
	return 1

func _cell_ok(center: Vector2, half: float) -> bool:
	if not _walk(center):
		return false
	for off in [Vector2(-half, -half), Vector2(half, -half), Vector2(-half, half), Vector2(half, half)]:
		if not _walk(center + off):
			return false
	return true

# ══════════════ 砖墙:骑线逐边铺满 + 全顶点立柱 + 短边杂物封堵 ══════════════
const RUBBLE := ["Environment/Walls/SM_Env_Brick_Rubble_01.fbx", "Environment/Walls/SM_Env_Brick_Rubble_02.fbx",
		"Environment/Walls/SM_Env_Brick_Rubble_03.fbx", "Environment/Walls/SM_Env_Brick_Rubble_04.fbx",
		"Environment/Walls/SM_Env_Brick_Rubble_06.fbx", "Environment/Bones/SM_Env_BonePile_Small_01.fbx",
		"Environment/Bones/SM_Env_BonePile_Small_02.fbx", "Environment/Pillars/SM_Env_Pillar_Broken_01.fbx"]

func _build_brick_walls(root: Node3D) -> Array:
	var wholder := Node3D.new()
	wholder.name = "BrickWalls"
	root.add_child(wholder)
	var tholder := Node3D.new()
	tholder.name = "Torches"
	root.add_child(tholder)
	var n_wall := 0
	var n_pillar := 0
	var n_fill := 0
	var n_torch := 0
	var torch_dist := 0.0
	const HALF_T := 0.22   # 半墙厚:墙线外移量 → 墙内侧面与边界齐平,不吃进关卡
	for lp in loops:
		var ml: PackedVector2Array = lp["pts"]
		var n := ml.size()
		if n < 3:
			continue
		# ① 每条边的朝向(可走侧):两侧多距离采样投票,防薄岩体上"隔洞采到对面地板"导致朝向翻转
		var facing: Array[Vector2] = []
		for i in n:
			var d := (ml[(i + 1) % n] - ml[i]).normalized()
			var n1 := Vector2(-d.y, d.x)
			var em := (ml[i] + ml[(i + 1) % n]) * 0.5
			var vote := 0
			for ds in [0.8, 1.4, 2.0]:
				if _walk(em + n1 * ds):
					vote += 1
				if _walk(em - n1 * ds):
					vote -= 1
			facing.append(n1 if vote > 0 else -n1)
		# ② 斜接点:相邻两条"外移半墙厚"的边线求交 → 墙件端点在此精确共享(首尾相连)
		var sp := PackedVector2Array()
		sp.resize(n)
		for i in n:
			var prev := (i - 1 + n) % n
			var d0 := (ml[i] - ml[prev]).normalized()
			var d1 := (ml[(i + 1) % n] - ml[i]).normalized()
			var o0 := -facing[prev] * HALF_T
			var o1 := -facing[i] * HALF_T
			var p0 := ml[prev] + o0
			var p1 := ml[i] + o1
			var cr := d0.cross(d1)
			var mpt: Vector2
			if absf(cr) < 0.02:
				mpt = ml[i] + (o0 + o1) * 0.5
			else:
				mpt = p0 + d0 * ((p1 - p0).cross(d1) / cr)
				if mpt.distance_to(ml[i]) > HALF_T * 4.0:   # 尖角斜接过长 → 截断,余缝交给顶点柱
					var avg := (o0 + o1)
					mpt = ml[i] + (avg.normalized() * HALF_T * 1.8 if avg.length() > 0.001 else o1)
			sp[i] = mpt
		# ③ 沿斜接折线逐边等分铺墙:片间端点共享 = 模型首尾相连无缝
		for i in n:
			var a := sp[i]
			var b := sp[(i + 1) % n]
			var seg := b - a
			var len := seg.length()
			var yaw := rad_to_deg(atan2(facing[i].x, facing[i].y))
			if len < 0.8:
				var mid0 := (a + b) * 0.5
				var rel: String = RUBBLE[rng.randi() % RUBBLE.size()]
				var sc := 0.8
				_place(wholder, rel, Vector3(mid0.x, _ground_y(rel, sc), mid0.y), rng.randf() * 360.0, Vector3.ONE * sc)
				n_fill += 1
			elif len >= 0.05:
				var dir := seg / len
				var n_seg := maxi(1, int(round(len / WALL_LEN)))
				if len / n_seg > WALL_LEN * 1.18:
					n_seg += 1
				var seg_len := len / n_seg
				for j in n_seg:
					var mid := a + dir * (seg_len * (j + 0.5))
					var rel2 := "Environment/Walls/SM_Env_Wall_01.fbx" if ((i + j) % 4 != 0) else "Environment/Walls/SM_Env_Wall_01_Alt.fbx"
					var extra := Vector3(seg_len / WALL_LEN * 1.005, WALL_YS, 1.0)
					var w := _place(wholder, rel2, Vector3.ZERO, yaw)
					w.scale = w.scale * extra
					# 关键:墙网格原点在端部(编目 center_xz≈[2.47,0.06]),按中心偏移反向补偿,
					# 让几何中心精确落在段中点 → 片间真正首尾相连
					var off := Basis(Vector3.UP, deg_to_rad(yaw)) * _center_off(rel2, extra)
					w.position = Vector3(mid.x, 0, mid.y) - off
					wall_sites.append({"mid": mid, "facing": facing[i], "yaw": yaw})
					n_wall += 1
					torch_dist += seg_len
					if torch_dist >= TORCH_STEP:
						torch_dist = 0.0
						var tp := mid + facing[i] * 0.55
						# 内侧可走且外侧不可走才挂(排除朝向存疑的薄岩体边)
						if _walk(mid + facing[i] * 0.9) and not _walk(mid - facing[i] * 0.9) and _walk(tp):
							_place(tholder, "Props/Lighting/SM_Prop_Torch_Ornate_02.fbx",
									Vector3(tp.x, 2.1, tp.y), rad_to_deg(atan2(facing[i].x, facing[i].y)))
							torch_pts.append(tp)
							n_torch += 1
							if n_torch % 2 == 0 and light_count < MAX_TORCH_LIGHTS:
								_light(tholder, Vector3(tp.x, 2.6, tp.y), Color(1.0, 0.62, 0.28), 1.7, 9.0)
			# ④ 顶点柱(小型,装饰性关节;斜接后仅需盖住转折处的端面)
			var turn := absf((ml[(i + 1) % n] - ml[i]).normalized().angle_to((ml[(i + 2) % n] - ml[(i + 1) % n]).normalized()))
			if turn > deg_to_rad(10.0):
				var pl := _place(wholder, "Environment/Pillars/SM_Env_Pillar_Round_01.fbx",
						Vector3(sp[(i + 1) % n].x, 0, sp[(i + 1) % n].y), rng.randf() * 360.0)
				pl.scale = pl.scale * Vector3(0.72, WALL_LEN * WALL_YS / 3.93, 0.72)
				n_pillar += 1
	return [n_wall, n_pillar, n_fill, n_torch]

# ══════════════ 地标 ══════════════
func _build_landmarks(root: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Landmarks"
	root.add_child(holder)
	# 装饰群避让区:入口厅(含出生点)/巨颅/肋笼/红门/方尖碑/水晶簇/烛位
	keepouts.append([Vector2(44.3, -33.0), 7.5])
	keepouts.append([Vector2(-70.0, 2.5), 6.0])   # 巨颅实际位置 (x=-70, z=2.5);此前误写成 (−70,35)
	keepouts.append([Vector2(-34.0, 26.0), 5.5])
	keepouts.append([Vector2(-42.1, 42.6), 5.0])
	keepouts.append([Vector2(-13.4, 8.8), 3.0])
	keepouts.append([Vector2(10.4, 3.4), 3.0])
	_place_grounded(holder, "Environment/Doors/SM_Env_Entrance_Crypt_02.fbx", 44.3, -37.0, 180.0)
	_place_grounded(holder, "Props/Lighting/SM_Prop_Brazier_01.fbx", 41.0, -32.0)
	_place_grounded(holder, "Props/Lighting/SM_Prop_Brazier_01.fbx", 47.6, -32.0)
	_light(holder, Vector3(41.0, 1.2, -32.0), Color(1.0, 0.6, 0.25), 1.6, 7.0)
	_light(holder, Vector3(47.6, 1.2, -32.0), Color(1.0, 0.6, 0.25), 1.6, 7.0)
	var grate := _place(holder, "Environment/Floors/SM_Env_Grate_01.fbx", Vector3(-1.9, 0.16, -4.2))
	grate.rotation_degrees = Vector3(90, 0, 0)
	_place_grounded(holder, "Environment/Bones/SM_Env_Bone_Skull_01.fbx", -70.0, 2.5, 35.0, Vector3.ONE * 0.45)
	_place_grounded(holder, "Environment/Bones/SM_Env_Bone_Rigcage_01.fbx", -34.0, 26.0, -25.0, Vector3.ONE * 0.42)
	_place_grounded(holder, "Environment/Doors/SM_Env_Door_Large_Stone_01.fbx", -42.1, 42.6, 0.0)
	_light(holder, Vector3(-42.1, 2.0, 41.0), Color(0.95, 0.18, 0.1), 2.4, 8.0)
	_place_grounded(holder, "Environment/Pillars/SM_Env_Obelisk_01.fbx", -13.4, 8.8, 20.0)
	_place_grounded(holder, "Environment/Pillars/SM_Env_Obelisk_01.fbx", 10.4, 3.4, -35.0)
	for gc in [Vector2(23.4, -13.5), Vector2(56.0, 7.0), Vector2(-21.0, -19.0), Vector2(-46.9, 3.3), Vector2(69.0, 35.0)]:
		if not _walk(gc):
			continue
		keepouts.append([gc, 3.5])
		_place_grounded(holder, "Environment/Decor/SM_Env_Gem_Large_01.fbx", gc.x, gc.y, rng.randf() * 360.0)
		_place_grounded(holder, "Environment/Decor/SM_Env_Gem_Spike_02.fbx", gc.x + 1.2, gc.y + 0.6, rng.randf() * 360.0, Vector3.ONE * 0.8)
		_place_grounded(holder, "Environment/Decor/SM_Env_Gem_Spike_01.fbx", gc.x - 1.0, gc.y - 0.8, rng.randf() * 360.0, Vector3.ONE * 0.6)
		_light(holder, Vector3(gc.x, 1.6, gc.y), Color(0.95, 0.38, 0.4), 1.7, 8.0)
	# ── 三大厅视觉锚点(v6 审计:密度镜头点名的空旷区,手摆定制件)──
	# 入口厅:雕像仪仗 + 骸骨,保持中央开阔(战场)
	_place_grounded(holder, "Environment/Pillars/SM_Env_Statue_02.fbx", 41.2, -36.2, 0.0)
	_place_grounded(holder, "Environment/Pillars/SM_Env_Statue_03.fbx", 47.4, -36.2, 0.0)
	_place_grounded(holder, "Environment/Bones/SM_Env_BonePile_Small_02.fbx", 51.8, -33.5, 40.0)
	_place_grounded(holder, "Props/Containers/SM_Prop_Vase_Group_01.fbx", 37.0, -34.0, 15.0)
	# 北中央枢纽厅 (0,-4):半圈残柱 + 符文石灰堆(玩家东西穿行的必经视觉锚)
	_place_grounded(holder, "Environment/Pillars/SM_Env_Pillar_Broken_02.fbx", -3.0, -6.5, 20.0, Vector3.ONE * 1.15)
	_place_grounded(holder, "Environment/Pillars/SM_Env_Pillar_Broken_Pile_02.fbx", -5.4, -8.0, 130.0)
	_place_grounded(holder, "Environment/Decor/SM_Env_Rune_Rounded_01.fbx", -1.2, -8.6, 75.0)
	_place_grounded(holder, "Props/Lighting/SM_Prop_Candles_03.fbx", -3.9, -4.9, 0.0)
	keepouts.append([Vector2(-3.5, -7.0), 3.0])
	# 西北大厅 (-58,-30):石台祭件轻锚点
	_place_grounded(holder, "Props/Furniture/SM_Prop_StoneTable_Broken_01.fbx", -58.0, -30.0, -25.0)
	_place_grounded(holder, "Props/Lighting/SM_Prop_Candle_Stand_01.fbx", -56.4, -28.8, 0.0)
	_place_grounded(holder, "Environment/Bones/SM_Env_Bone_Skull_Jaw_01.fbx", -59.6, -28.4, 210.0, Vector3.ONE * 0.18)
	keepouts.append([Vector2(-58.0, -29.5), 3.0])
	var candle_spots := [Vector2(42, -28), Vector2(56.5, -11), Vector2(70, 14), Vector2(33.5, 17), Vector2(-1.5, 8),
			Vector2(-21, -23), Vector2(-25.3, 3), Vector2(-37, 26), Vector2(-60.3, -25), Vector2(43, 33)]
	for ci in candle_spots.size():
		var cp: Vector2 = candle_spots[ci]
		if not _walk(cp):
			continue
		keepouts.append([cp, 2.2])
		_place_grounded(holder, "Props/Lighting/SM_Prop_Candle_Stand_01.fbx", cp.x, cp.y, rng.randf() * 360.0)
		_place_grounded(holder, "Props/Lighting/SM_Prop_Candles_01.fbx", cp.x + 0.7, cp.y + 0.3, rng.randf() * 360.0)
		_place_grounded(holder, "Props/Lighting/SM_Prop_Candles_01.fbx", cp.x - 0.5, cp.y + 0.6, rng.randf() * 360.0)
		if ci % 3 == 0:
			_light(holder, Vector3(cp.x, 1.4, cp.y), Color(1.0, 0.72, 0.4), 1.1, 5.5)

# ══════════════ 散布 ══════════════
func _build_scatter(root: Node3D) -> int:
	var holder := Node3D.new()
	holder.name = "Scatter"
	root.add_child(holder)
	var n := 0
	n += _scatter_items(holder, ["Environment/Bones/SM_Env_BonePile_01.fbx", "Environment/Bones/SM_Env_BonePile_02.fbx"],
			14, 1.1, 3.0, 0.7, 1.15)   # 净空≥1.1:骨堆半径≈0.75,防肋骨穿墙压顶
	n += _scatter_items(holder, ["Props/Containers/SM_Prop_Barrel_01.fbx", "Props/Containers/SM_Prop_Vase_03.fbx",
			"Props/Containers/SM_Prop_Crate_Wood_01.fbx", "Props/Containers/SM_Prop_Chest_01.fbx"],
			18, 0.7, 2.6, 0.85, 1.1)
	n += _scatter_items(holder, ["Environment/Cave_Rocks/SM_Env_Rubble_Pebbles_01.fbx"],
			40, 0.25, 1.4, 0.7, 1.4)
	return n

func _scatter_items(holder: Node, rels: Array, target: int, min_cl: float, max_cl: float, smin: float, smax: float) -> int:
	var placed := 0
	var guard := 0
	while placed < target and guard < target * 40:
		guard += 1
		var p := _rand_point()
		if p == Vector2.INF:
			continue
		if _near_keepout(p):   # 散布也须避开入口厅/地标/水晶簇
			continue
		var cl := _clearance(p)
		if cl < min_cl or cl > max_cl:
			continue
		var rel: String = rels[rng.randi() % rels.size()]
		var sc := rng.randf_range(smin, smax)
		_place_grounded(holder, rel, p.x, p.y, rng.randf() * 360.0, Vector3.ONE * sc)
		placed += 1
	return placed

func _rand_point() -> Vector2:
	for attempt in 8:
		var p := Vector2(rx0 + rng.randf() * rw * RCELL, rz0 + rng.randf() * rh * RCELL)
		if _walk(p):
			return p
	return Vector2.INF

# ══════════════ v6 主题装饰群:填充空旷区(全员经编目落地,杜绝半埋) ══════════════
# 模板成员: [rel, dx, dz, yaw, scale] —— 偏移随群落朝向整体旋转
const T_STORAGE: Array = [
	["Props/Containers/SM_Prop_Barrel_01.fbx", 0.0, 0.0, 0.0, 1.0],
	["Props/Containers/SM_Prop_Barrel_02.fbx", 1.05, 0.45, 30.0, 1.0],
	["Props/Containers/SM_Prop_Crate_Wood_02.fbx", -1.0, 0.15, 12.0, 1.0],
	["Props/Containers/SM_Prop_Crate_Wood_03.fbx", -0.85, 1.15, 40.0, 0.9],
	["Props/Containers/SM_Prop_Crate_Ornate_01.fbx", 0.05, -1.05, 25.0, 0.85],
	["Props/Containers/SM_Prop_Vase_Group_01.fbx", 0.45, 1.25, 0.0, 1.0],
	["Props/Containers/SM_Prop_Barrel_Broken_01.fbx", 1.7, 1.1, 75.0, 1.0],
]
const T_STUDY: Array = [
	["Props/Furniture/SM_Prop_Bookcase_01.fbx", 0.0, 0.0, 0.0, 1.0],
	["Props/Furniture/SM_Prop_Bookcase_02.fbx", 1.45, 0.05, -5.0, 1.0],
	["Props/Furniture/SM_Prop_WeaponRack_01.fbx", -1.95, 0.1, 8.0, 1.0],
	["Props/Furniture/SM_Prop_Table_Round_Broken_01.fbx", 0.5, 1.9, 30.0, 1.0],
	["Props/Furniture/SM_Prop_Stool_01.fbx", 1.5, 2.3, 80.0, 1.0],
	["Props/Lighting/SM_Prop_Candles_01.fbx", -0.8, 1.7, 0.0, 1.0],
]
const T_FOUNTAIN: Array = [
	["Environment/Walls/SM_Env_Stone_Fountain_01.fbx", 0.0, 0.0, 0.0, 1.0],
	["Environment/Walls/SM_Env_Stone_Vessel_01.fbx", 1.5, 0.4, 15.0, 1.0],
	["Props/Containers/SM_Prop_Vase_01.fbx", -1.2, 0.5, 0.0, 1.0],
	["Props/Containers/SM_Prop_Vase_Broken_01.fbx", -1.7, 1.2, 60.0, 1.0],
]
const T_GRAVE: Array = [
	# 石台残件当作石棺基座(Coffin_01 是"斜倚姿态"资产,空地摆放上端悬空,已弃用)
	["Props/Furniture/SM_Prop_StoneTable_Broken_01.fbx", 0.0, 0.0, 8.0, 1.0],
	["Environment/Decor/SM_Env_Rune_Rounded_01.fbx", 1.8, -1.0, -10.0, 1.0],
	["Environment/Decor/SM_Env_Rune_Square_01.fbx", -1.9, -0.8, 14.0, 0.95],
	["Environment/Decor/SM_Env_Rune_Rounded_02.fbx", -1.6, 1.4, -22.0, 0.9],
	["Environment/Decor/SM_Env_Rune_Pillar_01.fbx", 2.1, 1.5, 0.0, 0.9],
	["Environment/Bones/SM_Env_BonePile_Small_02.fbx", 1.2, 1.6, 0.0, 0.95],
	["Props/Lighting/SM_Prop_Candles_02.fbx", 0.9, -1.6, 0.0, 1.0],
]
const T_BONEPIT: Array = [
	["Environment/Bones/SM_Env_BonePile_01.fbx", 0.0, 0.0, 0.0, 1.0],
	["Environment/Bones/SM_Env_BonePile_03.fbx", 1.6, 0.8, 60.0, 0.85],
	["Environment/Bones/SM_Env_Bone_Ribs_01.fbx", -1.6, 1.0, 25.0, 0.16],
	["Environment/Bones/SM_Env_Bone_Skull_Jaw_01.fbx", 1.0, -1.4, -45.0, 0.18],
	["Environment/Bones/SM_Env_Bone_Spine_01.fbx", -1.2, -1.5, 15.0, 0.14],
	["Props/Creatures/SM_Prop_Skeleton_01.fbx", 2.2, -0.5, 120.0, 1.0],
]
const T_ALTAR: Array = [
	["Environment/Pillars/SM_Env_Alter_01.fbx", 0.0, 0.0, 0.0, 1.0],
	["Props/Lighting/SM_Prop_Candle_Stand_01.fbx", 2.0, 0.3, 0.0, 1.0],
	["Props/Lighting/SM_Prop_Candle_Stand_01.fbx", -2.0, 0.3, 0.0, 1.0],
	["Props/Lighting/SM_Prop_Candles_03.fbx", 0.8, 1.6, 0.0, 1.0],
	["Environment/Bones/SM_Env_Bone_Skull_02.fbx", -0.9, 1.7, 40.0, 0.12],
	["Props/Furniture/SM_Prop_Rug_03.fbx", 0.0, 2.6, 0.0, 0.5],
]
const T_TORTURE: Array = [
	["Props/Torture/SM_Prop_Toture_Cage_01.fbx", 0.0, 0.0, 0.0, 1.0],
	["Props/Torture/SM_Prop_Toture_Stocks_01.fbx", 2.1, 0.6, 25.0, 1.0],
	["Props/Torture/SM_Prop_Toture_IronMaiden_01.fbx", -1.9, 0.4, -20.0, 1.0],
	["Props/Creatures/SM_Prop_Skeleton_Slave_Lying_01.fbx", 0.7, 1.9, 70.0, 1.0],
	["Environment/Bones/SM_Env_BonePile_Small_01.fbx", -1.2, 1.6, 0.0, 0.9],
]
const T_CAMP: Array = [
	# Bench_01 是"翻倒姿态"资产,视觉上像悬空斜板,换矮凳(两处审计均flag)
	["Props/Lighting/SM_Prop_Bonfire_01.fbx", 0.0, 0.0, 0.0, 1.0],
	["Props/Furniture/SM_Prop_Stool_01.fbx", 1.6, 0.7, -70.0, 1.0],
	["Props/Lighting/SM_Prop_TorchStick_01.fbx", -1.4, 0.9, 0.0, 1.0],
	["Props/Creatures/SM_Prop_Skeleton_Slave_Shackles_01.fbx", -1.9, -0.8, 150.0, 1.0],
	["Props/Containers/SM_Prop_Vase_05.fbx", 1.1, -1.3, 0.0, 1.0],
]
const T_THRONE: Array = [
	["Props/Creatures/SM_Prop_Skeleton_Knight_Throne_01.fbx", 0.0, -0.4, 0.0, 1.15],
	["Props/Lighting/SM_Prop_Cauldron_01.fbx", 2.0, 0.6, 0.0, 1.0],
	["Props/Lighting/SM_Prop_Cauldron_01.fbx", -2.0, 0.6, 0.0, 1.0],
	["Props/Furniture/SM_Prop_Rug_02.fbx", 0.0, 2.4, 0.0, 0.5],
	["Environment/Bones/SM_Env_Bone_Cracked_01.fbx", 1.4, 2.4, 80.0, 0.2],
	["Environment/Walls/SM_Env_Brick_Rubble_04.fbx", -1.3, 2.0, 30.0, 1.0],
]
const TEMPLATES := {"storage": T_STORAGE, "study": T_STUDY, "fountain": T_FOUNTAIN, "grave": T_GRAVE,
		"bonepit": T_BONEPIT, "altar": T_ALTAR, "torture": T_TORTURE, "camp": T_CAMP, "throne": T_THRONE}
# 布点计划: [模板, 数量, 净空min, 净空max, 是否背墙朝内]
const CLUSTER_PLAN: Array = [
	# 大型场面件先占大厅锚点(后置会被小群落耗尽间距而落空)
	["throne", 1, 3.2, 9.0, false],
	["altar", 2, 3.5, 9.0, false],
	["storage", 6, 1.0, 2.0, true],
	["study", 2, 0.9, 1.5, true],
	["fountain", 1, 0.9, 1.4, true],
	["grave", 4, 2.6, 7.0, false],
	["bonepit", 4, 1.6, 5.0, false],
	["torture", 2, 2.2, 6.0, false],
	["camp", 2, 2.4, 6.0, false],
]
const BANNERS := ["Props/Furniture/SM_Prop_Wall_Banner_01.fbx", "Props/Furniture/SM_Prop_Wall_Banner_02.fbx",
		"Props/Furniture/SM_Prop_Wall_Banner_03.fbx"]
const STATUES := ["Environment/Pillars/SM_Env_Statue_01.fbx", "Environment/Pillars/SM_Env_Statue_02.fbx",
		"Environment/Pillars/SM_Env_Statue_03.fbx", "Environment/Pillars/SM_Env_Statue_04.fbx"]
const MAX_LIGHTS_TOTAL := 44

func _near_keepout(p: Vector2, margin: float = 0.0) -> bool:
	for k in keepouts:
		if p.distance_to(k[0]) < float(k[1]) + margin:
			return true
	return false

# 最近墙方向(p → 最近边界点),用于让背墙类装饰面朝场内
func _wall_dir(p: Vector2) -> Vector2:
	var best := INF
	var bp := p
	for lp in loops:
		var pv: PackedVector2Array = lp["pts"]
		for i in pv.size():
			var cp := Geometry2D.get_closest_point_to_segment(p, pv[i], pv[(i + 1) % pv.size()])
			var d := p.distance_to(cp)
			if d < best:
				best = d
				bp = cp
	return (bp - p).normalized() if bp != p else Vector2.RIGHT

func _find_anchor(cl_min: float, cl_max: float, gap: float, anchors: Array, tries: int) -> Vector2:
	for t in tries:
		var p := _rand_point()
		if p == Vector2.INF:
			continue
		var cl := _clearance(p)
		if cl < cl_min or cl > cl_max:
			continue
		if _near_keepout(p, 2.0):   # 群落成员可向外伸 ~2m,避让区按此外扩
			continue
		var ok := true
		for q in anchors:
			if p.distance_to(q) < gap:
				ok = false
				break
		if ok:
			return p
	return Vector2.INF

func _place_cluster(holder: Node3D, tpl: Array, anchor: Vector2, cyaw: float) -> int:
	var n := 0
	for mi in tpl.size():
		var m: Array = tpl[mi]
		var rel: String = m[0]
		var off: Vector3 = Basis(Vector3.UP, deg_to_rad(cyaw)) * Vector3(float(m[1]), 0.0, float(m[2]))
		var mp := anchor + Vector2(off.x, off.z)
		var sc := float(m[4]) * rng.randf_range(0.96, 1.04)
		# 按编目 footprint 计算所需净空,防大件(骨脊/肋骨/断柱)半身插进墙里
		var e := _cat(rel)
		var szv: Array = e.get("size", [1.0, 1.0, 1.0])
		var need := clampf(maxf(float(szv[0]), float(szv[2])) * 0.5 * sc * 0.7, 0.3, 1.4)
		if not _walk(mp) or _clearance(mp) < need:
			if mi == 0:
				return 0   # 主题核心件放不下 → 整个群落放弃,避免只剩配角的"无主"散件
			continue
		var yaw := cyaw + float(m[3]) + rng.randf_range(-7.0, 7.0)
		var node := _place_grounded(holder, rel, mp.x, mp.y, yaw, Vector3.ONE * sc)
		if rel.contains("Rug"):
			node.position.y += 0.015   # 地毯贴地,抬一线防止与地砖闪面
		n += 1
	return n

func _build_decor(root: Node3D) -> int:
	var holder := Node3D.new()
	holder.name = "DecorClusters"
	root.add_child(holder)
	var anchors: Array[Vector2] = []
	var n := 0
	for plan in CLUSTER_PLAN:
		var key: String = plan[0]
		var want: int = plan[1]
		var placed := 0
		var guard := 0
		while placed < want and guard < want * 12:
			guard += 1
			var a := _find_anchor(float(plan[2]), float(plan[3]), 7.0, anchors, 50)
			if a == Vector2.INF:
				break
			var cyaw: float
			if bool(plan[4]):
				var away := -_wall_dir(a)
				cyaw = rad_to_deg(atan2(away.x, away.y))
			else:
				cyaw = rng.randf() * 360.0
			anchors.append(a)
			var got := _place_cluster(holder, TEMPLATES[key], a, cyaw)
			if got == 0:
				continue   # 核心件放不下,换点重试(该锚点保留为占位)
			n += got
			if key == "altar" and light_count < MAX_LIGHTS_TOTAL:
				_light(holder, Vector3(a.x, 1.7, a.y), Color(1.0, 0.75, 0.42), 1.2, 6.5)
			elif (key == "camp" or key == "throne") and light_count < MAX_LIGHTS_TOTAL:
				_light(holder, Vector3(a.x, 1.1, a.y), Color(1.0, 0.55, 0.22), 1.5, 7.0)
			placed += 1
		if placed < want:
			print("[rebuild] 提示: 群落 ", key, " 仅安置 ", placed, "/", want)
	n += _build_singles(holder, anchors)
	n += _build_banners(holder)
	# 细碎遗骸/残片(低净空,填走廊边角)
	n += _scatter_items(holder, ["Props/Creatures/SM_Prop_Skeleton_01.fbx",
			"Props/Creatures/SM_Prop_Skeleton_Slave_Lying_01.fbx"], 8, 0.8, 4.0, 0.95, 1.05)
	n += _scatter_items(holder, ["Props/Containers/SM_Prop_Vase_Shard_01.fbx",
			"Environment/Walls/SM_Env_Brick_Rubble_05.fbx", "Props/Containers/SM_Prop_Vase_Broken_01.fbx"],
			26, 0.3, 2.6, 0.9, 1.3)
	n += _scatter_items(holder, ["Props/Lighting/SM_Prop_Candles_02.fbx"], 10, 0.5, 3.0, 0.9, 1.1)
	return n

func _build_singles(holder: Node3D, anchors: Array) -> int:
	var n := 0
	for i in 6:   # 靠墙雕像,面向场内
		var a := _find_anchor(1.3, 2.2, 5.0, anchors, 60)
		if a == Vector2.INF:
			break
		anchors.append(a)
		var away := -_wall_dir(a)
		var rel: String = STATUES[i % STATUES.size()]
		var sc := 0.72 if rel.ends_with("Statue_01.fbx") else 0.95
		_place_grounded(holder, rel, a.x, a.y, rad_to_deg(atan2(away.x, away.y)), Vector3.ONE * sc)
		n += 1
	for i in 8:   # 大厅残柱(净空提高到 3.2:倒柱堆 footprint 大,防横在窄走廊中央/搭上墙冠)
		var a := _find_anchor(3.2, 7.0, 6.0, anchors, 60)
		if a == Vector2.INF:
			break
		anchors.append(a)
		var rel2 := "Environment/Pillars/SM_Env_Pillar_Broken_02.fbx" if i % 2 == 0 else "Environment/Pillars/SM_Env_Pillar_Broken_Pile_02.fbx"
		_place_grounded(holder, rel2, a.x, a.y, rng.randf() * 360.0, Vector3.ONE * rng.randf_range(1.0, 1.2))
		n += 1
	for i in 4:   # 石灯
		var a := _find_anchor(1.8, 3.6, 6.0, anchors, 60)
		if a == Vector2.INF:
			break
		anchors.append(a)
		_place_grounded(holder, "Environment/Walls/SM_Env_Stone_Lantern_01.fbx", a.x, a.y, rng.randf() * 360.0)
		n += 1
	for i in 4:   # 走道地毯
		var a := _find_anchor(2.4, 6.0, 6.0, anchors, 60)
		if a == Vector2.INF:
			break
		anchors.append(a)
		var rel3 := "Props/Furniture/SM_Prop_Rug_02.fbx" if i % 2 == 0 else "Props/Furniture/SM_Prop_Rug_03.fbx"
		var node := _place_grounded(holder, rel3, a.x, a.y, 90.0 * (rng.randi() % 2), Vector3.ONE * 0.55)
		node.position.y += 0.015
		n += 1
	return n

# 墙面挂幅:网格原点在顶端(编目 min_y≈-高度) → 顶端定位在 3.35m,垂降 ~2.3m
func _build_banners(holder: Node3D) -> int:
	var n := 0
	var vi := 0
	for si in wall_sites.size():
		if n >= 24:
			break
		if si % 4 != 2:
			continue
		var s: Dictionary = wall_sites[si]
		var mid: Vector2 = s["mid"]
		var facing: Vector2 = s["facing"]
		# 只挂在直墙段中间:前后邻片同向(避开转角柱/斜接点),且远离地标避让区
		if si == 0 or si + 1 >= wall_sites.size():
			continue
		var y_prev := float((wall_sites[si - 1] as Dictionary)["yaw"])
		var y_next := float((wall_sites[si + 1] as Dictionary)["yaw"])
		var y_cur := float(s["yaw"])
		if absf(angle_difference(deg_to_rad(y_cur), deg_to_rad(y_prev))) > deg_to_rad(4.0) \
				or absf(angle_difference(deg_to_rad(y_cur), deg_to_rad(y_next))) > deg_to_rad(4.0):
			continue
		if _near_keepout(mid, 0.5):
			continue
		var near_torch := false
		for tp in torch_pts:
			if tp.distance_to(mid) < 2.2:
				near_torch = true
				break
		# 与火把同款的朝向双检:内可走+外不可走
		if near_torch or not _walk(mid + facing * 1.2) or _walk(mid - facing * 0.9):
			continue
		var rel: String = BANNERS[vi % BANNERS.size()]
		vi += 1
		var e := _cat(rel)
		var sz: Array = e.get("size", [1.0, 1.0, 1.0])
		var mny := float(e.get("min_y", 0.0))
		var s_hang := minf(2.3 / maxf(float(sz[1]), 0.1), 1.15)
		var y := 3.35 - (mny + float(sz[1])) * s_hang
		var p := mid + facing * 0.40   # 沿墙法线外移,避开墙面凸砖穿布
		_place(holder, rel, Vector3(p.x, y, p.y), rad_to_deg(atan2(facing.x, facing.y)), Vector3(1.0, s_hang, 1.0))
		n += 1
	return n

# ══════════════ 导航 ══════════════
func _build_navmesh(root: Node3D) -> int:
	var cell := 1.0
	var nx := int(rw * RCELL / cell)
	var nz := int(rh * RCELL / cell)
	var verts: Array[Vector3] = []
	var vmap := {}
	var polys: Array = []
	for iz in nz:
		for ix in nx:
			var c := Vector2(rx0 + (ix + 0.5) * cell, rz0 + (iz + 0.5) * cell)
			if _walk(c) and _walk(c + Vector2(cell, 0)) and _walk(c - Vector2(cell, 0)) \
					and _walk(c + Vector2(0, cell)) and _walk(c - Vector2(0, cell)):
				var x0 := rx0 + ix * cell
				var z0 := rz0 + iz * cell
				polys.append(PackedInt32Array([
					_vid(verts, vmap, x0, z0), _vid(verts, vmap, x0 + cell, z0),
					_vid(verts, vmap, x0 + cell, z0 + cell), _vid(verts, vmap, x0, z0 + cell)]))
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.vertices = verts
	nm.polygons = polys
	var reg := NavigationRegion3D.new()
	reg.name = "NavigationRegion3D"
	reg.navigation_mesh = nm
	root.add_child(reg)
	return polys.size()

func _vid(verts: Array, vmap: Dictionary, x: float, z: float) -> int:
	var key := "%.1f_%.1f" % [x, z]
	if not vmap.has(key):
		vmap[key] = verts.size()
		verts.append(Vector3(x, 0.05, z))
	return vmap[key]

func _own(n: Node, root: Node) -> void:
	for c in n.get_children():
		if c.owner == null:
			c.owner = root
		_own(c, root)
