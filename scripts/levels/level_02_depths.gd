@tool
extends Node3D

# L2 ·「痛苦回廊」白盒 —— 按提供的蓝图(平面图)解读搭建的大型地牢白盒。
# @tool:几何在编辑器里也会构建(可见预览);战斗部分(刷怪/出口/落点)仅运行时。
# 改了 WALK/SCALE 等数组后:在编辑器里重新打开本场景(或重载脚本)即可刷新预览。
# 蓝图解读(轴对齐近似,北=−Z=上):
#   西门(入口拱门) → 西廊 → 中央枢纽(十字) → 三向分叉:
#     · 北:长北廊(纵深)→ 上中室 / 北门(纵深尽端)
#     · 西南:死胡同(小圆室)
#     · 东:东廊 → 齿轮室 → 右侧环路(绕中心实体)→ Boss厅(中心柱)
#   下环路:枢纽南廊 → 南长廊 → 汇入 Boss 入口,与「东路」形成大环路。
# V3.0 大秘境清理:已移除地图内全部传送门 + 宝箱 + 机关,仅保留入口;终点=守门人传送门(进度满由 RiftManager 激活)。
#
# 导航:rect→栅格 navmesh 编译器(矩形栅格化→共享顶点四边形,连通由构造保证);
#       墙体由同一栅格的「可走/不可走」边界自动生成。全部 collision_layer=4。
#
# 规模:SCALE 统一缩放,按 ~6 分钟单程通关校准(见 verify_level02.gd 测的临界路径长度)。

const SCALE: float = 1.5   # 统一缩放:房间/走廊放大,避免局促;临界路径随之拉长
const ENEMY := preload("res://scenes/enemies/enemy_zombie.tscn")
const CORPSE := preload("res://scripts/entities/data/walking_corpse.tres")
const ARCHER_DATA := preload("res://scripts/entities/data/skeleton_archer.tres")
const BLOATED_DATA := preload("res://scripts/entities/data/bloated_corpse.tres")

# 各遭遇点的敌人种类(对应 ENCOUNTERS 顺序;混入 Synty 敌人做视觉多样化,数值仍用 CORPSE)
# V3.0:1/3/6 换成弓手(远程驻射),5/8 换成肿胀走尸(自爆),其他保留视觉变体走基础近战
const ENCOUNTER_ENEMY := [
	preload("res://scenes/enemies/enemy_skeleton_slave_01.tscn"),    # 0 西廊·首遇
	preload("res://scenes/enemies/enemy_archer.tscn"),               # 1 枢纽 — 骷髅弓手
	preload("res://scenes/enemies/enemy_skeleton_soldier_01.tscn"),  # 2 枢纽→东 过渡
	preload("res://scenes/enemies/enemy_archer.tscn"),               # 3 东廊 — 骷髅弓手
	preload("res://scenes/enemies/enemy_skeleton_soldier_02.tscn"),  # 4 齿轮室
	preload("res://scenes/enemies/enemy_bloated.tscn"),              # 5 右环·南 — 肿胀自爆
	preload("res://scenes/enemies/enemy_archer.tscn"),               # 6 北廊纵深 — 骷髅弓手
	preload("res://scenes/enemies/enemy_hero_knight_male.tscn"),     # 7 北门守卫
	preload("res://scenes/enemies/enemy_bloated.tscn"),              # 8 南长廊 — 肿胀自爆
	preload("res://scenes/enemies/enemy_goblin_warchief.tscn"),      # 9 Boss 入口廊
	preload("res://scenes/enemies/enemy_skeleton_knight.tscn"),      # 10 Boss 厅尸潮(高潮)
]
# 数据资源(与 ENCOUNTER_ENEMY 对齐):弓手用 archer 数值,自爆用 bloated 数值,其他走尸数值
const ENCOUNTER_DATA := [
	CORPSE,        # 0
	ARCHER_DATA,   # 1
	CORPSE,        # 2
	ARCHER_DATA,   # 3
	CORPSE,        # 4
	BLOATED_DATA,  # 5
	ARCHER_DATA,   # 6
	CORPSE,        # 7
	BLOATED_DATA,  # 8
	CORPSE,        # 9
	CORPSE,        # 10
]
const SPAWN_TRIGGER := preload("res://scripts/components/spawn_trigger.gd")
const LEVEL_EXIT := preload("res://scripts/components/level_exit.gd")

