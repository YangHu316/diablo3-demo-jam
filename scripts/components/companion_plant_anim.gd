extends Node

# companion_plant_anim.gd — 只读父节点(templar)的公共 state 来驱动植物动画。
# 不修改 templar.gd:仅读取它的 `state`(enum State{FOLLOW=0, ATTACK=1})选择播放的动画。
# FOLLOW → idle(摇摆);ATTACK → bite(咬合,攻击期间循环)。

@export var anim_player_path: NodePath
@export var idle_anim: String = "idle"
@export var attack_anim: String = "bite"
@export var attack_state: int = 1   # templar State.ATTACK

var _ap: AnimationPlayer = null
var _last_state: int = -1

func _ready() -> void:
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if _ap == null:
		push_warning("CompanionPlantAnim: 找不到 AnimationPlayer @ %s" % anim_player_path)
		return
	# 两个动画都循环(idle 持续摇摆,attack 期间持续咬)
	for a in [idle_anim, attack_anim]:
		if _ap.has_animation(a):
			_ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR

func _process(_delta: float) -> void:
	if _ap == null:
		return
	var p: Node = get_parent()
	if p == null or not ("state" in p):
		return
	var s: int = int(p.state)
	if s == _last_state:
		return
	_last_state = s
	var target: String = attack_anim if s == attack_state else idle_anim
	if _ap.has_animation(target) and _ap.current_animation != target:
		_ap.play(target)
