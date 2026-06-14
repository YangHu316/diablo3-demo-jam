extends Node

# 5槽技能输入/CD/资源管理器。挂在 Player 子节点。
# 流程: 输入按下 -> CD 检查 -> Focus 资源检查 -> 扣除 -> emit skill_activated
# 真正的执行逻辑由 SkillExecutor 监听 skill_activated 自行处理。
#
# slot_skills 元素期望是 SkillData (res://scripts/skills/skill_data.gd) 的 .tres 实例,
# 但用 Resource 弱类型避免跨文件 class_name 解析问题,运行时 duck-typing 取属性。

signal skill_activated(slot_index: int, skill_data: Resource)
signal cooldown_changed(slot_index: int, remaining: float, total: float)
# 引导技能(CHANNEL)信号 — SkillExecutor 据此启动 / 停止 引导循环
signal channel_started(slot_index: int, skill_data: Resource)
signal channel_stopped(slot_index: int, skill_data: Resource)

const SLOT_COUNT: int = 5
# slot 0 = 左键, 1 = 右键, 2/3/4 = 数字键 1/2/3
const SLOT_ACTIONS: Array = [
	"attack_primary",
	"attack_secondary",
	"skill_1",
	"skill_2",
	"skill_3",
]

# L1 默认装在槽 0 的技能(必出,玩家从一开始就能左键攻击)
# 其他 4 槽通过 ProgressionManager.level_up 解锁后填入。
const DEFAULT_L1_SKILL_PATH: String = "res://scripts/skills/data/piercing_arrow.tres"

# 系统组 ProgressionManager.level_up.unlocked 字符串 → (槽位, 技能 .tres 路径) 映射。
# unlock id 来自 data/xp_curve.tres 的 unlocks 字段(系统组维护)。
# 战斗组 skill_id 与 unlock id 不完全一致(piercing_arrow vs skill_puncture 等),
# 在这里桥接,避免改动数据表或 .tres 文件名。
# slot_N 类的解锁不在此表,因为我们的槽一直存在,只是没技能就响应失败 → 忽略 slot_N。
const UNLOCK_ID_TO_SKILL: Dictionary = {
	"skill_puncture":     [0, "res://scripts/skills/data/piercing_arrow.tres"],
	"skill_multishot":    [1, "res://scripts/skills/data/multishot.tres"],
	"skill_frost_arrow":  [2, "res://scripts/skills/data/frost_arrow.tres"],
	"skill_roll":         [3, "res://scripts/skills/data/dodge_roll.tres"],
	# V3.0:女武神召唤 → 箭雨风暴(引导型,SkillType.CHANNEL=4)
	"skill_valkyrie":     [4, "res://scripts/skills/data/arrow_storm.tres"],
	"skill_arrow_storm":  [4, "res://scripts/skills/data/arrow_storm.tres"],
}

# Inspector 里若已填 slot_skills 则覆盖默认行为(便于关卡 / 调试摆置)
@export var slot_skills: Array[Resource] = []
# 是否在 Hold(按住)模式下持续触发。射击类 hold=true 让玩家按住连发(CD 限速);
# 翻滚/召唤这类一次性技能改 just_pressed,避免按住反复触发。
@export var slot_hold_trigger: Array[bool] = [true, true, true, false, false]
# Day1 灰盒调试开关:为 true 时,_ready 直接装满 5 槽不等 level_up(便于测全部技能)。
# 集成阶段切回 false 验"L1 只能左键 → 升级解锁"流程。可以在 Inspector 覆盖。
@export var debug_unlock_all: bool = true

var _cooldowns: PackedFloat32Array = PackedFloat32Array()

# V3.0 LMB 门控:player.gd 决定何时让 LMB 槽 0 开火(点地走时不开火)。
# 默认 false,由 player.gd 每帧根据"是否锁定敌人在射程内/Shift 站桩"重新评估并 set_lmb_attack_armed(b)。
var _lmb_attack_armed: bool = false

