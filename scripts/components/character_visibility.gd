extends Node3D

# character_visibility.gd —— 挂在 Characters.fbx instance 的根节点上(Node 名通常是 Characters)
# 把所有角色 mesh 隐藏,只露 visible_character;挂件按 visible_attachments 选择性露。
# Synty PolygonDungeon 的 Characters.fbx 把 16 个角色 + 12 个挂件全挤在一个 Skeleton3D 下,
# 我们用 visibility 过滤来"挑角色",共用同一根骨架与 AnimationPlayer。

@export var visible_character: String = "Character_Hero_Knight_Female"
@export var visible_attachments: PackedStringArray = []  # 留空 = 所有挂件都隐藏
@export var hide_all_others: bool = true

func _ready() -> void:
	var skel: Node = get_node_or_null("Skeleton3D")
	if skel == null:
		# fallback:递归找
		skel = _find_skeleton(self)
	if skel == null:
		push_warning("character_visibility: Skeleton3D not found")
		return
	var attach_set: Dictionary = {}
	for a in visible_attachments:
		attach_set[String(a)] = true
	for c in skel.get_children():
		if c is MeshInstance3D:
			c.visible = (c.name == visible_character) or not hide_all_others
		elif c is BoneAttachment3D:
			c.visible = attach_set.has(String(c.name))

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var found: Skeleton3D = _find_skeleton(c)
		if found != null:
			return found
	return null
