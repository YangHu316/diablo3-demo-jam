extends Node3D

# 俯拍工具:非 headless 运行,加载目标关卡 → 正交相机垂直俯拍 → 存 PNG(+bounds sidecar)→ 退出.
# 用于 AI 关卡搭建的"图像自检/重叠对比"回路。
# Run: Godot --path . res://tools/capture_topdown.tscn
# 可选参数(-- 之后): --scene <res路径>  --out <res路径>
const DEFAULT_SCENE := "res://scenes/levels/level_03_csg.tscn"
const DEFAULT_OUT := "res://tools/_capture/level_03_csg_topdown.png"

func _ready() -> void:
	var scene_path := DEFAULT_SCENE
	var out_path := DEFAULT_OUT
	var args := OS.get_cmdline_user_args()
	var hide_names: Array[String] = []
	var tilt := 90.0
	var focus := Vector2(INF, INF)
	var fsize := 0.0
	var no_fill := false
	for i in args.size():
		if args[i] == "--scene" and i + 1 < args.size():
			scene_path = args[i + 1]
		elif args[i] == "--out" and i + 1 < args.size():
			out_path = args[i + 1]
		elif args[i] == "--hide" and i + 1 < args.size():
			hide_names.append(args[i + 1])
		elif args[i] == "--tilt" and i + 1 < args.size():
			tilt = float(args[i + 1])
		elif args[i] == "--focus" and i + 2 < args.size():
			focus = Vector2(float(args[i + 1]), float(args[i + 2]))
		elif args[i] == "--size" and i + 1 < args.size():
			fsize = float(args[i + 1])
		elif args[i] == "--nofill":
			no_fill = true

	var ps: PackedScene = load(scene_path)
	if ps == null:
		printerr("[capture] 场景加载失败: ", scene_path)
		get_tree().quit(1)
		return
	var lvl := ps.instantiate()
	add_child(lvl)
	for hn in hide_names:
		var n := lvl.find_child(hn, true, false)
		if n != null and "visible" in n:
			n.set("visible", false)
			print("[capture] 已隐藏 ", hn)

	# 等几何(含 CSG bake / @tool 生成)就绪后按 AABB 求包围盒
	for i in 4:
		await RenderingServer.frame_post_draw
	var aabb := _merge_aabb(lvl)
	if aabb.size == Vector3.ZERO:
		printerr("[capture] 场景无可见几何")
		get_tree().quit(1)
		return
	var margin := 6.0
	var bounds := Rect2(aabb.position.x, aabb.position.z, aabb.size.x, aabb.size.z).grow(margin)
	if focus.x != INF and fsize > 0.0:
		bounds = Rect2(focus.x - fsize * 0.5, focus.y - fsize * 0.5, fsize, fsize)

	# 俯拍补光(垂直向下,读得清;--nofill 时保留场景真实光照)
	if not no_fill:
		var fill := DirectionalLight3D.new()
		fill.rotation_degrees = Vector3(-90, 0, 0)
		fill.light_energy = 1.1
		fill.light_color = Color(1, 1, 1)
		fill.shadow_enabled = false
		add_child(fill)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.rotation_degrees = Vector3(-tilt, 0, 0)   # 默认垂直向下,北(-Z)=画面上方;--tilt 可斜视
	var cd := 120.0
	cam.position = Vector3(bounds.get_center().x,
			cd * sin(deg_to_rad(tilt)), bounds.get_center().y + cd * cos(deg_to_rad(tilt)))
	var vp_size := get_viewport().get_visible_rect().size
	var aspect := vp_size.x / vp_size.y
	cam.size = maxf(bounds.size.y, bounds.size.x / aspect) * 1.02   # 正交 size=纵向跨度
	cam.current = true
	add_child(cam)

	for i in 8:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var abs_dir := ProjectSettings.globalize_path(out_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var err := img.save_png(ProjectSettings.globalize_path(out_path))

	# bounds sidecar:俯拍画面实际覆盖的世界矩形(相机视野,含 letterbox 修正)
	var view_h := cam.size
	var view_w := view_h * aspect
	var side := {
		"min_x": cam.position.x - view_w * 0.5,
		"min_z": cam.position.z - view_h * 0.5,
		"size_x": view_w,
		"size_z": view_h,
	}
	var f := FileAccess.open(ProjectSettings.globalize_path(out_path + ".bounds.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(side))
	f.close()
	print("[capture] ", "已保存 " + out_path if err == OK else "保存失败 err=%d" % err,
			" 分辨率=", img.get_size(), " 视野=", side)
	get_tree().quit(0 if err == OK else 1)

func _merge_aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is GeometryInstance3D and not (cur.get_parent() is Skeleton3D):
			var gi := cur as GeometryInstance3D
			var a: AABB = gi.global_transform * gi.get_aabb()
			# 过滤:蒙皮角色网格(上面已跳过,原始 AABB 巨大)、退化/远离关卡范围的杂散对象
			var c := a.get_center()
			if a.size.length() < 400.0 and absf(c.x) < 100.0 and absf(c.z) < 100.0:
				if first:
					box = a
					first = false
				else:
					box = box.merge(a)
		for c in cur.get_children():
			stack.append(c)
	return box
