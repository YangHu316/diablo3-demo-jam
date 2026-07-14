@tool
extends Node3D

# ═══════════════════════════════════════════════════════════════════════════
# L3「CRYPTAL MAZE」白盒 — 依据用户提供的第二版俯瞰平面图复现(2026-07-14 V2)
# 编译器沿用 level_02_depths.gd 的 rect→栅格 navmesh 模式(矩形分割+边界自动立墙)。
#
# 平面图转写约定(V2 图):
#   · 参考图 10 px = 1 raw 单位;原点取图 (600,480)px → x=(px-600)/10, z=(py-480)/10
#   · 图上方 = 北 = -Z;白色=可走区域,黑色=背景;世界坐标 = raw × SCALE(1.5)
#   · 图中宝石/药瓶/矿石/岩石等图标全部忽略;仅保留右上角入口传送门(entrance+出生点);
#     左下红色门仅保留其凸口几何,不做地标
#   · 镂空(顶带矩形坑/中央竖槽/右中圆孔)= 环带矩形围出未覆盖区,编译器自动沿边立墙
#   · 梯桥(图中带横档的窄桥)= 窄走廊矩形
#
# 大结构(自西向东):
#   L1 左侧竖长串室(顶凸包→顶室→药水厅→下厅→左下斗篷厅)  LDA 梯桥→L2
#   L2 中左复合体:西北凸包+顶横厅(带矩形镂空)+中竖梯厅+中厅+蛇形迷宫(MZ)
#      +底部大厅(BR2)+红门凸口
#   C1 中央竖长厅(带竖槽镂空+南圆凸)  SPW/SPE 东西主干走廊
#   RC 右中复合体:顶圆丘(KN)+梯桥+主横带+中厅+圆形镂空环+下挂双瓣厅  LDR 梯桥→R3
#   R1 入口圆厅(右上·传送门)→LDE 梯桥→R2 右上大厅→颈→R3 右中厅→R4 右下大厅(西尾)
# ═══════════════════════════════════════════════════════════════════════════

const SCALE: float = 1.5

const LEVEL_EXIT := preload("res://scripts/components/level_exit.gd")

# 可走矩形 [xmin, xmax, zmin, zmax](raw 单位;相邻矩形需重叠/相接才连通)
const WALK := [
	# ── 左侧竖长串室 L1 ───────────────────────────────────────────
	[-45, -38, -30, -26],      # L1a 顶部凸包
	[-48, -36, -27, -21],      # L1b 顶室
	[-51, -36, -21, -13],      # L1c 药水厅(图标忽略)
	[-53, -38, -13, -4],       # L1d 下厅
	[-54, -44, -6, 4],         # L1e 左下斗篷厅(图标忽略)
	[-36, -31, -22, -18.5],    # LDA 梯桥:L1→L2 西北
	# ── 中左复合体 L2 ─────────────────────────────────────────────
	[-28, -22, -25, -20],      # L2k 西北凸包
	[-31, -4, -20, -18.5],     # L2n-N 顶横厅·北带
	[-31, -24, -18.5, -14],    # L2n-W 顶横厅·西带
	[-15, -4, -18.5, -14],     # L2n-E 顶横厅·东带(围出矩形镂空 x-24..-15,z-18.5..-14)
	[-31, -4, -14, -12],       # L2n-S 顶横厅·南带
	[-21, -14, -14, -5],       # L2s 中竖梯厅(顶横厅→中厅)
	[-26, -14, -5, 4.5],       # L2m 中厅
	[-8, -3.5, -13.5, -8.5],   # C1n 顶横厅东端→中央厅 竖颈
	# ── 蛇形迷宫 MZ(L2 西南,墙指交错) ────────────────────────────
	[-36, -33, -1, 14],        # MZ-W 西列
	[-33, -31, 10, 14],        # MZ-C 底部接口(墙1 x-33..-31,z-1..10 悬北)
	[-31, -29, -1, 14],        # MZ-M 中列
	[-29, -27.5, -1, 3],       # MZ-T 顶部接口(墙2 x-29..-27.5,z3..14 立南)
	[-27.5, -26, -1, 14],      # MZ-E 东列(北接中厅)
	# ── L2 底部 ───────────────────────────────────────────────────
	[-37, -19, 12, 24],        # BR2 底部大厅
	[-35, -28, 21, 28],        # RDN 红门凸口(仅几何,无地标)
	[-26, -19, 4.5, 12],       # L2se 中厅→底部大厅 东侧连接
	# ── 中央竖长厅 C1 ─────────────────────────────────────────────
	[-9.5, 1.5, -8.5, 1],      # C1a 上段(格栅图标忽略)
	[-9.5, -5.5, 1, 9],        # C1w 西带
	[-2, 1.5, 1, 9],           # C1e 东带(围出竖槽镂空 x-5.5..-2,z1..9)
	[-9, 1, 9, 15],            # C1s 南圆凸
	# ── 东西主干走廊 ──────────────────────────────────────────────
	[-14, -9, 1, 4.5],         # SPW 主干·西段(L2 中厅→C1)
	[1.5, 6.5, 1, 4.5],        # SPE 主干·东段(C1→RC)
	# ── 右中复合体 RC ─────────────────────────────────────────────
	[6, 34, -2.5, 5.5],        # RCb 主横带
	[9, 16, -14, -6.5],        # KN  顶圆丘
	[13, 16, -7, -2],          # LDK 梯桥:圆丘→主横带
	[9, 34, 5.5, 12],          # RCm 中厅
	[9, 17, 12, 15],           # RCr-W 圆孔环·西(圆孔 x17..21.5,z12..15,南口连瓣厅间隙=钥匙孔形)
	[21.5, 30, 12, 15],        # RCr-E 圆孔环·东
	[9, 19, 15, 16.5],         # RCr-SW 圆孔环·西南带
	[21.5, 30, 15, 16.5],      # RCr-SE 圆孔环·东南带(x19..21.5 留缝通瓣厅间隙)
	[9.5, 19, 16.5, 24],       # RCl-W 下挂西瓣厅
	[22, 30, 16.5, 24],        # RCl-E 下挂东瓣厅(两瓣间 x19..22 为黑隙,上通圆孔)
	[34, 38.5, 6.5, 11],       # LDR 梯桥:RC→R3(桥两端黑隙分离)
	# ── 右列 R ────────────────────────────────────────────────────
	[21, 33, -29, -20],        # R1 入口圆厅(传送门·玩家出生)
	[27, 30, -20.5, -16],      # LDE 梯桥:R1→R2
	[28.5, 49, -18, -1],       # R2 右上大厅(含东北凸)
	[24, 28.5, -17, -10.5],    # R2k 右上大厅·西侧凸包
	[30, 34, -2.5, -1],        # NRC R2↔RC 窄颈(存疑连接)
	[40, 45, -3, 2],           # NR3 R2→R3 颈
	[38.5, 53, 0, 13],         # R3 右中厅(西缘与 RC 之间黑隙,梯桥相连)
	[37, 53, 13, 28],          # R4 右下大厅
	[35, 42, 22, 29],          # R4t 右下·西尾
]

