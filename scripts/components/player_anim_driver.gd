extends Node

# player_anim_driver.gd — 把 UAL 动画接到 player 状态上。
# 挂在 Player 子节点;监听 Player + SkillSlotManager 的信号 + 每帧 is_moving 状态机切动画。
#
# 信号源:
#   - Player.dodge_started / dodge_ended / player_died / took_damage(可选)
#   - SkillSlotManager.skill_activated (一次性射击 → ATTACK 短动画)
#   - SkillSlotManager.channel_started / channel_stopped (E 引导 → CHANNEL 循环)

@export var anim_player_path: NodePath
# UAL 状态→动画名(默认对齐 ual1 命名)
@export var anim_library: String = "ual1"
# V3.11:同时注入第二个库(用 OverhandThrow 这种 ual2 才有的动作)
@export var extra_libraries: PackedStringArray = ["ual2"]
# V3.x 合并:名字采用 78ade47 美术验证过的短名(Godot 导入后 _Loop 后缀被剥掉,
# Idle_Loop → Idle / Jog_Fwd_Loop → Jog_Fwd 才能命中,否则 _resolve 回退 → T-pose)
@export var idle_anim: String = "Idle"
@export var move_anim: String = "Jog_Fwd"
@export var dodge_anim: String = "Roll"
# V3.12:用户选定 Pistol_Shoot(扣扳机)— UAL 没拉弓,这个最贴近"瞬发射击"。
@export var attack_anim: String = "Pistol_Shoot"
# 备选(若 attack_anim 不存在则按顺序回退)
@export var attack_anim_fallbacks: PackedStringArray = ["OverhandThrow", "Spell_Simple_Shoot"]
@export var channel_enter_anim: String = "Spell_Simple_Enter"  # 进引导
@export var channel_loop_anim: String = "Spell_Simple_Idle"    # 同短名规则,Spell_Simple_Idle_Loop → _Idle
@export var channel_exit_anim: String = "Spell_Simple_Exit"
@export var hit_anim: String = "Hit_Chest"                     # 受击
@export var death_anim: String = "Death01"
# 循环动画(导入的 glTF 默认不循环)
@export var loop_anims: PackedStringArray = [
	"Idle", "Jog_Fwd", "Walk", "Sprint", "Spell_Simple_Idle",
]

enum State { IDLE, MOVE, DODGE, ATTACK, CHANNEL, HIT, DEATH }

var _ap: AnimationPlayer = null
var _player: Node = null
var _state: int = State.IDLE
var _last_anim: String = ""
# 一次性动作锁(ATTACK / HIT 播完才让 _process 回到 IDLE/MOVE)
var _oneshot_lock_until: float = 0.0
# 引导期间记录是否在 loop 段(进入动作放完进 loop)
var _channel_in_loop: bool = false

