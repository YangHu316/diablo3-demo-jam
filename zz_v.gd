extends Node3D

func _ready() -> void:
	var lvl: Node3D = load("res://scenes/levels/level_02_assembled.tscn").instantiate()
	add_child(lvl)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	var down := PhysicsRayQueryParameters3D.create(Vector3(-124.5,5,-10.5), Vector3(-124.5,-5,-10.5))
	down.collision_mask = 4
	var dh := space.intersect_ray(down)
	print("地板命中=", not dh.is_empty(), " y=", (("%.2f"%dh.position.y) if not dh.is_empty() else "无"))
	var sb := 0
	for n in _all(lvl):
		if n is StaticBody3D: sb += 1
	print("StaticBody(每块)=", sb)
	await get_tree().create_timer(0.5).timeout
	var fill := DirectionalLight3D.new(); fill.rotation_degrees = Vector3(-50,30,0); fill.light_energy=1.0; add_child(fill)
	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(-34,26,60), Vector3(-46,1,20), Vector3.UP); cam.fov=60.0
	add_child(cam); cam.current = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://_cap.png")
	get_tree().quit()

func _all(n,a=[]):
	a.append(n)
	for c in n.get_children(): _all(c,a)
	return a
