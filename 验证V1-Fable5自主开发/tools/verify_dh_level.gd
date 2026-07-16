extends SceneTree

# 验证V1 · 关卡校验:
#   ① 全部敌人生成器位于可走区内(中心可走+净空达标) —— 生成范围不越墙的硬校验
#   ② 敌人数值资源加载且未被 export 范围截断(巨像 11000)
#   ③ 美术场景可加载,导航网格面数正常
#   ④ CSG 墙体隐藏后碰撞仍在(美术层隐藏白盒墙的前提)
# Run: Godot --headless --path . --script res://验证V1-Fable5自主开发/tools/verify_dh_level.gd

const WalkableArea := preload("res://验证V1-Fable5自主开发/scripts/walkable_area.gd")
const PLAY := "res://验证V1-Fable5自主开发/scenes/level_03_dh_play.tscn"
const ART := "res://验证V1-Fable5自主开发/scenes/level_03_csg_art.tscn"

var _fails := 0
var _frames := 0
var _csg: Node = null

func _init() -> void:
	physics_frame.connect(_on_phys)

func _on_phys() -> void:
	_frames += 1
	if _frames == 1:
		_static_checks()
		var csg_ps := load(ART) as PackedScene   # 副本场景(墙已隐藏,碰撞应保留)
		_csg = csg_ps.instantiate()
		get_root().add_child(_csg)
	elif _frames == 20:
		_collision_check()
		print("=== ", "VERIFY OK" if _fails == 0 else "VERIFY FAIL(%d)" % _fails, " ===")
		quit(1 if _fails > 0 else 0)

func _ok(cond: bool, label: String) -> void:
	if not cond:
		_fails += 1
	print("  ", "OK " if cond else "FAIL ", label)

func _static_checks() -> void:
	print("=== 验证V1 关卡校验 ===")
	# ① 生成器布点(读 play 场景文本,逐生成器验证中心点)
	var txt := FileAccess.get_file_as_string(ProjectSettings.globalize_path(PLAY))
	var re := RegEx.new()
	re.compile("\\[node name=\"(Sp[^\"]+)\"[^\\]]*\\]\\r?\\ntransform = Transform3D\\([^)]*, ([-0-9.]+), ([-0-9.]+), ([-0-9.]+)\\)\\r?\\nenemy_type = \"([a-z_]+)\"\\r?\\ncount = (\\d+)\\r?\\nradius = ([0-9.]+)")
	var total_enemies := 0
	var bad := 0
	var found := 0
	for m in re.search_all(txt):
		found += 1
		var nm := m.get_string(1)
		var x := float(m.get_string(2))
		var z := float(m.get_string(4))
		var cnt := int(m.get_string(6))
		total_enemies += cnt
		var p := Vector2(x, z)
		var w: bool = WalkableArea.is_walkable(p)
		var cl: float = WalkableArea.clearance(p)
		if not w or cl < 1.0:
			bad += 1
			print("    ✗ ", nm, " @(", x, ",", z, ") walkable=", w, " clear=%.2f" % cl)
	_ok(found >= 30, "生成器解析数量 = %d (≥30)" % found)
	_ok(bad == 0, "全部生成器中心可走且净空≥1m (违规 %d)" % bad)
	print("    敌人总数(配置) = ", total_enemies)
	# 采样复核:sample_in_disc 输出必在可走区
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var sample_bad := 0
	for i in 200:
		var c := Vector2(rng.randf_range(-70, 70), rng.randf_range(-38, 38))
		if not WalkableArea.is_walkable(c):
			continue
		var p2: Vector2 = WalkableArea.sample_in_disc(rng, c, 5.0, 0.8)
		if not WalkableArea.is_walkable(p2):
			sample_bad += 1
	_ok(sample_bad == 0, "sample_in_disc 200 次采样全部落在可走区 (违规 %d)" % sample_bad)
	# ② 敌人数值资源
	var colossus := load("res://验证V1-Fable5自主开发/scripts/enemy_data/dh_crystal_colossus.tres")
	_ok(colossus != null and int(colossus.get("max_health")) == 11000, "晶簇巨像 HP=11000 未被截断")
	var names := ["dh_rotwalker", "dh_crypthound", "dh_marrow_archer", "dh_blightbloat", "dh_crypt_warden", "dh_crystal_colossus"]
	var loaded := 0
	for n in names:
		if load("res://验证V1-Fable5自主开发/scripts/enemy_data/%s.tres" % n) != null:
			loaded += 1
	_ok(loaded == 6, "敌人数值资源 6/6 加载")
	# ③ 美术场景与导航
	var art := (load(ART) as PackedScene).instantiate()
	var reg := art.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	_ok(reg != null and reg.navigation_mesh.get_polygon_count() > 2000, "导航网格面数 = %d (>2000)" % (reg.navigation_mesh.get_polygon_count() if reg else -1))
	art.free()

func _collision_check() -> void:
	# ④ 墙隐藏后碰撞仍在:从入口厅外向内打射线,应被北墙挡住
	var space := get_root().get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(44.3, 1.2, -48.0), Vector3(44.3, 1.2, -30.0))
	q.collision_mask = 4
	var hit := space.intersect_ray(q)
	_ok(not hit.is_empty(), "CSG 墙隐藏后碰撞仍在(入口北墙射线命中 %s)" % (str(hit.get("position", "")) if not hit.is_empty() else "无"))
	# 地板碰撞:向下射线
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(43.6, 2.0, -30.0), Vector3(43.6, -2.0, -30.0))
	q2.collision_mask = 4
	var hit2 := space.intersect_ray(q2)
	_ok(not hit2.is_empty(), "地板碰撞正常(向下射线命中)")
