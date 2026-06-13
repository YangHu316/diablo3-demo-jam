extends Node

# 5槽技能输入/CD/资源管理器。挂在 Player 子节点。
# 流程: 输入按下 -> CD 检查 -> Focus 资源检查 -> 扣除 -> emit skill_activated
# 真正的执行逻辑由 SkillExecutor 监听 skill_activated 自行处理。
#
# slot_skills 元素期望是 SkillData (res://scripts/skills/skill_data.gd) 的 .tres 实例,
# 但用 Resource 弱类型避免跨文件 class_name 解析问题,运行时 duck-typing 取属性。

signal skill_activated(slot_index: int, skill_data: Resource)
signal cooldown_changed(slot_index: int, remaining: float, total: float)

const SLOT_COUNT: int = 5
# slot 0 = 左键, 1 = 右键, 2/3/4 = 数字键 1/2/3
const SLOT_ACTIONS: Array = [
	"attack_primary",
	"attack_secondary",
	"skill_1",
	"skill_2",
	"skill_3",
]

# 默认槽位 -> 技能资源路径。Inspector 里若已填 slot_skills 则覆盖。
const DEFAULT_SKILL_PATHS: Dictionary = {
	0: "res://scripts/skills/data/piercing_arrow.tres",     # 左键 利箭
	1: "res://scripts/skills/data/multishot.tres",          # 右键 多重射击
	2: "res://scripts/skills/data/frost_arrow.tres",        # 键1 冰冻箭
	3: "res://scripts/skills/data/dodge_roll.tres",         # 键2 翻滚
	4: "res://scripts/skills/data/valkyrie_summon.tres",    # 键3 女武神
}

# 注:这里不用 Array[SkillData] 强类型,避免跨文件 class_name 解析问题。
# 元素期望是 SkillData 资源(skill_data.gd 实例)。
@export var slot_skills: Array[Resource] = []
# 是否在 Hold(按住)模式下持续触发。射击类 hold=true 让玩家按住连发(CD 限速);
# 翻滚/召唤这类一次性技能改 just_pressed,避免按住反复触发。
@export var slot_hold_trigger: Array[bool] = [true, true, true, false, false]

var _cooldowns: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	_cooldowns.resize(SLOT_COUNT)
	for i in range(SLOT_COUNT):
		_cooldowns[i] = 0.0

	# 保证 slot_skills 长度为 5
	while slot_skills.size() < SLOT_COUNT:
		slot_skills.append(null)
	if slot_skills.size() > SLOT_COUNT:
		slot_skills.resize(SLOT_COUNT)

	# 用默认路径填空槽
	for slot_key in DEFAULT_SKILL_PATHS.keys():
		var slot: int = int(slot_key)
		if slot_skills[slot] != null:
			continue
		var path: String = DEFAULT_SKILL_PATHS[slot_key]
		if ResourceLoader.exists(path):
			var sd: Resource = load(path)
			if sd != null:
				slot_skills[slot] = sd

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
		var pressed: bool
		if i < slot_hold_trigger.size() and slot_hold_trigger[i]:
			pressed = Input.is_action_pressed(action)
		else:
			pressed = Input.is_action_just_pressed(action)
		if pressed:
			_try_activate(i)

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
