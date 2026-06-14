extends Area3D

# BossNpc: BOSS 死亡后出现在受难之室的神秘 NPC. 玩家鼠标点击它 → 触发两轮固定台词对话,
# 对话结束后才弹出结算页 (RiftManager.emit_run_cleared).
#
# 点击检测: Area3D.input_event 信号 (input_ray_pickable=true + collision_layer 在交互层).
#   —— 与玩家"点地移动/点敌攻击"互不干扰: 玩家的攻击射线只查敌人层(2)与地面;
#      本 NPC 在交互层(16), 玩家射线不命中它, 而 Godot 的 PhysicsPicking 会单独给它派 input_event.
# V3.13:身体替换成 Synty Character_Rock_Golem 模型 (石像), 保留光环/光源/碰撞/名牌不变.

const NPC_NAME: String = "守墓石像"
const ROCK_GOLEM_SCENE: PackedScene = preload("res://assets/characters/synty/Character_Rock_Golem.tscn")

# 两轮固定台词 (按顺序逐句点击推进).
const LINES: Array[String] = [
	"凡人……你斩落了屠夫的镰刀,血色的回响终于平息。",
	"带上这片净土的战利品,庇护所的灯火会为你长明。去吧,英雄。",
]

var _started: bool = false

func _ready() -> void:
	add_to_group("boss_npc")
	collision_layer = 16          # 交互层 (与掉落物/塔同层), 不与敌人(2)/玩家(1)互扰
	collision_mask = 0            # 不主动检测任何 body
	monitoring = false
	monitorable = false
	input_ray_pickable = true     # 允许 PhysicsPicking 给本 Area3D 派 input_event
	input_event.connect(_on_input_event)
	_build_visual()
	_play_appear()

# ── 视觉构建 (石像 NPC) ───────────────────────────────────────
func _build_visual() -> void:
	# 身体: Synty 石像模型 (替代原程序化胶囊). 保留 Y=0 贴地, 略放大让神秘感.
	var body: Node = ROCK_GOLEM_SCENE.instantiate()
	body.name = "Body"
	add_child(body)
	if body is Node3D:
		(body as Node3D).scale = Vector3(1.2, 1.2, 1.2)   # 比玩家略大,体现"古老守护者"压迫感
		# V3.13f:Synty 石像 default 朝 +Z (玩家从南门 +Z 方向走来), 无需旋转.
		# 之前 PI(180°) 反而让石像背对玩家.
	# V3.13e:Synty 模型默认 T-pose(双臂张开), 注入 UAL Idle 让它站立呼吸.
	var ap: AnimationPlayer = _find_animation_player(body)
	if ap != null:
		var anim_lib: Node = get_node_or_null("/root/AnimLib")
		if anim_lib != null and anim_lib.has_method("inject_library"):
			anim_lib.inject_library(ap, "ual1")
			if ap.has_animation("ual1/Idle"):
				# 设循环(UAL 导入默认非循环, 必须显式设)
				var idle: Animation = ap.get_animation("ual1/Idle")
				if idle != null:
					idle.loop_mode = Animation.LOOP_LINEAR
				ap.play("ual1/Idle")

# 递归找 AnimationPlayer (Synty 模型层级里 AnimationPlayer 是直接子节点, 但保险起见递归).
func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r: AnimationPlayer = _find_animation_player(c)
		if r != null:
			return r
	return null

	# 地面光环 (扁圆柱, 半透明金).
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.1
	cyl.height = 0.04
	var hm := StandardMaterial3D.new()
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.albedo_color = Color(1.0, 0.8, 0.4, 0.35)
	hm.emission_enabled = true
	hm.emission = Color(1.0, 0.8, 0.4)
	hm.emission_energy_multiplier = 1.6
	cyl.material = hm
	halo.mesh = cyl
	halo.position = Vector3(0, 0.03, 0)
	add_child(halo)

	# 暖光源.
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.6, 0)
	light.light_color = Color(1.0, 0.82, 0.45)
	light.light_energy = 2.4
	light.omni_range = 8.0
	add_child(light)

	# 点击碰撞体 (胶囊, 覆盖整个石像;石像 1.2x 缩放后约 2.4m 高 / 1.0m 宽).
	# V3.13f:之前 r=0.6 h=2.2 太小, 玩家点石像头/肩膀超出胶囊范围 → PhysicsPicking 不触发.
	var cs := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 1.2
	sh.height = 3.6
	cs.shape = sh
	cs.position = Vector3(0, 1.8, 0)
	add_child(cs)

	# 头顶名牌 + 点击提示.
	var plate := Label3D.new()
	plate.name = "Nameplate"
	plate.text = "%s\n[ 点击对话 ]" % NPC_NAME
	plate.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plate.no_depth_test = true
	plate.fixed_size = true
	plate.pixel_size = 0.0032
	plate.modulate = Color(1.0, 0.9, 0.55)
	plate.outline_size = 6
	plate.outline_modulate = Color(0, 0, 0, 0.9)
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate.position = Vector3(0, 4.0, 0)
	add_child(plate)

# 出场演出: 从地面淡入 + 轻微浮起.
func _play_appear() -> void:
	scale = Vector3(0.6, 0.6, 0.6)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector3.ONE, 0.45)

# ── 点击 → 启动对话 ───────────────────────────────────────────
func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape: int) -> void:
	if _started:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_start_dialogue()

func _start_dialogue() -> void:
	if _started:
		return
	_started = true
	# 进对话即冻结玩家 (停走/停攻击), 防止点对话框时误走位.
	_set_player_frozen(true)
	# 收起点击提示, 防止玩家以为还能再点.
	var plate := get_node_or_null("Nameplate")
	if plate is Label3D:
		(plate as Label3D).text = NPC_NAME
	var panel: Node = get_tree().get_first_node_in_group("dialogue_panel")
	if panel != null and panel.has_method("start_dialogue"):
		if not panel.dialogue_finished.is_connected(_on_dialogue_finished):
			panel.dialogue_finished.connect(_on_dialogue_finished)
		panel.start_dialogue(NPC_NAME, LINES)
	else:
		# 找不到对话面板 (异常兜底): 直接结算, 不卡死流程.
		_on_dialogue_finished()

func _on_dialogue_finished() -> void:
	_set_player_frozen(false)
	var rm: Node = get_node_or_null("/root/RiftManager")
	if rm != null and rm.has_method("emit_run_cleared"):
		rm.emit_run_cleared()
	# 对话完成后 NPC 退场 (缩小消失).
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
	tw.tween_callback(queue_free)

func _set_player_frozen(v: bool) -> void:
	var ps := get_tree().get_nodes_in_group("player")
	if ps.size() > 0 and "is_frozen" in ps[0]:
		ps[0].is_frozen = v
