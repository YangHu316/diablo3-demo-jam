extends SceneTree

# 校验 Boss房白盒:加载/几何/导航连通.
var _lvl: Node = null
var _f: int = 0

func _init() -> void:
	physics_frame.connect(_on_phys)

func _on_phys() -> void:
	_f += 1
	if _f == 1:
		var ps := load("res://scenes/levels/boss_room.tscn")
		if ps == null:
			printerr("FAIL: boss_room.tscn 未加载"); quit(1); return
		_lvl = ps.instantiate()
		get_root().add_child(_lvl)
		if load("res://scenes/levels/boss_room_play.tscn") == null:
			printerr("WARN: boss_room_play.tscn 解析失败")
	elif _f == 10:
		var region := _lvl.get_node_or_null("NavigationRegion3D")
		var polys: int = region.navigation_mesh.get_polygon_count() if region != null else -1
		var bodies := 0
		for c in _lvl.get_children():
			if c is StaticBody3D: bodies += 1
		print("boss房 navmesh面=", polys, " StaticBody=", bodies)
		var map: RID = region.get_navigation_map()
		# 南北纵贯(入口→对侧)
		var t1 := Vector3(0, 0.2, -16)
		var p1 := NavigationServer3D.map_get_path(map, Vector3(0, 0.2, 16), t1, true)
		var d1 := (p1[p1.size()-1].distance_to(t1)) if p1.size() > 0 else 999.0
		print("南北纵贯(风筝): 点数=", p1.size(), " 末端距=", snappedf(d1, 0.1), "  ", ("OK" if d1 < 2.0 else "**FAIL**"))
		# 东西横贯
		var t2 := Vector3(-16, 0.2, 0)
		var p2 := NavigationServer3D.map_get_path(map, Vector3(16, 0.2, 0), t2, true)
		var d2 := (p2[p2.size()-1].distance_to(t2)) if p2.size() > 0 else 999.0
		print("东西横贯(风筝): 点数=", p2.size(), " 末端距=", snappedf(d2, 0.1), "  ", ("OK" if d2 < 2.0 else "**FAIL**"))
		quit()
