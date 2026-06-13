extends Node

# ProgressionManager (Autoload): XP / level / attribute growth.
# Day1 任务5 实现.
#
# 信号契约:
#   xp_gained(current_xp, xp_to_next, level)  -> HUD 经验条
#   level_up(new_level, unlocked)             -> 战斗① 接此解锁技能槽/技能/被动
#   stats_changed(stats)                      -> HUD/战斗① 刷新主属性
# unlocked: Array[String]，来自 XPCurve.unlocks_at(level)，如 ["slot_2","skill_multishot"].
#
# 数据来源: DataTables (xp_curve 决定升级曲线/属性成长; monsters 决定每只怪给多少 XP).
# 击杀来源: CombatManager.enemy_killed(enemy, killer, overkill, dir).
#   战斗① 需在怪物实例上挂元数据: set_meta("monster_id", &"trash") / set_meta("monster_level", 3).
#   缺省处理: 无 monster_id 时用默认怪, 无 monster_level 时用玩家当前等级.

signal xp_gained(current_xp: int, xp_to_next: int, level: int)
signal level_up(new_level: int, unlocked: Array)
signal stats_changed(stats: Dictionary)

# 怪物实例缺省元数据时的兜底 (战斗① 接入前可跑通).
const DEFAULT_MONSTER_ID: StringName = &"trash"

var level: int = 1
var current_xp: int = 0          # 当前等级内已累计的 XP (升级后清零/扣除)

# 当前主属性 (随升级成长, 装备加成由 Inventory 另算).
var agility: int = 0
var vitality: int = 0
var max_hp: int = 0

# 依赖注入: 默认走 autoload (/root/DataTables); 测试 harness 可直接赋值.
var _data_tables: Node = null

func _ready() -> void:
	_init_stats_for_level()
	# 监听击杀以累计 XP (战斗① 的怪挂元数据 "monster_id" / "monster_level").
	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null and cm.has_signal("enemy_killed"):
		cm.enemy_killed.connect(_on_enemy_killed)

# 取 DataTables: 优先注入引用, 否则在树内时取 autoload.
func _dt() -> Node:
	if _data_tables != null:
		return _data_tables
	if is_inside_tree():
		_data_tables = get_node_or_null("/root/DataTables")
	return _data_tables

# 按当前等级从曲线刷新主属性 (启动 & 升级后调用).
func _init_stats_for_level() -> void:
	var c: XPCurve = _curve()
	if c != null:
		agility = c.agility_at(level)
		vitality = c.vitality_at(level)
		max_hp = c.max_hp_at(level)

func _curve() -> XPCurve:
	var dt: Node = _dt()
	return dt.xp_curve if dt != null else null

# ---------------------------------------------------------------------------
# 击杀 -> XP
# ---------------------------------------------------------------------------
func _on_enemy_killed(enemy, _killer, _overkill: int, _dir: Vector3) -> void:
	add_xp(_xp_for_enemy(enemy))

# 从被击杀的怪物实例推断应给的 XP.
func _xp_for_enemy(enemy) -> int:
	var dt: Node = _dt()
	if dt == null:
		return 0

	var monster_id: StringName = DEFAULT_MONSTER_ID
	var monster_level: int = level   # 缺省按玩家等级 (同级怪)

	if enemy != null and is_instance_valid(enemy):
		if enemy.has_meta("monster_id"):
			monster_id = StringName(enemy.get_meta("monster_id"))
		if enemy.has_meta("monster_level"):
			monster_level = int(enemy.get_meta("monster_level"))

	var stats: Dictionary = dt.get_monster_stats(monster_id, monster_level)
	return int(stats.get("xp", 0))

# ---------------------------------------------------------------------------
# XP 累计 + 跨级升级
# ---------------------------------------------------------------------------
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	var c: XPCurve = _curve()
	if c == null:
		return

	current_xp += amount

	# 已满级: 不再升级, 经验条停在满级状态.
	if level >= c.max_level:
		current_xp = 0
		xp_gained.emit(current_xp, _xp_to_next(), level)
		return

	# 跨级循环: 一次击杀可能连升多级.
	while level < c.max_level:
		var need: int = c.xp_required(level)
		if need <= 0 or current_xp < need:
			break
		current_xp -= need
		_level_up()

	# 升到满级后清空溢出, 经验条置满.
	if level >= c.max_level:
		current_xp = 0

	xp_gained.emit(current_xp, _xp_to_next(), level)

func _level_up() -> void:
	level += 1
	_init_stats_for_level()
	var c: XPCurve = _curve()
	var unlocked: Array = c.unlocks_at(level) if c != null else []
	level_up.emit(level, unlocked)
	stats_changed.emit(get_stats())

# 当前等级升到下一级所需 XP (-1 = 已满级).
func _xp_to_next() -> int:
	var c: XPCurve = _curve()
	if c == null:
		return -1
	return c.xp_required(level)

# ---------------------------------------------------------------------------
# 查询 API (HUD / 战斗① / 存档)
# ---------------------------------------------------------------------------
func get_stats() -> Dictionary:
	return {
		"level": level,
		"current_xp": current_xp,
		"xp_to_next": _xp_to_next(),
		"agility": agility,
		"vitality": vitality,
		"max_hp": max_hp,
	}

func is_max_level() -> bool:
	var c: XPCurve = _curve()
	return c != null and level >= c.max_level
