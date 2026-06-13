extends SceneTree

# 校验 L2 大关卡:加载/几何/导航连通 + 测临界路径长度→估通关步行时长.
# Run: Godot --headless --path . --script res://tools/verify_level02.gd

const PLAYER_SPEED := 7.0
const SCALE := 1.5   # 与 level_02_depths.gd 同步

var _lvl: Node = null
var _frames: int = 0

func _s(x: float, z: float) -> Vector3:
	return Vector3(x * SCALE, 0.2, z * SCALE)

func _init() -> void:
	physics_frame.connect(_on_phys)

func _on_phys() -> void:
	_frames += 1
	if _frames == 1:
		var ps := load("res://scenes/levels/level_02_depths.tscn")
		if ps == null:
			printerr("FAIL: level_02_depths.tscn 未加载"); quit(1); return
		_lvl = ps.instantiate()
		get_root().add_child(_lvl)
		if load("res://scenes/levels/level_02_play.tscn") == null:
			printerr("WARN: level_02_play.tscn 解析失败")
	elif _frames == 30:
		_check()
		quit()

func _len(path: PackedVector3Array) -> float:
	var d := 0.0
	for i in range(1, path.size()):
		d += path[i].distance_to(path[i - 1])
	return d

func _route(map: RID, label: String, a: Vector3, b: Vector3) -> float:
	var p := NavigationServer3D.map_get_path(map, a, b, true)
	var endd := (p[p.size() - 1].distance_to(b)) if p.size() > 0 else 999.0
	var l := _len(p)
	var ok := "OK" if (p.size() > 0 and endd < 3.0) else "**FAIL(断)**"
	print("  ", label, ": 点数=", p.size(), " 末端距=", snappedf(endd, 0.1), " 路径长=", snappedf(l, 0.1), "  ", ok)
	return l

func _check() -> void:
	print("=== L2 痛苦回廊 白盒校验 ===")
	var region := _lvl.get_node_or_null("NavigationRegion3D")
	var nav: NavigationMesh = region.navigation_mesh if region != null else null
	print("navmesh 多边形数: ", nav.get_polygon_count() if nav != null else -1)
	var bodies := 0
	var lights := 0
	for c in _lvl.get_children():
		if c is StaticBody3D: bodies += 1
		elif c is OmniLight3D: lights += 1
	print("StaticBody3D(地面+墙+地标): ", bodies, "   光源: ", lights)

	var map: RID = region.get_navigation_map()
	var entry := _s(-83, -7)
	print("map valid=", map.is_valid(), " regions=", NavigationServer3D.map_get_regions(map).size(), " SCALE=", SCALE)
	print("closest_point(入口)=", NavigationServer3D.map_get_closest_point(map, entry))
	print("连通性 / 路径长度:")
	var crit := _route(map, "入口→Boss(直达)", entry, _s(80, 78))
	var to_obj := _route(map, "入口→北门(目标)", entry, _s(-36, -78))
	var obj_boss := _route(map, "北门→Boss", _s(-36, -78), _s(80, 78))
	_route(map, "入口→宝藏(死胡同)", entry, _s(-62, 34))
	_route(map, "入口→齿轮室", entry, _s(22, 18))
	# 环路验证:齿轮→Boss(东路) vs 南长廊→Boss(下环)两条都通
	_route(map, "齿轮→Boss(东路)", _s(22, 18), _s(80, 78))
	_route(map, "南长廊→Boss(下环)", _s(10, 54), _s(80, 78))

	var designed := to_obj + obj_boss   # 设计路线:先取北门目标再下 Boss
	print("设计路线(入口→北门→Boss)= ", snappedf(designed, 0.1), " 单位 ≈ ", snappedf(designed / PLAYER_SPEED, 1.0), " 秒步行")
	var walk_s := crit / PLAYER_SPEED
	print("临界路径纯步行 ≈ ", snappedf(walk_s, 1.0), " 秒 (", snappedf(walk_s / 60.0, 0.1), " 分);速度=", PLAYER_SPEED, " u/s")
	print("  → 估单程通关(步行+战斗,战斗约占 60-70%): ≈ ", snappedf(walk_s / 0.35 / 60.0, 0.1), " 分")
	print("=== done ===")