func _ready() -> void:
	_ap = get_node_or_null(anim_player_path) as AnimationPlayer
	if _ap == null:
		push_warning("PlayerAnimDriver: AnimationPlayer @ %s 未找到 — 角色不会有骨骼动画" % anim_player_path)
		var p: Node = get_parent()
		if p != null:
			_ap = _find_ap(p)
			if _ap != null:
				print("PlayerAnimDriver: 递归找到 AnimationPlayer at %s" % _ap.get_path())
		if _ap == null:
			return
	if anim_library != "":
		_inject_ual_library()
	# V3.11:注入额外库(ual2)— OverhandThrow 等动作在 ual2 里
	for extra in extra_libraries:
		_inject_extra_library(String(extra))
	# 调试:启动时列动画清单
	var loaded_names: PackedStringArray = PackedStringArray()
	for ln in _ap.get_animation_library_list():
		var lib: AnimationLibrary = _ap.get_animation_library(ln)
		if lib != null:
			for an in lib.get_animation_list():
				loaded_names.append("%s/%s" % [ln, an] if ln != "" else String(an))
	print("PlayerAnimDriver: %d 个动画上线" % loaded_names.size())
	# V3.11:把所有 anim 名打到日志,方便核对(找 OverhandThrow / Spell_Simple_Shoot 是否真烤进来)
	if loaded_names.size() > 0:
		print("[AnimDriver] anims: ", ", ".join(loaded_names))
	# V3.11:把所有 anim 名打到日志,方便核对(找 OverhandThrow / Spell_Simple_Shoot 是否真烤进来)
	if loaded_names.size() > 0:
		print("[AnimDriver] anims: ", ", ".join(loaded_names))
	# 设循环
	for a in loop_anims:
		var full: String = "%s/%s" % [anim_library, a] if anim_library != "" else a
		if _ap.has_animation(full):
			_ap.get_animation(full).loop_mode = Animation.LOOP_LINEAR
	# 接信号
	_player = get_parent()
	if _player != null:
		if _player.has_signal("dodge_started"):
			_player.dodge_started.connect(_on_dodge_started)
		if _player.has_signal("dodge_ended"):
			_player.dodge_ended.connect(_on_dodge_ended)
		if _player.has_signal("player_died"):
			_player.player_died.connect(_on_player_died)
		if _player.has_signal("took_damage"):
			_player.took_damage.connect(_on_took_damage)
	# SkillSlotManager 信号(攻击 / 引导)
	var ssm: Node = null
	if _player != null:
		ssm = _player.get_node_or_null("SkillSlotManager")
	if ssm != null:
		if ssm.has_signal("skill_activated"):
			ssm.skill_activated.connect(_on_skill_activated)
		if ssm.has_signal("channel_started"):
			ssm.channel_started.connect(_on_channel_started)
		if ssm.has_signal("channel_stopped"):
			ssm.channel_stopped.connect(_on_channel_stopped)
	# 动画播完回调(用于一次性 enter→loop / exit 衔接)
	if _ap != null and not _ap.animation_finished.is_connected(_on_anim_finished):
		_ap.animation_finished.connect(_on_anim_finished)
	_play(_resolve(idle_anim))

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

# V3.11:把额外的 UAL 库(如 ual2)也注入到 AnimationPlayer
func _inject_extra_library(lib_name: String) -> void:
	if lib_name == "" or lib_name == anim_library:
		return
	var lib_node: Node = get_node_or_null("/root/AnimLib")
	if lib_node == null or not lib_node.has_method("inject_library"):
		return
	lib_node.inject_library(_ap, lib_name)

func _process(delta: float) -> void:
	if _ap == null or _player == null or not is_instance_valid(_player):
		return
	# DEATH/CHANNEL 全部由信号锁住,不让 _process 覆盖
	if _state == State.DEATH or _state == State.CHANNEL:
		return
	# DODGE / ATTACK / HIT 一次性 lock(动画播完才回 IDLE)
	if _state == State.DODGE or _state == State.ATTACK or _state == State.HIT:
		_oneshot_lock_until -= delta
		if _oneshot_lock_until > 0.0:
			return
		# 锁完回基础态
		_state = State.IDLE
	# IDLE ↔ MOVE
	var moving: bool = false
	if "is_moving" in _player:
		moving = bool(_player.is_moving)
	if moving and _state != State.MOVE:
		_state = State.MOVE
		_play(_resolve(move_anim))
	elif not moving and _state != State.IDLE:
		_state = State.IDLE
		_play(_resolve(idle_anim))

# ── 信号处理 ──────────────────────────────────────────────
func _on_dodge_started(_dir: Vector3, _duration: float) -> void:
	_state = State.DODGE
	var full: String = _resolve(dodge_anim)
	_play(full)
	# V3.10:dodge 持续 0.4s 但 Roll 动画 ~1s,_on_dodge_ended 早于动画完成会被切断。
	# 用 _oneshot_lock 让 Roll 播完(85% 长度后允许 idle/move 接管)。
	_oneshot_lock_until = _anim_length(full) * 0.85

func _on_dodge_ended() -> void:
	# V3.10:不立刻切 idle,让 Roll 动画自然播完(_oneshot_lock_until 控制)
	# 状态保持 DODGE,_process 看到 _oneshot_lock_until 到期会切回 IDLE/MOVE
	pass

func _on_player_died() -> void:
	_state = State.DEATH
	_play(_resolve(death_anim))

