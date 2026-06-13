extends Node

# enemy_anim_driver.gd — 把骨骼动画接到 enemy_base 的状态机上。
# 挂在敌人(CharacterBody3D)下作为子节点,设 anim_player_path 指向模型里的 AnimationPlayer。
# 监听父节点的 state_changed 信号,按状态播放对应动画。不改 enemy_base.gd。

@export var anim_player_path: NodePath
# 状态 → 动画名(对应 enemy_base.State:IDLE/CHASE/ATTACK/STAGGER/DEATH)
@export var idle_anim: String = "Idle"
@export var move_anim: String = "Walk"
@export var attack_anim: String = "Attack1"
@export var death_anim: String = "Death1"
# 需要循环播放的动画(导入的 glTF 默认不循环)
@export var loop_anims: PackedStringArray = ["Idle", "Walk"]

var _ap: AnimationPlayer = null

func _ready() -> void:
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if _ap == null:
		push_warning("EnemyAnimDriver: 找不到 AnimationPlayer @ %s" % anim_player_path)
		return
	# 给循环动画设上循环
	for a in loop_anims:
		if _ap.has_animation(a):
			_ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	var enemy: Node = get_parent()
	if enemy != null and enemy.has_signal("state_changed"):
		enemy.state_changed.connect(_on_state_changed)
	_play(idle_anim)

func _on_state_changed(_old_state: int, new_state: int) -> void:
	match new_state:
		0: _play(idle_anim)     # IDLE
		1: _play(move_anim)     # CHASE
		2: _play(attack_anim)   # ATTACK
		3: _play(idle_anim)     # STAGGER(暂用 idle,僵直由组件做视觉)
		4: _play(death_anim)    # DEATH

func _play(anim: String) -> void:
	if _ap == null:
		return
	if not _ap.has_animation(anim):
		return
	if _ap.current_animation == anim:
		return
	_ap.play(anim)
