@tool
extends SceneTree

# tools/list_characters.gd —— headless 枚举 Characters.fbx 子节点
# 跑法:Godot --headless --script res://tools/list_characters.gd

func _initialize() -> void:
	const PATH := "res://assets/PolygonDungeon/Models/Characters/Characters.fbx"
	var packed: PackedScene = load(PATH)
	if packed == null:
		print("ERR: 加载失败 ", PATH)
		quit(1)
		return
	var root: Node = packed.instantiate()
	if root == null:
		print("ERR: instantiate 失败")
		quit(1)
		return
	print("=== Characters.fbx 节点树 ===")
	_dump(root, 0)
	print("\n=== 直接子节点(顶层)===")
	for c in root.get_children():
		var aabb_str := ""
		if c is MeshInstance3D and c.mesh != null:
			var box: AABB = c.mesh.get_aabb()
			aabb_str = "  size=%s" % str(box.size)
		print("  - %s : %s%s" % [c.name, c.get_class(), aabb_str])
	# 列动画名
	var ap: AnimationPlayer = root.get_node_or_null("AnimationPlayer")
	if ap != null:
		print("\n=== AnimationPlayer 动画清单(共 %d 个)===" % ap.get_animation_list().size())
		for n in ap.get_animation_list():
			var anim: Animation = ap.get_animation(n)
			print("  - %s   length=%.2fs   loop=%s" % [n, anim.length, anim.loop_mode])
	quit(0)

func _dump(node: Node, depth: int) -> void:
	var indent := "  ".repeat(depth)
	var extra := ""
	if node is MeshInstance3D:
		extra = " [mesh]"
	elif node is Skeleton3D:
		extra = " [skeleton, bones=%d]" % (node as Skeleton3D).get_bone_count()
	print("%s%s : %s%s" % [indent, node.name, node.get_class(), extra])
	if depth < 3:  # 别太深,树太大
		for c in node.get_children():
			_dump(c, depth + 1)