# 受击(可选信号 took_damage(amount, source))
func _on_took_damage(_amount: int, _source) -> void:
	# 引导/死亡时不打断
	if _state == State.DEATH or _state == State.CHANNEL or _state == State.DODGE:
		return
	_state = State.HIT
	var full: String = _resolve(hit_anim)
	_play(full)
	_oneshot_lock_until = _anim_length(full) * 0.85   # 提前 15% 解锁,衔接更顺

# 一次性技能触发 → ATTACK 短动画(只对射击类槽生效;翻滚不进这里因为槽 type=MOVEMENT)
func _on_skill_activated(_slot: int, sd: Resource) -> void:
	if sd == null or _state == State.DEATH or _state == State.CHANNEL or _state == State.DODGE:
		return
	# 0 = PROJECTILE,3 = MELEE — 只这两类播 attack
	var t: int = int(sd.skill_type)
	if t != 0 and t != 3:
		return
	# V3.9:玩家移动中不放抬手扣扳机动画 — 真正攻击时玩家已停在射程内 (is_moving=false)
	# 走路途中经过敌人触发的 LMB armed 自动开火,不该把跑步动画打断为射击姿势
	var moving: bool = false
	if _player != null and "is_moving" in _player:
		moving = bool(_player.is_moving)
	if moving:
		return
	_state = State.ATTACK
	# V3.11:attack_anim + fallback 链 — 第一个能 resolve 的就用
	var full: String = _resolve(attack_anim)
	if _ap == null or not _ap.has_animation(full):
		for fb in attack_anim_fallbacks:
			var f: String = _resolve(String(fb))
			if _ap != null and _ap.has_animation(f):
				full = f
				break
	print("[AnimDriver] ATTACK → ", full)
	_play(full)
	_oneshot_lock_until = _anim_length(full) * 0.7

# 引导(E)开始 → 播 enter,enter 结束 _on_anim_finished 切到 loop
func _on_channel_started(_slot: int, _sd: Resource) -> void:
	_state = State.CHANNEL
	_channel_in_loop = false
	var full: String = _resolve(channel_enter_anim)
	if _ap.has_animation(full):
		_play(full)
	else:
		# 没 enter 直接 loop
		_channel_in_loop = true
		_play(_resolve(channel_loop_anim))

func _on_channel_stopped(_slot: int, _sd: Resource) -> void:
	if _state != State.CHANNEL:
		return
	_state = State.IDLE
	_channel_in_loop = false
	# 试着播 exit,播完 _on_anim_finished 回 idle/move;失败直接回
	var full: String = _resolve(channel_exit_anim)
	if _ap.has_animation(full):
		_play(full)
	else:
		_play(_resolve(idle_anim))

func _on_anim_finished(anim_name: StringName) -> void:
	var name_str: String = String(anim_name)
	# enter 结束 → loop
	if _state == State.CHANNEL and not _channel_in_loop:
		_channel_in_loop = true
		_play(_resolve(channel_loop_anim))
		return
	# exit 结束 → idle(_state 已在 _on_channel_stopped 切回 IDLE)
	if name_str.ends_with(channel_exit_anim):
		_play(_resolve(idle_anim))

# ── 工具 ──────────────────────────────────────────────────
func _resolve(anim: String) -> String:
	if anim_library == "":
		return anim
	# V3.11:先查主库,再查 extra_libraries(支持 ual1+ual2 混用)
	var primary: String = "%s/%s" % [anim_library, anim]
	if _ap != null and _ap.has_animation(primary):
		return primary
	for extra in extra_libraries:
		var full_extra: String = "%s/%s" % [String(extra), anim]
		if _ap != null and _ap.has_animation(full_extra):
			return full_extra
	return anim  # 最终兜底:无 library 前缀

func _play(anim: String) -> void:
	if _ap == null or anim == "":
		return
	if not _ap.has_animation(anim):
		return
	if _last_anim == anim and _ap.is_playing():
		return
	_ap.play(anim)
	_last_anim = anim

func _anim_length(full: String) -> float:
	if _ap == null or not _ap.has_animation(full):
		return 0.3
	var a: Animation = _ap.get_animation(full)
	if a == null:
		return 0.3
	return float(a.length)
