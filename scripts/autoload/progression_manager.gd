extends Node

# ProgressionManager (Autoload): XP / level / attribute growth.
# Day1 任务5 完整实现; 此处先定下对外信号契约 (Hour-0 与战斗①敲定).
#
# 信号契约:
#   xp_gained(current_xp, xp_to_next, level)  -> HUD 经验条
#   level_up(new_level, unlocked)             -> 战斗① 接此解锁技能槽/技能/被动
# unlocked: Array[String]，来自 XPCurve.unlocks_at(level)，如 ["slot_2","skill_multishot"].

signal xp_gained(current_xp: int, xp_to_next: int, level: int)
signal level_up(new_level: int, unlocked: Array)

var level: int = 1
var current_xp: int = 0

func _ready() -> void:
	# 监听击杀以累计 XP (战斗① 的怪挂等级元数据 "monster_level").
	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null and cm.has_signal("enemy_killed"):
		cm.enemy_killed.connect(_on_enemy_killed)

func _on_enemy_killed(enemy, _killer, _overkill: int, _dir: Vector3) -> void:
	# Day1 任务5 填充: 取怪物等级 -> 查 DataTables xp -> add_xp().
	# 占位: 默认每杀给 0, 待任务5 接入数值.
	pass

# 任务5 实现: 加 XP, 跨级时循环发 level_up.
func add_xp(_amount: int) -> void:
	pass
