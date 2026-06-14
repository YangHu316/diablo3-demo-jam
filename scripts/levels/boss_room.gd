@tool
extends Node3D

# Boss房「受难之室」白盒(屠夫)—— 八边形竞技场,放大面积给弓系风筝空间。
# 八边形 = 半展 R=18 的方形切 c=8 斜角;可走区 ≈1168 单位²(原方形 576 的 ~2 倍)。
# 8 顶点(X,Z):(-10,-18)(10,-18)(18,-10)(18,10)(10,18)(-10,18)(-18,10)(-18,-10)。
# 8 面墙(4 轴对齐+4 斜角)围出八边形,南面留 X[-3,3] 入口;导航=单八边形多边形(.tscn)。
# 几何 collision_layer=4;四角火炉为装饰(无碰撞,不挡走位)。屠夫从入口触发(白盒占位走尸)。

const ENEMY := preload("res://scenes/enemies/enemy_zombie.tscn")
const CORPSE := preload("res://scripts/entities/data/walking_corpse.tres")
const SPAWN_TRIGGER := preload("res://scripts/components/spawn_trigger.gd")

const PLAYER_SPAWN := Vector3(0, 0, 15)   # 南门入口内侧

func _ready() -> void:
	for c in get_children():
		if c is StaticBody3D or c is MeshInstance3D or c is OmniLight3D or (c is Area3D and c.get_script() == SPAWN_TRIGGER):
			c.free()
	_build()
	if not Engine.is_editor_hint():
		_build_boss()
		call_deferred("_place_player")

func _mat(col: Color, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.95
	if emissive:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.6
	return m

# 轴对齐墙/盒.
func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, col: bool) -> void:
	var b := StaticBody3D.new()
	b.collision_layer = 4
	b.collision_mask = 0
	b.position = pos
	add_child(b)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	b.add_child(mi)
	if col:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		b.add_child(cs)

# 斜角墙:a,b 为 (X,Z) 端点;绕 Y 旋转对齐.
func _wall_diag(a: Vector2, b: Vector2, mat: StandardMaterial3D) -> void:
	var mid := (a + b) * 0.5
	var d := b - a
	var b2 := StaticBody3D.new()
	b2.collision_layer = 4
	b2.collision_mask = 0
	b2.position = Vector3(mid.x, 1.2, mid.y)
	b2.rotation = Vector3(0, atan2(-d.y, d.x), 0)
	add_child(b2)
	var sz := Vector3(d.length() + 1.0, 2.4, 0.5)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	bm.material = mat
	mi.mesh = bm
	b2.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = sz
	cs.shape = sh
	b2.add_child(cs)

func _build() -> void:
	# 地面(方形覆盖八边形包围盒;角外余料被斜墙挡住)
	_box(Vector3(0, -0.2, 0), Vector3(37, 0.4, 37), _mat(Color(0.16, 0.14, 0.15)), true)
	# 中心象限地板(烧地板机制可视;微抬+暗红)
	var quad := _mat(Color(0.3, 0.12, 0.1))
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			_box(Vector3(sx * 7.5, 0.02, sz * 7.5), Vector3(14, 0.06, 14), quad, false)
	# 8 面墙
	var wm := _mat(Color(0.26, 0.22, 0.22))
	_box(Vector3(0, 1.2, -18), Vector3(21, 2.4, 0.5), wm, true)        # 北(顶)
	_box(Vector3(18, 1.2, 0), Vector3(0.5, 2.4, 21), wm, true)         # 东(右)
	_box(Vector3(-18, 1.2, 0), Vector3(0.5, 2.4, 21), wm, true)        # 西(左)
	_box(Vector3(-6.5, 1.2, 18), Vector3(7, 2.4, 0.5), wm, true)       # 南左(入口在 X[-3,3])
	_box(Vector3(6.5, 1.2, 18), Vector3(7, 2.4, 0.5), wm, true)        # 南右
	_wall_diag(Vector2(10, -18), Vector2(18, -10), wm)                 # 东北斜
	_wall_diag(Vector2(18, 10), Vector2(10, 18), wm)                   # 东南斜
	_wall_diag(Vector2(-10, 18), Vector2(-18, 10), wm)                 # 西南斜
	_wall_diag(Vector2(-18, -10), Vector2(-10, -18), wm)               # 西北斜
	# 四角火炉(装饰·无碰撞·不挡走位)+ 暖光
	for p in [Vector2(13, -13), Vector2(13, 13), Vector2(-13, 13), Vector2(-13, -13)]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.7; cm.bottom_radius = 0.9; cm.height = 1.6
		cm.material = _mat(Color(0.9, 0.4, 0.12), true)
		mi.mesh = cm
		mi.position = Vector3(p.x, 0.8, p.y)
		add_child(mi)
		var l := OmniLight3D.new()
		l.position = Vector3(p.x, 2.0, p.y)
		l.light_color = Color(1.0, 0.55, 0.2); l.light_energy = 3.0; l.omni_range = 16.0
		add_child(l)

func _build_boss() -> void:
	var area := Area3D.new()
	area.set_script(SPAWN_TRIGGER)
	area.collision_layer = 0
	area.collision_mask = 1
	area.monitoring = true
	area.position = Vector3(0, 0.5, 12)   # 入口内侧触发
	area.set("enemy_scene", ENEMY)
	area.set("enemy_data", CORPSE)
	area.set("count", 1)
	area.set("formation", "cluster")
	area.set("spawn_radius", 1.0)
	area.set("spawn_at_self", false)
	area.set("spawn_center_path", NodePath("../BossSpawn"))
	area.set("one_shot", true)
	area.set("target_player", false)
	add_child(area)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 3.0
	cs.shape = sh
	area.add_child(cs)

func _place_player() -> void:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0 and ps[0] is Node3D:
		(ps[0] as Node3D).global_position = PLAYER_SPAWN
