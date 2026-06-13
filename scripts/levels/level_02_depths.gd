@tool
extends Node3D

# L2 ·「痛苦回廊」白盒 —— 按提供的蓝图(平面图)解读搭建的大型地牢白盒。
# @tool:几何在编辑器里也会构建(可见预览);战斗部分(刷怪/出口/落点)仅运行时。
# 改了 WALK/SCALE 等数组后:在编辑器里重新打开本场景(或重载脚本)即可刷新预览。
# 蓝图解读(轴对齐近似,北=−Z=上):
#   西门(入口蓝portal) → 西廊 → 中央枢纽(十字) → 三向分叉:
#     · 北:长北廊(纵深)→ 上中室 / 北门(目标·蓝portal)
#     · 西南:宝藏死胡同(小圆室)
#     · 东:东廊 → 齿轮室(机关)→ 右侧环路(绕中心实体)→ Boss厅(中心柱)
#   下环路:枢纽南廊 → 南长廊 → 汇入 Boss 入口,与「东路」形成大环路。
#
# 导航:rect→栅格 navmesh 编译器(矩形栅格化→共享顶点四边形,连通由构造保证);
#       墙体由同一栅格的「可走/不可走」边界自动生成。全部 collision_layer=4。
#
# 规模:SCALE 统一缩放,按 ~6 分钟单程通关校准(见 verify_level02.gd 测的临界路径长度)。

const SCALE: float = 1.5   # 统一缩放:房间/走廊放大,避免局促;临界路径随之拉长
const ENEMY := preload("res://scenes/enemies/enemy_zombie.tscn")
const CORPSE := preload("res://scripts/entities/data/walking_corpse.tres")
const SPAWN_TRIGGER := preload("res://scripts/components/spawn_trigger.gd")
const LEVEL_EXIT := preload("res://scripts/components/level_exit.gd")

# 可走矩形 [xmin, xmax, zmin, zmax](相邻矩形需重叠/相接,栅格才连通)
const WALK := [
	[-92, -74, -16, 2],    # W1 西门(入口)
	[-78, -44, -6, 2],     # W2 西廊
	[-44, -18, -2, 30],    # H  中央枢纽
	[-40, -30, -70, 4],    # N1 长北廊(纵深)
	[-50, -22, -86, -66],  # NP 北门(目标)
	[-30, 2, -52, -28],    # UC 上中室(分隔室)
	[-46, -30, 26, 40],    # T1 西南廊
	[-78, -46, 24, 44],    # TR 宝藏死胡同
	[-18, 12, 14, 26],     # E1 东廊(加宽,留弓系风筝空间)
	[12, 32, 8, 28],       # GR 齿轮室
	[30, 58, 8, 16],       # RL_N 右环·北
	[50, 58, 16, 40],      # RL_E 右环·东
	[30, 58, 32, 44],      # RL_S 右环·南(加宽)
	[30, 38, 16, 36],      # RL_W 右环·西(围中心实体)
	[44, 54, 40, 56],      # BC Boss 入口廊
	[50, 84, 52, 82],      # BOSS Boss 厅(中心柱)
	[-40, -30, 28, 58],    # S1 枢纽南廊
	[-40, 46, 48, 60],     # S2 南长廊(加宽;汇入 Boss 入口=大环路)
]

# 地标 [x, z, kind]   kind: portal_in / portal_out / gear / chest / boss_pillar / waypoint
const LANDMARKS := [
	[-83, -7, "portal_in"],    # 西门入口
	[-36, -78, "portal_out"],  # 北门目标
	[-36, -70, "beacon"],      # 北门光柱(远端牵引,长廊尽头可见)
	[22, 18, "gear"],          # 机关
	[-62, 34, "chest"],        # 宝藏
	[67, 67, "boss_pillar"],   # Boss 中心柱
	[-31, 14, "waypoint"],     # 枢纽
]

# 长廊串灯坐标 [x, z](每约 18-22u 一盏暖光,把"纸面纵深"换成"一段段看得见的推进")
const TORCHES := [
	[-35, -58], [-35, -40], [-35, -22], [-35, -4],   # N1 长北廊
	[-30, 54], [-10, 54], [10, 54], [30, 54],         # S2 南长廊
]

# 遭遇 [x, z, count, formation, radius, surround]
# 注:surround 半径不可超过所在走廊半宽(否则刷进墙) → 仅用于开阔 Boss 厅;
#     窄廊用 cluster/line。东路主线数量单调爬升,Boss 厅为高潮。
const ENCOUNTERS := [
	[-60, -2, 3, "line", 5, false],      # 西廊·首遇(前置开场,不冷场)
	[-31, 14, 4, "cluster", 5, false],   # 枢纽
	[-15, 18, 4, "line", 5, false],      # 枢纽→东 过渡(填空走段)
	[-3, 20, 4, "line", 5, false],       # 东廊
	[22, 18, 5, "cluster", 5, false],    # 齿轮室(清场=机关转开)
	[44, 38, 6, "cluster", 4, false],    # 右环·南(改 cluster,贴合窄廊半宽)
	[10, 54, 5, "line", 5, false],       # 南长廊(下环)
	[-35, -40, 5, "cluster", 5, false],  # 北廊伏击(纵深支线)
	[-36, -78, 4, "cluster", 5, false],  # 北门守卫(目标)
	[49, 48, 6, "line", 5, false],       # Boss 入口廊(爬升,不回落)
	[67, 67, 12, "surround", 7, true],   # Boss 厅尸潮(高潮:12 环绕)
]

