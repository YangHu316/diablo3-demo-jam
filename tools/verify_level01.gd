extends SceneTree

# Headless 校验 L1 白盒:场景加载 / 几何搭建 / 导航网格 / 寻路连通(含环路).
# Run: Godot --headless --path . --script res://tools/verify_level01.gd

var _lvl: Node = null
var _frames: int = 0

func _init() -> void:
	physics_frame.connect(_on_phys)

func _on_phys() -> void:
	_frames += 1
	if _frames == 1:
		var ps := load("res://scenes/levels/level_01_gate.tscn")
		if ps == null:
			printerr("FAIL: level_01_gate.tscn 未加载")
			quit(1)
			return
		_lvl = ps.instantiate()
		get_root().add_child(_lvl)
		# 顺带确认 play 包装也能解析
		if load("res://scenes/levels/level_01_play.tscn") == null:
			printerr("WARN: level_01_play.tscn 解析失败")
	elif _frames == 10:
		_check()
		quit()

func _ok(b: bool) -> String:
	return "OK" if b else "**FAIL**"

func _check() -> void:
	print("=== L1 白盒校验 ===")
	var region := _lvl.get_node_or_null("NavigationRegion3D")
	var nav: NavigationMesh = region.navigation_mesh if region != null else null
	var polys := nav.get_polygon_count() if nav != null else -1
	print("navmesh 多边形数: ", polys, "  ", _ok(polys == 5))

	var bodies := 0
	var lights := 0
	for c in _lvl.get_children():
		if c is StaticBody3D:
			bodies += 1
		elif c is OmniLight3D:
			lights += 1
	print("StaticBody3D(地面+墙+地标): ", bodies, "  ", _ok(bodies >= 25))
	print("篝火光源: ", lights)

	var map: RID = region.get_navigation_map()
	# 主路:广场 → 休整(必须连通,端点贴近目标)
	var to_rest := Vector3(0, 0.05, -15)
	var p1 := NavigationServer3D.map_get_path(map, Vector3(0, 0.05, 24), to_rest, true)
	var d1 := (p1[p1.size() - 1].distance_to(to_rest)) if p1.size() > 0 else 999.0
	print("寻路 广场→休整: 点数=", p1.size(), " 末端距目标=", snappedf(d1, 0.01), "  ", _ok(d1 < 2.0))

	# 环路:主街 → 支廊宝箱(绕行支路连通)
	var to_chest := Vector3(8, 0.05, 10)
	var p2 := NavigationServer3D.map_get_path(map, Vector3(0, 0.05, 11), to_chest, true)
	var d2 := (p2[p2.size() - 1].distance_to(to_chest)) if p2.size() > 0 else 999.0
	print("寻路 主街→支廊: 点数=", p2.size(), " 末端距目标=", snappedf(d2, 0.01), "  ", _ok(d2 < 2.5))

	# 环路:支廊 → 城门广场北端(支路汇入广场)
	var to_court := Vector3(0, 0.05, -8)
	var p3 := NavigationServer3D.map_get_path(map, to_chest, to_court, true)
	var d3 := (p3[p3.size() - 1].distance_to(to_court)) if p3.size() > 0 else 999.0
	print("寻路 支廊→广场北: 点数=", p3.size(), " 末端距目标=", snappedf(d3, 0.01), "  ", _ok(d3 < 2.5))
	print("=== done ===")
