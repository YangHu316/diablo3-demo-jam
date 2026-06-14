extends Node

# enemy_anim_driver.gd — 把骨骼动画接到 enemy_base 的状态机上。
# 挂在敌人(CharacterBody3D)下作为子节点,设 anim_player_path 指向模型里的 AnimationPlayer。
# 监听父节点的 state_changed 信号,按状态播放对应动画。不改 enemy_base.gd。
#
# 支持 UAL 动画库: 启动时自动注入 ual1/ual2 动画库到 AnimationPlayer。
# 通过 anim_library 参数选择使用哪个动画库 ("ual1"/"ual2")。

@export var anim_player_path: NodePath
# 状态 → 动画名(对应 enemy_base.State:IDLE/CHASE/ATTACK/STAGGER/DEATH)
@export var idle_anim: String = "Idle"
@export var move_anim: String = "Walk"
@export var attack_anim: String = "Attack1"
@export var death_anim: String = "Death1"
# 需要循环播放的动画(导入的 glTF 默认不循环)
@export var loop_anims: PackedStringArray = ["Idle", "Walk"]

# UAL 动画库配置:选择 "ual1"/"ual2" 或留空使用角色自带动画
@export var anim_library: String = ""

# 行走动画播放倍速:走动画太慢会脚滑,×2 与移动速度对齐(只作用于移动状态)
@export var move_anim_speed: float = 2.0

# 死亡状态值:enemy_base.State.DEATH=4, butcher.State.DEATH=5
@export var death_state: int = 4

# UAL 状态→动画映射(覆盖上面的默认动画名)
# 键 = enemy_base.State 枚举值(int), 值 = UAL 动画名(不含库前缀)
@export var ual_idle_anim: String = "Idle"
@export var ual_move_anim: String = "Walk"
@export var ual_attack_anim: String = "Sword_Attack"
@export var ual_death_anim: String = "Death01"
@export var ual_loop_anims: PackedStringArray = ["Idle", "Walk", "Jog_Fwd"]

var _ap: AnimationPlayer = null

func _ready() -> void:
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if _ap == null:
		push_warning("EnemyAnimDriver: 找不到 AnimationPlayer @ %s" % anim_player_path)
		return

	# 注入 UAL 动画库（如果配置了）
	if anim_library != "":
		_inject_ual_library()

	# 给循环动画设上循环
	for a in loop_anims:
		if _ap.has_animation(a):
			_ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR

	var enemy: Node = get_parent()
	if enemy != null and enemy.has_signal("state_changed"):
		enemy.state_changed.connect(_on_state_changed)
	_play(_get_anim_for_state(0))  # 初始 idle

func _inject_ual_library() -> void:
	var anim_lib_node = get_node_or_null("/root/AnimLib")
	if anim_lib_node == null:
		push_warning("EnemyAnimDriver: AnimLib autoload not found")
		return
	if not anim_lib_node.has_method("inject_library"):
		push_warning("EnemyAnimDriver: AnimLib has no inject_library method")
		return
	anim_lib_node.inject_library(_ap, anim_library)

	# 给 UAL 循环动画设上循环
	for a in ual_loop_anims:
		var full_name: String = "%s/%s" % [anim_library, a]
		if _ap.has_animation(full_name):
			_ap.get_animation(full_name).loop_mode = Animation.LOOP_LINEAR

func _on_state_changed(_old_state: int, new_state: int) -> void:
	var canon: int = 0
	if new_state == 1:                    # CHASE / MOVE
		canon = 1
	elif new_state == 2:                  # ATTACK
		canon = 2
	elif new_state == death_state:        # DEATH
		canon = 4
	# STAGGER/CHARGE/ROAR/SWEEP → idle(canon 保持 0)
	var speed: float = move_anim_speed if canon == 1 else 1.0
	_play(_get_anim_for_state(canon), speed)

func _get_anim_for_state(state: int) -> String:
	if anim_library != "":
		var ual_anim := ""
		match state:
			0: ual_anim = ual_idle_anim
			1: ual_anim = ual_move_anim
			2: ual_anim = ual_attack_anim
			4: ual_anim = ual_death_anim
		var full_name: String = "%s/%s" % [anim_library, ual_anim]
		if _ap != null and _ap.has_animation(full_name):
			return full_name
	# Fallback: 使用角色自带动画
	match state:
		0: return idle_anim
		1: return move_anim
		2: return attack_anim
		4: return death_anim
		_: return idle_anim

func _play(anim: String, speed: float = 1.0) -> void:
	if _ap == null:
		return
	if not _ap.has_animation(anim):
		return
	if _ap.current_animation == anim:
		return
	_ap.play(anim, -1, speed)
