extends Node

# companion_plant_anim.gd — 只读父节点(templar)的公共字段来驱动植物动画。
# 不修改 templar.gd:仅读取它的 `state`(enum State{FOLLOW=0, ATTACK=1})与 `velocity`。
# 贴脸攻击(ATTACK 且基本不移动)→ bite(张嘴咬合);
# 移动中(跟随/追击,velocity 超阈值)→ move(前倾摇摆+咀嚼);
# 站定 → idle(轻摇摆)。

@export var anim_player_path: NodePath
@export var idle_anim: String = "idle"
@export var move_anim: String = "move"
@export var attack_anim: String = "bite"
@export var attack_state: int = 1        # templar State.ATTACK
@export var move_threshold: float = 0.5   # velocity 长度超此值视为"移动中"

var _ap: AnimationPlayer = null
var _last_anim: String = ""

func _ready() -> void:
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if _ap == null:
		push_warning("CompanionPlantAnim: 找不到 AnimationPlayer @ %s" % anim_player_path)
		return
	# 全部循环(idle 摇摆 / move 滑行 / bite 攻击期间持续咬)
	for a in [idle_anim, move_anim, attack_anim]:
		if _ap.has_animation(a):
			_ap.get_animation(a).loop_mode = Animation.LOOP_LINEAR

func _process(_delta: float) -> void:
	if _ap == null:
		return
	var p: Node = get_parent()
	if p == null:
		return
	var moving: bool = ("velocity" in p) and (p.velocity as Vector3).length() > move_threshold
	var attacking: bool = ("state" in p) and int(p.state) == attack_state
	var target: String = idle_anim
	if attacking and not moving:
		target = attack_anim
	elif moving:
		target = move_anim
	if target == _last_anim:
		return
	_last_anim = target
	if _ap.has_animation(target) and _ap.current_animation != target:
		_ap.play(target)