# 可走矩形 [xmin, xmax, zmin, zmax](相邻矩形需重叠/相接,栅格才连通)
const WALK := [
	[-92, -74, -16, 2],    # W1 西门(入口)
	[-78, -44, -6, 2],     # W2 西廊
	[-44, -18, -2, 30],    # H  中央枢纽
	[-40, -30, -70, 4],    # N1 长北廊(纵深)
	[-50, -22, -86, -66],  # NP 北门(纵深尽端)
	[-30, 2, -52, -28],    # UC 上中室(分隔室)
	[-46, -30, 26, 40],    # T1 西南廊
	[-78, -46, 24, 44],    # TR 死胡同(支线小室)
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

# 地标 [x, z, kind]   kind: entrance / boss_pillar / waypoint
# V3.0 大秘境清理:移除 portal_in/portal_out(传送门)、chest(宝箱)、gear(机关)、beacon(原北门牵引);仅保留入口(改纯拱门·无传送语义);守门人传送门由 RiftManager 进度满激活(非地图装饰)。
const LANDMARKS := [
	[-83, -7, "entrance"],     # 西门入口(纯拱门·仅保留入口)
	[67, 67, "boss_pillar"],   # Boss 厅中心柱(守门人房入口前地标·装饰发光)
	[-31, 14, "waypoint"],     # 枢纽地标(装饰)
]

# 长廊串灯坐标 [x, z](每约 18-22u 一盏暖光,把"纸面纵深"换成"一段段看得见的推进")
const TORCHES := [
	[-35, -58], [-35, -40], [-35, -22], [-35, -4],   # N1 长北廊
	[-30, 54], [-10, 54], [10, 54], [30, 54],         # S2 南长廊
]

# 哥特结构件 [x, z, kind, rot_deg]  kind: arch(拱门) / colonnade(列柱廊) / brazier(火盆) / altar(祭坛) / broken_wall(断墙)
# V3.0 形似优化:沿动线节点摆哥特白盒结构(拱门框景 / 列柱廊 / 火盆引导 / 祭坛 / 断墙)。
# V3.0 防穿模:立柱/盆座/断墙=碰撞实体(_pillar / StaticBody);横梁/盖板/柱头/祭石=无碰撞(_cylinder / _deco_box)。
#   柱距(列柱 4u)>玩家半径,不挡主路;navmesh(WALK)未抠洞,敌人同 OBSTACLES 物理滑动绕行。
const STRUCTURES := [
	[-61, -2, "colonnade", 0],    # 西廊·列柱廊(沿廊框景)
	[-31, 0, "arch", 0],          # 枢纽北口·拱门(框长北廊纵深)
	[-62, 34, "altar", 0],        # 西南死胡同·祭坛(原宝藏室→祭坛室,给死路视觉目的)
	[-15, 20, "arch", 90],        # 东廊入口·拱门
	[22, 12, "broken_wall", 0],   # 齿轮室·断墙(破败感)
	[44, 38, "colonnade", 0],     # 右环·南·列柱廊
	[49, 46, "arch", 0],          # Boss 入口廊·宏伟门廊(框守门人厅)
	[58, 67, "colonnade", 90],    # Boss 厅·西侧列柱
	[76, 67, "colonnade", 90],    # Boss 厅·东侧列柱
	[-35, -28, "brazier", 0],     # 长北廊·大火盆(纵深引导)
	[-36, 50, "brazier", 0],      # 南长廊·大火盆
]

# 碰撞立柱(阻挡物)[x, z, radius]  破开大空间 + 给弓系风筝掩体 / 破精英弓手视线
# ⚠ 白盒阶段:立柱有物理碰撞但 navmesh(WALK)未抠洞 → 敌人 NavAgent 直线会贴柱·靠物理滑动绕行(可接受);
#   若需精确绕行,后续给柱加 NavigationObstacle3D 或在栅格编译器里挖洞(交接)。radius=世界单位,位置=WALK 坐标。
const OBSTACLES := [
	[-38, 8, 1.4],    # 枢纽·西北柱
	[-24, 20, 1.4],   # 枢纽·东南柱
	[-8, 17, 1.2],    # 东廊·错位柱(chicane 逼走位)
	[2, 23, 1.2],     # 东廊·错位柱
	[16, 22, 1.3],    # 齿轮室·柱
	[28, 14, 1.3],    # 齿轮室·柱
	[38, 38, 1.3],    # 右环·南·柱
	[50, 38, 1.3],    # 右环·南·柱
	[62, 62, 1.5],    # Boss 厅·风筝柱·西南
	[72, 62, 1.5],    # Boss 厅·风筝柱·东南
	[62, 72, 1.5],    # Boss 厅·风筝柱·西北
	[72, 72, 1.5],    # Boss 厅·风筝柱·东北
]

# 遭遇 [x, z, count, formation, radius, surround]
# 注:surround 半径不可超过所在走廊半宽(否则刷进墙) → 仅用于开阔 Boss 厅;
#     窄廊用 cluster/line。东路主线数量单调爬升,Boss 厅为高潮。
# V3.0 大秘境:取消等级成长,怪物用固定值(数值表/rift_monsters.csv);数量按进度条权重单调爬升(白怪+1.0/蓝名+5.0/黄名+8.0,总≈100~110,见 大秘境-单局固定数值与关卡配置.md §6.3)。
# 当前白盒所有原型都 spawn enemy_zombie;战斗① 出齐 6 原型场景后按注释替换 enemy_scene。
const ENCOUNTERS := [
	[-60, -2, 8, "cluster", 6, false],   # 西门/西廊 开场(走尸5+疯犬3)
	[-31, 14, 6, "cluster", 5, false],   # 枢纽(走尸4+弓手2)
	[-15, 18, 4, "line", 5, false],      # 枢纽→东 过渡
	[-3, 20, 6, "line", 5, false],       # 东廊(走尸4+弓手2)
	[22, 18, 4, "cluster", 5, false],    # 齿轮室(走尸3+蓝名1·精英)
	[44, 38, 7, "cluster", 4, false],    # 右环·南(肿胀2+盾兵2+走尸3·破盾/自爆教学)
	[-35, -40, 6, "cluster", 5, false],  # 北廊纵深(走尸4+弓手2)
	[-36, -78, 4, "cluster", 5, false],  # 北门守卫(黄名1+扈从骷髅3·首领点·扈从=敌随从非玩家)
	[10, 54, 5, "line", 5, false],       # 南长廊 下环(召唤者1+走尸4)
	[49, 48, 5, "line", 5, false],       # Boss入口廊(蓝名1+走尸4)
	[67, 67, 12, "surround", 7, true],   # 终前尸潮(12环绕)·进度满→过守门人传送门去Boss房
	# ── 关卡C 混编追加(逼弓系风筝·配 OBSTACLES 立柱掩体;占位 spawn 走尸,战斗① 按注释绑对应怪种 AI/数据)──
	[-34, 18, 3, "cluster", 5, false],   # 枢纽·墓园疯犬群(高速冲锋逼翻滚·绕 O1/O2 柱拉开)
	[-26, 10, 2, "line", 5, false],      # 枢纽·骷髅弓手(远程驻射逼走位·用 O1/O2 柱挡射线)
	[-3, 22, 2, "cluster", 4, false],    # 东廊·肿胀走尸(自爆逼站位·穿 O3/O4 chicane)
	[44, 34, 3, "cluster", 4, false],    # 右环·南·墓园疯犬(冲锋·绕 O7/O8 柱)
	[67, 60, 3, "line", 6, false],       # Boss厅·骷髅弓手(守门人战远程压制·绕 O9~O12 风筝柱)
]

const PLAYER_SPAWN := Vector3(-83, 0, -7)   # 西门

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
	# 视觉几何:编辑器 + 运行时都建(编辑器里可见预览)
	_build_floors()
	_build_grid_nav_and_walls()
	_build_landmarks()
	_build_torches()
	_build_structures()
	_build_obstacles()
	# 战斗逻辑:只在运行时建(编辑器里不跑刷怪/出口/落点,避免编辑器误触发)
	if not Engine.is_editor_hint():
		# V3.0:遭遇改「敌人集团蓝图」手动摆放(scenes/enemies/groups/*.tscn → scenes/levels/level_02_encounters.tscn,
		# 已由 level_02_play.tscn 实例化)。不再脚本生成固定位置/数量;下方 ENCOUNTERS/ENCOUNTER_ENEMY 常量保留仅供参考。
		# 需临时回退脚本刷怪:取消下一行注释即可。
		#_build_encounters()
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
			"entrance":
				_entrance(x, z)   # 纯入口拱门(无传送语义/无发光门面)
			"boss_pillar":
				# 中心柱 + 环形台座(Boss厅中心特征)
				_cylinder(_at(x, z, 0.0), 2.4, 0.3, _mat(Color(0.22, 0.2, 0.18)))
				_cylinder(_at(x, z, 1.6), 1.0, 3.2, _mat(Color(0.45, 0.1, 0.1), true))
			"waypoint":
				_cylinder(_at(x, z, 0.05), 1.6, 0.1, _mat(Color(0.4, 0.4, 0.5), true))

func _entrance(x: float, z: float) -> void:
	# 纯入口拱门:两立柱 + 顶横梁(石材·无发光门面/无传送语义);暖光示意入口
	var stone := _mat(Color(0.4, 0.38, 0.34))
	_box(Vector3(x - 1.6, 1.6, z), Vector3(0.7, 3.2, 0.7), stone, true)
	_box(Vector3(x + 1.6, 1.6, z), Vector3(0.7, 3.2, 0.7), stone, true)
	_box(Vector3(x, 3.4, z), Vector3(4.0, 0.6, 0.7), stone, false)
	var l := OmniLight3D.new()
	l.position = _at(x, z, 2.4)
	l.light_color = Color(1.0, 0.7, 0.4)
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

# ---- 哥特结构件(立柱/盆座/断墙=碰撞实体防穿模·横梁/盖板/顶饰=无碰撞·@tool 可预览)----
func _deco_box(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	# 无碰撞装饰盒(纯 MeshInstance,不建 StaticBody);pos 走 WALK 坐标(x/z×SCALE)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = Vector3(pos.x * SCALE, pos.y, pos.z * SCALE)
	add_child(mi)

func _build_structures() -> void:
	var stone := _mat(Color(0.40, 0.38, 0.34))
	for s in STRUCTURES:
		var x: float = s[0]
		var z: float = s[1]
		var rot: float = deg_to_rad(float(s[3]))
		match String(s[2]):
			"arch":
				_build_arch(x, z, rot, stone)
			"colonnade":
				_build_colonnade(x, z, rot, stone)
			"brazier":
				_build_brazier(x, z)
			"altar":
				_build_altar(x, z, stone)
			"broken_wall":
				_build_broken_wall(x, z, rot, stone)

func _build_arch(x: float, z: float, rot: float, mat: StandardMaterial3D) -> void:
	# 拱门:两立柱 + 顶横梁(无碰撞);rot 控制跨度方向
	var w := 3.0
	var ph := 4.5
	var dx := cos(rot)
	var dz := sin(rot)
	for sgn in [-1.0, 1.0]:
		var px: float = x + dx * w * sgn
		var pz: float = z + dz * w * sgn
		_pillar(px, pz, 0.45, ph, mat)   # 立柱带碰撞(防穿模);横梁仍无碰撞(走人头顶)
	var beam := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3((w * 2.0 + 0.9) * SCALE, 0.7, 0.7)
	bm.material = mat
	beam.mesh = bm
	beam.position = _at(x, z, ph + 0.1)
	beam.rotation = Vector3(0, -rot, 0)
	add_child(beam)

func _build_colonnade(x: float, z: float, rot: float, mat: StandardMaterial3D) -> void:
	# 列柱廊:一排廊柱(柱身 + 柱头)+ 顶盖板(全无碰撞);沿 rot 方向排布
	var n := 5
	var gap := 4.0
	var ph := 5.0
	var dx := cos(rot)
	var dz := sin(rot)
	for i in range(n):
		var off: float = (float(i) - float(n - 1) * 0.5) * gap
		var cx: float = x + dx * off
		var cz: float = z + dz * off
		_pillar(cx, cz, 0.5, ph, mat)               # 廊柱带碰撞(防穿模);柱距 4u>玩家半径不挡主路
		_cylinder(_at(cx, cz, ph - 0.1), 0.7, 0.35, mat)   # 柱头(顶部·无碰撞)
	var span: float = float(n - 1) * gap + 1.6
	var cap := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(span * SCALE, 0.5, 1.4 * SCALE)
	bm.material = mat
	cap.mesh = bm
	cap.position = _at(x, z, ph + 0.3)
	cap.rotation = Vector3(0, -rot, 0)
	add_child(cap)

func _build_brazier(x: float, z: float) -> void:
	# 大火盆:盆座(带碰撞防穿模)+ 火光(无碰撞)+ 暖光(动线引导)
	_pillar(x, z, 0.7, 1.8, _mat(Color(0.22, 0.2, 0.18)))
	_cylinder(_at(x, z, 1.95), 0.85, 0.5, _mat(Color(1.0, 0.5, 0.15), true))
	var l := OmniLight3D.new()
	l.position = _at(x, z, 2.4)
	l.light_color = Color(1.0, 0.55, 0.2)
	l.light_energy = 3.2
	l.omni_range = 14.0
	add_child(l)

func _build_altar(x: float, z: float, mat: StandardMaterial3D) -> void:
	# 祭坛:矮台座(带碰撞防穿模)+ 发光祭石(无碰撞)+ 顶光
	_pillar(x, z, 1.2, 0.8, mat)
	_deco_box(Vector3(x, 1.1, z), Vector3(1.0, 0.6, 1.0), _mat(Color(0.5, 0.15, 0.15), true))
	var l := OmniLight3D.new()
	l.position = _at(x, z, 1.8)
	l.light_color = Color(0.9, 0.3, 0.25)
	l.light_energy = 2.2
	l.omni_range = 10.0
	add_child(l)

func _build_broken_wall(x: float, z: float, rot: float, mat: StandardMaterial3D) -> void:
	# 断墙:几段高低不齐的墙块(破败感);V3.0 加碰撞防穿模
	var dx := cos(rot)
	var dz := sin(rot)
	var heights := [2.6, 1.8, 2.2, 1.2]
	for i in range(heights.size()):
		var off: float = (float(i) - 1.5) * 1.6
		var h: float = heights[i]
		var sz := Vector3(1.5 * SCALE, h, 0.6 * SCALE)
		var seg := StaticBody3D.new()
		seg.collision_layer = 4
		seg.collision_mask = 0
		seg.position = _at(x + dx * off, z + dz * off, h * 0.5)
		seg.rotation = Vector3(0, -rot, 0)
		add_child(seg)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		bm.material = mat
		mi.mesh = bm
		seg.add_child(mi)
		var cs := CollisionShape3D.new()
		var shp := BoxShape3D.new()
		shp.size = sz
		cs.shape = shp
		seg.add_child(cs)

# ---- 碰撞立柱(阻挡物·破开大空间 / 弓系风筝掩体)----
func _pillar(x: float, z: float, r: float, h: float, mat: StandardMaterial3D) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = _at(x, z, h * 0.5)
	add_child(body)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = r
	cm.bottom_radius = r
	cm.height = h
	cm.material = mat
	mi.mesh = cm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = r
	sh.height = h
	cs.shape = sh
	body.add_child(cs)

func _build_obstacles() -> void:
	var mat := _mat(Color(0.34, 0.32, 0.30))
	for o in OBSTACLES:
		var x: float = o[0]
		var z: float = o[1]
		var r: float = o[2]
		_pillar(x, z, r, 3.5, mat)

# ---- 遭遇 ----
func _build_encounters() -> void:
	for i in ENCOUNTERS.size():
		var e = ENCOUNTERS[i]
		var area := Area3D.new()
		area.set_script(SPAWN_TRIGGER)
		area.collision_layer = 0
		area.collision_mask = 1
		area.monitoring = true
		area.position = _at(e[0], e[1], 0.5)
		area.set("enemy_scene", ENCOUNTER_ENEMY[i] if i < ENCOUNTER_ENEMY.size() else ENEMY)
		area.set("enemy_data", ENCOUNTER_DATA[i] if i < ENCOUNTER_DATA.size() else CORPSE)
		area.set("count", int(e[2]))
		area.set("formation", String(e[3]))
		area.set("spawn_radius", float(e[4]) * SCALE)
		area.set("spawn_at_self", true)
		area.set("one_shot", true)
		area.set("target_player", bool(e[5]))
		# V3.0:预放置 — level 加载即刷好怪在 IDLE 待机,玩家走近后由 enemy_base 自启 CHASE
		area.set("preplaced", true)
		add_child(area)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 3.5
		cs.shape = sh
		area.add_child(cs)

func _build_exit() -> void:
	# 守门人传送门:设在 Boss 厅深处;V3.0 由 RiftManager 进度满激活后切场景(非地图装饰传送门)
	var area := Area3D.new()
	area.set_script(LEVEL_EXIT)
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.position = _at(80, 78, 0.5)
	area.set("level_id", "L2_depths")
	area.set("next_hint", "守门人房(进度满·RiftManager 切场景)")
	add_child(area)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(3, 2, 3)
	cs.shape = sh
	area.add_child(cs)