const PLAYER_SPAWN := Vector3(-83, 0, -7)   # 西门

var nav_region: NavigationRegion3D = null

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	# 清掉上一次生成的几何(保留 .tscn 里手摆的灯光/环境),保证编辑器反复刷新不叠加
	for c in get_children():
		if c is DirectionalLight3D or c is WorldEnvironment:
			continue
		c.free()
	# 视觉几何:编辑器 + 运行时都建(编辑器里可见预览)
	_build_floors()
	_build_grid_nav_and_walls()
	_build_landmarks()
	_build_torches()
	# 战斗逻辑:只在运行时建(编辑器里不跑刷怪/出口/落点,避免编辑器误触发)
	if not Engine.is_editor_hint():
		_build_encounters()
		_build_exit()
		call_deferred("_place_player")

func _build_torches() -> void:
	var post := _mat(Color(0.22, 0.2, 0.18))
	for t in TORCHES:
		var x: float = t[0]
		var z: float = t[1]
		_cylinder(_at(x, z, 0.7), 0.25, 1.4, post)
		var l := OmniLight3D.new()
		l.position = _at(x, z, 1.6)
		l.light_color = Color(1.0, 0.6, 0.25)
		l.light_energy = 2.4
		l.omni_range = 10.0
		add_child(l)

# 把玩家放到缩放后的入口(让 play 包装与 SCALE 解耦)
func _place_player() -> void:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0 and ps[0] is Node3D:
		(ps[0] as Node3D).global_position = _at(PLAYER_SPAWN.x, PLAYER_SPAWN.z, PLAYER_SPAWN.y)

# ---------------------------------------------------------------------------
func _mat(c: Color, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.6
	return m

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, collision: bool) -> StaticBody3D:
	# pos 为 WALK 坐标(x/z 乘 SCALE);size 为绝对尺寸(传入时已按需含 SCALE)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = Vector3(pos.x * SCALE, pos.y, pos.z * SCALE)
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	if collision:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
	return body

func _build_floors() -> void:
	var mat := _mat(Color(0.18, 0.18, 0.21))
	for r in WALK:
		var cx: float = (float(r[0]) + float(r[1])) * 0.5
		var cz: float = (float(r[2]) + float(r[3])) * 0.5
		var sx: float = float(r[1] - r[0]) * SCALE
		var sz: float = float(r[3] - r[2]) * SCALE
		_box(Vector3(cx, -0.2, cz), Vector3(sx, 0.4, sz), mat, true)

# ---- 栅格 navmesh + 自动墙 ----
func _walk_at(cx: float, cz: float) -> bool:
	for r in WALK:
		if cx > r[0] and cx < r[1] and cz > r[2] and cz < r[3]:
			return true
	return false

func _build_grid_nav_and_walls() -> void:
	var xset := {}
	var zset := {}
	for r in WALK:
		xset[r[0]] = true
		xset[r[1]] = true
		zset[r[2]] = true
		zset[r[3]] = true
	var xs: Array = xset.keys()
	xs.sort()
	var zs: Array = zset.keys()
	zs.sort()

	var verts: Array[Vector3] = []
	var vmap := {}
	var polys: Array = []
	var wall_mat := _mat(Color(0.30, 0.28, 0.26))

	for i in range(xs.size() - 1):
		for j in range(zs.size() - 1):
			var x0: float = xs[i]
			var x1: float = xs[i + 1]
			var z0: float = zs[j]
			var z1: float = zs[j + 1]
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			if not _walk_at(cx, cz):
				continue
			# navmesh 四边形(共享顶点)
			var p := PackedInt32Array([
				_vid(verts, vmap, x0, z0), _vid(verts, vmap, x1, z0),
				_vid(verts, vmap, x1, z1), _vid(verts, vmap, x0, z1)])
			polys.append(p)
			# 与不可走邻格的边界 → 墙
			if not _cell_walk(xs, zs, i - 1, j):
				_wall(Vector3(x0, 1.2, cz), Vector3(0.5, 2.4, (z1 - z0) * SCALE), wall_mat)
			if not _cell_walk(xs, zs, i + 1, j):
				_wall(Vector3(x1, 1.2, cz), Vector3(0.5, 2.4, (z1 - z0) * SCALE), wall_mat)
			if not _cell_walk(xs, zs, i, j - 1):
				_wall(Vector3(cx, 1.2, z0), Vector3((x1 - x0) * SCALE, 2.4, 0.5), wall_mat)
			if not _cell_walk(xs, zs, i, j + 1):
				_wall(Vector3(cx, 1.2, z1), Vector3((x1 - x0) * SCALE, 2.4, 0.5), wall_mat)

	var nm := NavigationMesh.new()
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.vertices = verts
	nm.polygons = polys
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	nav_region.navigation_mesh = nm
	add_child(nav_region)