# CHANNEL 类技能(skill_type=4):按住引导,松开停;每槽独立。
# 当前正在引导的槽位(-1=未引导)。同一帧只允许一个引导技能。
var _channeling_slot: int = -1

func set_lmb_attack_armed(b: bool) -> void:
	_lmb_attack_armed = b

# SkillType.CHANNEL 枚举值(与 skill_data.gd 对齐)— 避免跨文件 enum 引用
const _SKILL_TYPE_CHANNEL: int = 4

func _ready() -> void:
	_cooldowns.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		_cooldowns[i] = 0.0

	# 保证 slot_skills 长度为 5
	while slot_skills.size() < SLOT_COUNT:
		slot_skills.append(null)
	if slot_skills.size() > SLOT_COUNT:
		slot_skills.resize(SLOT_COUNT)

	# 默认装 L1 技能(利箭 → 槽 0),其余 4 槽留空,等 ProgressionManager.level_up 解锁
	if slot_skills[0] == null and ResourceLoader.exists(DEFAULT_L1_SKILL_PATH):
		var sd0: Resource = load(DEFAULT_L1_SKILL_PATH)
		if sd0 != null:
			slot_skills[0] = sd0

	# 调试模式:一键装满 5 槽(便于测试,不等升级)
	if debug_unlock_all:
		for unlock_id in UNLOCK_ID_TO_SKILL.keys():
			_apply_unlock(String(unlock_id))
		# 调试模式同时打开占位被动(精准)
		_apply_unlock("passive_precision")

	# 监听系统组的升级信号,据 unlocked 字段填充技能槽
	var pm: Node = get_node_or_null("/root/ProgressionManager")
	if pm != null and pm.has_signal("level_up"):
		pm.level_up.connect(_on_level_up)

# 系统组 ProgressionManager.level_up.unlocked 是 Array[String](xp_curve.unlocks_at(level))
func _on_level_up(_new_level: int, unlocked: Array) -> void:
	for raw in unlocked:
		_apply_unlock(String(raw))

# 把 unlock id 解析为"装技能 .tres 到对应槽";slot_N 类条目无效果(我们的槽一直在)
func _apply_unlock(unlock_id: String) -> void:
	# 被动:致命精准(策划 §4.3 a)— 占位实现,等系统组 Inventory.stats_changed 落地再改
	if unlock_id == "passive_precision":
		var DC = preload("res://scripts/skills/damage_calculator.gd")
		DC.apply_precision_passive()
		return
	if not UNLOCK_ID_TO_SKILL.has(unlock_id):
		# slot_N / passive_X / rune_X 等不影响主动技能槽,跳过
		return
	var pair: Array = UNLOCK_ID_TO_SKILL[unlock_id]
	var slot: int = int(pair[0])
	var path: String = String(pair[1])
	if slot < 0 or slot >= SLOT_COUNT:
		return
	if not ResourceLoader.exists(path):
		push_warning("SkillSlotManager: skill resource missing: %s" % path)
		return
	var sd: Resource = load(path)
	if sd == null:
		return
	slot_skills[slot] = sd
	_cooldowns[slot] = 0.0  # 解锁瞬间 CD 清零,首次可立即用
	cooldown_changed.emit(slot, 0.0, float(sd.cooldown))

func _process(delta: float) -> void:
	# 更新 CD
	for i in range(SLOT_COUNT):
		if _cooldowns[i] > 0.0:
			var prev: float = _cooldowns[i]
			_cooldowns[i] = max(0.0, _cooldowns[i] - delta)
			var sd: Resource = slot_skills[i]
			var total: float = 0.0
			if sd != null:
				total = float(sd.cooldown)
			if not is_equal_approx(prev, _cooldowns[i]):
				cooldown_changed.emit(i, _cooldowns[i], total)
	# 输入检测
	_poll_inputs()

