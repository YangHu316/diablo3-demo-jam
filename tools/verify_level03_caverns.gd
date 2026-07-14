extends SceneTree

# 校验 L3 幽暗洞窟白盒:加载/几何/导航连通 + 关键路径长度(对照参考平面图拓扑).
# Run: Godot --headless --path . --script res://tools/verify_level03_caverns.gd

const PLAYER_SPEED := 7.0
const SCALE := 1.5   # 与 level_03_caverns.gd 同步

var _lvl: Node = null
var _frames: int = 0
var _fails: int = 0

func _s(x: float, z: float) -> Vector3:
	return Vector3(x * SCALE, 0.2, z * SCALE)

func _init() -> void:
	physics_frame.connect(_on_phys)

func _on_phys() -> void:
	_frames += 1
	if _frames == 1:
		var ps := load("res://scenes/levels/level_03_caverns.tscn")
		if ps == null:
			printerr("FAIL: level_03_caverns.tscn 未加载"); quit(1); return
		_lvl = ps.instantiate()
		get_root().add_child(_lvl)
		if load("res://scenes/levels/level_03_caverns_play.tscn") == null:
			printerr("WARN: level_03_caverns_play.tscn 解析失败")
	elif _frames == 30:
		_check()
		quit(1 if _fails > 0 else 0)

func _len(path: PackedVector3Array) -> float:
	var d := 0.0
	for i in range(1, path.size()):
		d += path[i].distance_to(path[i - 1])
	return d

func _route(map: RID, label: String, a: Vector3, b: Vector3) -> float:
	var p := NavigationServer3D.map_get_path(map, a, b, true)
	var endd := (p[p.size() - 1].distance_to(b)) if p.size() > 0 else 999.0
	var l := _len(p)
	var ok := p.size() > 0 and endd < 3.0
	if not ok:
		_fails += 1
	print("  ", label, ": 点数=", p.size(), " 末端距=", snappedf(endd, 0.1), " 路径长=", snappedf(l, 0.1), "  ", "OK" if ok else "**FAIL(断)**")
	return l

func _check() -> void:
	print("=== L3 幽暗洞窟 白盒校验 ===")
	var region := _lvl.get_node_or_null("NavigationRegion3D")
	var nav: NavigationMesh = region.navigation_mesh if region != null else null
	print("navmesh 多边形数: ", nav.get_polygon_count() if nav != null else -1)
	var bodies := 0
	for c in _lvl.get_children():
		if c is StaticBody3D: bodies += 1
	print("StaticBody3D(地面+墙+地标): ", bodies)

	var map: RID = region.get_navigation_map()
	var entry := _s(26.5, -24)   # R1 入口圆厅(传送门)
	print("map valid=", map.is_valid(), " regions=", NavigationServer3D.map_get_regions(map).size(), " SCALE=", SCALE)
	print("closest_point(入口)=", NavigationServer3D.map_get_closest_point(map, entry))
	print("连通性 / 路径长度(拓扑对照 CRYPTAL MAZE 参考图):")
	# 主动线:入口(右上)→ 右列 → 右中复合体 → 中央厅 → 中左复合体 → 左侧串室
	var to_far_left := _route(map, "入口→左下斗篷厅(全图横贯)", entry, _s(-49, 0))
	_route(map, "入口→右上大厅(经梯桥)", entry, _s(30, -10))
	_route(map, "入口→右中厅", entry, _s(44, 7))
	_route(map, "入口→右下大厅西尾", entry, _s(38, 26))
	_route(map, "入口→RC主横带(经窄颈)", entry, _s(20, 1))
	_route(map, "入口→RC顶圆丘(经梯桥)", entry, _s(12, -10))
	_route(map, "入口→RC下挂西瓣厅", entry, _s(14, 20))
	_route(map, "入口→RC下挂东瓣厅", entry, _s(26, 20))
	_route(map, "RC圆孔环西→东(绕孔)", _s(11, 13.5), _s(28, 13.5))
	_route(map, "入口→中央厅南圆凸", entry, _s(-4, 12))
	_route(map, "中央厅竖槽西→东(绕槽)", _s(-7.5, 5), _s(0, 5))
	_route(map, "入口→L2顶横厅北带(绕镂空)", entry, _s(-17, -19.2))
	_route(map, "入口→L2西北凸包", entry, _s(-25, -22))
	_route(map, "入口→迷宫西列深处(蛇形)", entry, _s(-34.5, 5))
	_route(map, "入口→底部大厅红门凸口", entry, _s(-31, 26))
	_route(map, "入口→L1顶部凸包", entry, _s(-42, -28))
	var walk_s := to_far_left / PLAYER_SPEED
	print("横贯全图(入口→左下斗篷厅)纯步行 ≈ ", snappedf(walk_s, 1.0), " 秒 (", snappedf(walk_s / 60.0, 0.1), " 分);速度=", PLAYER_SPEED, " u/s")
	print("=== ", "VERIFY OK" if _fails == 0 else "VERIFY FAIL(%d)" % _fails, " ===")