func _vid(verts: Array, vmap: Dictionary, x: float, z: float) -> int:
	var key := "%s_%s" % [x, z]
	if not vmap.has(key):
		vmap[key] = verts.size()
		verts.append(Vector3(x * SCALE, 0.05, z * SCALE))
	return vmap[key]

func _cell_walk(xs: Array, zs: Array, i: int, j: int) -> bool:
	if i < 0 or i >= xs.size() - 1 or j < 0 or j >= zs.size() - 1:
		return false
	return _walk_at((xs[i] + xs[i + 1]) * 0.5, (zs[j] + zs[j + 1]) * 0.5)

func _wall(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	# pos.x/z 为 WALK 坐标,需乘 SCALE;size 已含 SCALE(传入时算好)
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = Vector3(pos.x * SCALE, pos.y, pos.z * SCALE)
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)

# ---- 地标 ----
func _at(x: float, z: float, y: float = 0.0) -> Vector3:
	return Vector3(x * SCALE, y, z * SCALE)

func _build_landmarks() -> void:
	for lm in LANDMARKS:
		var x: float = lm[0]
		var z: float = lm[1]
		match String(lm[2]):
			"portal_in":
				_portal(x, z, Color(0.3, 0.9, 0.5), 2.0)
			"portal_out":
				_portal(x, z, Color(0.3, 0.6, 1.0), 4.5)   # 目标门更亮,远端可见
			"beacon":
				# 高光柱:穿过长廊黑暗,在远处成为亮点(纵深牵引)
				_cylinder(_at(x, z, 5.0), 0.6, 10.0, _mat(Color(0.4, 0.7, 1.0), true))
				var bl := OmniLight3D.new()
				bl.position = _at(x, z, 6.0)
				bl.light_color = Color(0.4, 0.7, 1.0)
				bl.light_energy = 5.0
				bl.omni_range = 28.0
				add_child(bl)
			"gear":
				_gear(x, z)
			"chest":
				_box(Vector3(x, 0.4, z), Vector3(1.4, 0.8, 1.0), _mat(Color(0.85, 0.62, 0.15), true), true)
			"boss_pillar":
				# 中心柱 + 环形台座(Boss厅中心特征)
				_cylinder(_at(x, z, 0.0), 2.4, 0.3, _mat(Color(0.22, 0.2, 0.18)))
				_cylinder(_at(x, z, 1.6), 1.0, 3.2, _mat(Color(0.45, 0.1, 0.1), true))
			"waypoint":
				_cylinder(_at(x, z, 0.05), 1.6, 0.1, _mat(Color(0.4, 0.4, 0.5), true))

func _portal(x: float, z: float, c: Color, energy: float) -> void:
	# 拱门 + 发光门面
	var stone := _mat(Color(0.4, 0.38, 0.34))
	_box(Vector3(x - 1.6, 1.6, z), Vector3(0.7, 3.2, 0.7), stone, true)
	_box(Vector3(x + 1.6, 1.6, z), Vector3(0.7, 3.2, 0.7), stone, true)
	_box(Vector3(x, 3.4, z), Vector3(4.0, 0.6, 0.7), stone, false)
	var mi := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(2.6, 2.8, 0.2)
	pm.material = _mat(c, true)
	mi.mesh = pm
	mi.position = _at(x, z, 1.6)
	add_child(mi)
	var l := OmniLight3D.new()
	l.position = _at(x, z, 1.6)
	l.light_color = c
	l.light_energy = energy
	l.omni_range = 10.0 + energy * 2.0
	add_child(l)

func _gear(x: float, z: float) -> void:
	var mat := _mat(Color(0.55, 0.5, 0.2), true)
	_cylinder(_at(x, z, 0.9), 1.3, 0.4, mat)
	_cylinder(_at(x, z, 0.45), 0.4, 0.9, _mat(Color(0.3, 0.28, 0.2)))

func _cylinder(pos: Vector3, radius: float, h: float, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = h
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	add_child(mi)

# ---- 遭遇 ----
func _build_encounters() -> void:
	for e in ENCOUNTERS:
		var area := Area3D.new()
		area.set_script(SPAWN_TRIGGER)
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		area.position = _at(e[0], e[1], 0.5)
		area.set("enemy_scene", ENEMY)
		area.set("enemy_data", CORPSE)
		area.set("count", int(e[2]))
		area.set("formation", String(e[3]))
		area.set("spawn_radius", float(e[4]) * SCALE)
		area.set("spawn_at_self", true)
		area.set("one_shot", true)
		area.set("target_player", bool(e[5]))
		add_child(area)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 3.5
		cs.shape = sh
		area.add_child(cs)

func _build_exit() -> void:
	# 出口设在 Boss 厅深处(击杀后出关占位)
	var area := Area3D.new()
	area.set_script(LEVEL_EXIT)
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.position = _at(80, 78, 0.5)
	area.set("level_id", "L2_depths")
	area.set("next_hint", "下一层")
	add_child(area)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3, 2, 3)
	cs.shape = sh
	area.add_child(cs)
