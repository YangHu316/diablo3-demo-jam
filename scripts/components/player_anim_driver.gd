extends Node

# player_anim_driver.gd — 把 UAL 动画接到 player 状态上。
# 挂在 Player 子节点;监听 Player 的 dodge_started / dodge_ended / player_died 信号 +
# 每帧根据 is_moving / is_dodging / is_dead 切动画。
#
# 与 enemy_anim_driver 同款:用 AnimLib 注入 ual1/ual2 库到 AnimationPlayer,
# 通过 anim_library 选库("ual1"/"ual2",留空 = 用角色自带动画)。

@export var anim_player_path: NodePath
# UAL 状态→动画名(默认对齐 ual1 命名)
@export var anim_library: String = "ual1"
@export var idle_anim: String = "Idle_Loop"
@export var move_anim: String = "Jog_Fwd_Loop"
# UAL1 里翻滚动画名是 Roll(不是 Dodge_Fwd),已查表确认
@export var dodge_anim: String = "Roll"
@export var attack_anim: String = "Pistol_Shoot"  # 暂用手枪射击代替 Bow_Attack
@export var death_anim: String = "Death01"
# 循环动画(导入的 glTF 默认不循环)
@export var loop_anims: PackedStringArray = ["Idle_Loop", "Jog_Fwd_Loop", "Walk_Loop", "Sprint_Loop"]

enum State { IDLE, MOVE, DODGE, DEATH }

var _ap: AnimationPlayer = null
var _player: Node = null
var _state: int = State.IDLE
var _last_anim: String = ""

func _ready() -> void:
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if _ap == null:
		push_warning("PlayerAnimDriver: AnimationPlayer @ %s 未找到 — 角色不会有骨骼动画" % anim_player_path)
		# V3.6 兜底:如果按 NodePath 找不到,递归找一个 AnimationPlayer
		var p: Node = get_parent()
		if p != null:
			_ap = _find_ap(p)
			if _ap != null:
				print("PlayerAnimDriver: 递归找到 AnimationPlayer at %s" % _ap.get_path())
		if _ap == null:
			return
	# 注入 UAL 动画库
	if anim_library != "":
		_inject_ual_library()
	# 调试:打印实际加载到的所有动画名
	var loaded_names: PackedStringArray = PackedStringArray()
	for ln in _ap.get_animation_library_list():
		var lib: AnimationLibrary = _ap.get_animation_library(ln)
		if lib != null:
			for an in lib.get_animation_list():
				loaded_names.append("%s/%s" % [ln, an] if ln != "" else String(an))
	print("PlayerAnimDriver: AnimationPlayer 上共 %d 个动画 → %s" % [loaded_names.size(), ", ".join(loaded_names)])
	# 设循环
	for a in loop_anims:
		var full: String = "%s/%s" % [anim_library, a] if anim_library != "" else a
		if _ap.has_animation(full):
			_ap.get_animation(full).loop_mode = Animation.LOOP_LINEAR
	_player = get_parent()
	# 接信号(优先级最高:翻滚/死亡瞬间切)
	if _player != null:
		if _player.has_signal("dodge_started"):
			_player.dodge_started.connect(_on_dodge_started)
		if _player.has_signal("dodge_ended"):
			_player.dodge_ended.connect(_on_dodge_ended)
		if _player.has_signal("player_died"):
			_player.player_died.connect(_on_player_died)
	_play(_resolve(idle_anim))

# V3.6:递归找 AnimationPlayer(导入的 FBX 节点结构有时会变,NodePath 失效兜底)
func _find_ap(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r: AnimationPlayer = _find_ap(c)
		if r != null:
			return r
	return null

func _inject_ual_library() -> void:
	var lib_node: Node = get_node_or_null("/root/AnimLib")
	if lib_node == null or not lib_node.has_method("inject_library"):
		return
	lib_node.inject_library(_ap, anim_library)

func _process(_delta: float) -> void:
	if _ap == null or _player == null or not is_instance_valid(_player):
		return
	if _state == State.DEATH or _state == State.DODGE:
		return  # 信号驱动,不被 _process 覆盖
	# 简单:看 is_moving 切 idle/move
	var moving: bool = false
	if "is_moving" in _player:
		moving = bool(_player.is_moving)
	if moving and _state != State.MOVE:
		_state = State.MOVE
		_play(_resolve(move_anim))
	elif not moving and _state != State.IDLE:
		_state = State.IDLE
		_play(_resolve(idle_anim))

func _on_dodge_started(_dir: Vector3, _duration: float) -> void:
	_state = State.DODGE
	_play(_resolve(dodge_anim))

func _on_dodge_ended() -> void:
	_state = State.IDLE
	_play(_resolve(idle_anim))

func _on_player_died() -> void:
	_state = State.DEATH
	_play(_resolve(death_anim))

func _resolve(anim: String) -> String:
	if anim_library == "":
		return anim
	var full: String = "%s/%s" % [anim_library, anim]
	if _ap != null and _ap.has_animation(full):
		return full
	return anim  # fallback

func _play(anim: String) -> void:
	if _ap == null or anim == "":
		return
	if not _ap.has_animation(anim):
		return
	if _last_anim == anim and _ap.is_playing():
		return
	_ap.play(anim)
	_last_anim = anim