# 地标 [x, z, kind]  — 仅保留右上入口传送门;其余图标按要求忽略
const LANDMARKS := [
	[26.5, -25, "entrance"],   # 入口传送门(R1 圆厅内)
]

# 火把串(留空;氛围光照归美术阶段)
const TORCHES := []

const PLAYER_SPAWN := Vector3(26.5, 0, -23)   # R1 入口圆厅(传送门前)

var nav_region: NavigationRegion3D = null

func _ready() -> void:
	add_to_group("level")
	_rebuild()

func _rebuild() -> void:
	# 清掉上一次生成的几何(保留 .tscn 里手摆的灯光/环境),保证编辑器反复刷新不叠加
	for c in get_children():
		if c is DirectionalLight3D or c is WorldEnvironment:
			continue
		c.free()
	_build_floors()
	_build_grid_nav_and_walls()
	_build_torches()
	_build_landmarks()
	if not Engine.is_editor_hint():
		# 敌人生成点:与 L2 同规则,由「敌人集团蓝图」手摆进 play 场景,本脚本不生成。
		call_deferred("_place_player")

# 供俯拍/校验工具取世界包围盒(含 SCALE)
func get_world_bounds() -> Rect2:
	var xmin := INF; var xmax := -INF; var zmin := INF; var zmax := -INF
	for r in WALK:
		xmin = minf(xmin, r[0]); xmax = maxf(xmax, r[1])
		zmin = minf(zmin, r[2]); zmax = maxf(zmax, r[3])
	return Rect2(xmin * SCALE, zmin * SCALE, (xmax - xmin) * SCALE, (zmax - zmin) * SCALE)

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
	var mat := _mat(Color(0.72, 0.70, 0.66))   # 浅石板色(对齐参考图白色地面,俯拍易比对)
	for r in WALK:
		var cx: float = (float(r[0]) + float(r[1])) * 0.5
		var cz: float = (float(r[2]) + float(r[3])) * 0.5
		var sx: float = float(r[1] - r[0]) * SCALE
		var sz: float = float(r[3] - r[2]) * SCALE
		_box(Vector3(cx, -0.2, cz), Vector3(sx, 0.4, sz), mat, true)

# ---- 栅格 navmesh + 自动墙(同 L2 编译器) ----
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
	var wall_mat := _mat(Color(0.38, 0.36, 0.33))   # 石壁灰

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
			var p := PackedInt32Array([
				_vid(verts, vmap, x0, z0), _vid(verts, vmap, x1, z0),
				_vid(verts, vmap, x1, z1), _vid(verts, vmap, x0, z1)])
			polys.append(p)
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

# ---- 火把(可选氛围;当前留空) ----
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

# ---- 地标 ----
func _at(x: float, z: float, y: float = 0.0) -> Vector3:
	return Vector3(x * SCALE, y, z * SCALE)

func _build_landmarks() -> void:
	for lm in LANDMARKS:
		var x: float = lm[0]
		var z: float = lm[1]
		match String(lm[2]):
			"entrance":
				_entrance(x, z)

func _entrance(x: float, z: float) -> void:
	# 入口传送门标识:两立柱 + 顶横梁 + 暖光(几何占位;美术阶段换真传送门资产)
	var stone := _mat(Color(0.4, 0.38, 0.34))
	_box(Vector3(x - 1.6, 1.6, z), Vector3(0.7, 3.2, 0.7), stone, true)
	_box(Vector3(x + 1.6, 1.6, z), Vector3(0.7, 3.2, 0.7), stone, true)
	_box(Vector3(x, 3.4, z), Vector3(4.0, 0.6, 0.7), stone, false)
	var l := OmniLight3D.new()
	l.position = _at(x, z, 2.4)
	l.light_color = Color(1.0, 0.6, 0.25)
	l.light_energy = 2.0
	l.omni_range = 12.0
	add_child(l)

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
