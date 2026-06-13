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
	# 列骨骼名(找肩膀/手臂骨骼用,程序压 T-pose)
	var skel: Skeleton3D = root.get_node_or_null("Skeleton3D")
	if skel != null:
		print("\n=== Skeleton3D 骨骼清单(共 %d 根)===" % skel.get_bone_count())
		for i in range(skel.get_bone_count()):
			var bname: String = skel.get_bone_name(i)
			var key: String = bname.to_lower()
			# 标记手臂相关的骨骼
			var tag := ""
			if key.contains("shoulder") or key.contains("clavic") or key.contains("upper") and (key.contains("arm") or key.contains("l_") or key.contains("r_")):
				tag = "  ← arm?"
			elif key.contains("arm") or key.contains("hand") or key.contains("forearm"):
				tag = "  ← arm?"
			print("  [%2d] %s%s" % [i, bname, tag])
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
