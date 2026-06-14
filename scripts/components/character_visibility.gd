@tool
extends Node3D

# character_visibility.gd —— 挂在 Characters.fbx instance 的根节点上(Node 名通常是 Characters)
# 把所有角色 mesh 隐藏,只露 visible_character;挂件按 visible_attachments 选择性露。
# 同时把 T-pose(双臂平举)压成 A-pose(自然下垂),策划 §6 美术 D 出动画前的临时方案。
#
# @tool: 让编辑器里也执行隐藏/压臂——否则整包 Characters.fbx 的 16 个角色 mesh
# 会在编辑器视口里全部堆叠显示(运行时本来就靠 _ready 隐藏,所以游戏正常)。
# 仅做显隐/骨骼姿势,改的是 FBX 实例的子节点(非 editable),不会存进 .tscn、无 git 噪声。

@export var visible_character: String = "Character_Hero_Knight_Female"
@export var visible_attachments: PackedStringArray = []  # 留空 = 所有挂件都隐藏
@export var hide_all_others: bool = true

# T-pose → A-pose 程序化压臂(美术 D 接 AnimationTree 后可关)
@export var apply_a_pose: bool = true
# Shoulder 绕 local 轴旋转;默认 Z 轴 75°,R 自动取负镜像。Inspector 可调
@export var shoulder_axis: Vector3 = Vector3(0, 0, 1)
@export var shoulder_angle_deg: float = 75.0
# Elbow 微弯让胳膊更自然(0 = 不弯)
@export var elbow_bend_deg: float = 15.0

func _ready() -> void:
	var skel: Node = get_node_or_null("Skeleton3D")
	if skel == null:
		skel = _find_skeleton(self)
	if skel == null:
		push_warning("character_visibility: Skeleton3D not found")
		return
	# 1. 过滤 mesh / 挂件可见性
	var attach_set: Dictionary = {}
	for a in visible_attachments:
		attach_set[String(a)] = true
	for c in skel.get_children():
		if c is MeshInstance3D:
			c.visible = (c.name == visible_character) or not hide_all_others
		elif c is BoneAttachment3D:
			c.visible = attach_set.has(String(c.name))
	# 2. 程序化 A-pose
	if apply_a_pose and skel is Skeleton3D:
		_apply_a_pose(skel as Skeleton3D)

func _apply_a_pose(skel: Skeleton3D) -> void:
	var axis: Vector3 = shoulder_axis.normalized() if shoulder_axis.length() > 0.001 else Vector3(0, 0, 1)
	var ang: float = deg_to_rad(shoulder_angle_deg)
	# 左肩:正向旋转;右肩:取负(镜像)
	var lq: Quaternion = Quaternion(axis, ang)
	var rq: Quaternion = Quaternion(axis, -ang)
	var l_idx: int = skel.find_bone("Shoulder_L")
	var r_idx: int = skel.find_bone("Shoulder_R")
	if l_idx >= 0:
		skel.set_bone_pose_rotation(l_idx, lq)
	if r_idx >= 0:
		skel.set_bone_pose_rotation(r_idx, rq)
	# Elbow 微弯
	if elbow_bend_deg > 0.0:
		var ebend: float = deg_to_rad(elbow_bend_deg)
		var le_idx: int = skel.find_bone("Elbow_L")
		var re_idx: int = skel.find_bone("Elbow_R")
		var leq: Quaternion = Quaternion(axis, ebend)
		var req: Quaternion = Quaternion(axis, -ebend)
		if le_idx >= 0:
			skel.set_bone_pose_rotation(le_idx, leq)
		if re_idx >= 0:
			skel.set_bone_pose_rotation(re_idx, req)

func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var found: Skeleton3D = _find_skeleton(c)
		if found != null:
			return found
	return null