func _poll_inputs() -> void:
	for i in range(SLOT_COUNT):
		var action: String = SLOT_ACTIONS[i]
		var sd_i: Resource = slot_skills[i]
		# CHANNEL 类技能特殊路径:按下=开始引导,松开=停止引导,期间无 CD,执行结束才进 CD
		if sd_i != null and int(sd_i.skill_type) == _SKILL_TYPE_CHANNEL:
			_handle_channel_input(i, action, sd_i)
			continue
		var pressed: bool
		if i < slot_hold_trigger.size() and slot_hold_trigger[i]:
			pressed = Input.is_action_pressed(action)
		else:
			pressed = Input.is_action_just_pressed(action)
		# V3.0:槽 0(LMB 利箭)只在 player 把它"装填"上才开火 — 否则点地走不开枪。
		if i == 0 and not _lmb_attack_armed:
			pressed = false
		if pressed:
			_try_activate(i)

# 引导输入处理:开始(just_pressed)/ 持续(executor 自管)/ 结束(just_released 或 强行停止)
func _handle_channel_input(slot: int, action: String, sd: Resource) -> void:
	if Input.is_action_just_pressed(action):
		# CD 未好 → 不能开
		if _cooldowns[slot] > 0.0:
			return
		# 同时只允许一个引导
		if _channeling_slot >= 0:
			return
		_channeling_slot = slot
		channel_started.emit(slot, sd)
	elif Input.is_action_just_released(action):
		if _channeling_slot == slot:
			_stop_channel(slot, sd)

# 由 SkillExecutor 在专注耗尽时调用,强行停掉引导
func stop_channel_external(slot: int) -> void:
	if _channeling_slot != slot:
		return
	var sd: Resource = slot_skills[slot]
	_stop_channel(slot, sd)

func _stop_channel(slot: int, sd: Resource) -> void:
	_channeling_slot = -1
	channel_stopped.emit(slot, sd)
	# 引导结束才进 CD(防止按一下就锁住)
	var cd: float = float(sd.cooldown) if sd != null else 0.0
	if cd > 0.0:
		_cooldowns[slot] = cd
		cooldown_changed.emit(slot, cd, cd)

func is_channeling() -> bool:
	return _channeling_slot >= 0

func _try_activate(slot: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	if _cooldowns[slot] > 0.0:
		return
	var sd: Resource = slot_skills[slot]
	if sd == null:
		return
	# 资源检查 + 扣除(consume 内部已经判断"够不够")
	var focus_cost: float = float(sd.focus_cost)
	if focus_cost > 0.0:
		var fr: Node = get_node_or_null("/root/FocusResource")
		if fr == null:
			push_warning("SkillSlotManager: FocusResource autoload not found")
			return
		if not fr.consume(focus_cost):
			# 蓝不够,按不动
			return
	# 进入 CD,广播激活
	var cd: float = float(sd.cooldown)
	_cooldowns[slot] = cd
	cooldown_changed.emit(slot, _cooldowns[slot], cd)
	skill_activated.emit(slot, sd)

# ── 公共 API ─────────────────────────────────────────────
func set_skill(slot: int, sd: Resource) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	slot_skills[slot] = sd
	_cooldowns[slot] = 0.0

func get_skill(slot: int) -> Resource:
	if slot < 0 or slot >= SLOT_COUNT:
		return null
	return slot_skills[slot]

func get_cooldown_remaining(slot: int) -> float:
	if slot < 0 or slot >= SLOT_COUNT:
		return 0.0
	return _cooldowns[slot]

# 强行清掉某槽的 CD(供翻滚的 cancels_attack_cooldowns 使用)
func cancel_cooldown(slot: int) -> void:
	if slot < 0 or slot >= SLOT_COUNT:
		return
	if _cooldowns[slot] <= 0.0:
		return
	var sd: Resource = slot_skills[slot]
	var total: float = float(sd.cooldown) if sd != null else 0.0
	_cooldowns[slot] = 0.0
	cooldown_changed.emit(slot, 0.0, total)
