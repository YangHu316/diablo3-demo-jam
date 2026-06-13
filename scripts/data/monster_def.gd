extends Resource
class_name MonsterDef

# Monster stat definition with level-scaling formulas.
# Source: 附录A 白怪基础表, 05-Demo成长与数值 §怪物表.
# 白怪生命 = base_health * health_growth^(L-1)
# 白怪攻击 = base_attack * attack_growth^(L-1)
# 白怪经验 = base_xp     * xp_growth^(L-1)

@export var id: StringName = &""
@export var display_name: String = ""

# 等级 1 基准值.
@export var base_health: float = 40.0
@export var base_attack: float = 15.0
@export var base_xp: float = 8.0

# 逐级增长系数.
@export var health_growth: float = 1.31
@export var attack_growth: float = 1.17
@export var xp_growth: float = 1.45

@export var level_cap: int = 8        # 动态等级同步, 8 封顶

# 精英/首领倍率 (相对白怪). 白怪填 1.0.
@export var health_mult: float = 1.0
@export var attack_mult: float = 1.0

@export var is_boss: bool = false
@export var gold_per_kill_mult: float = 1.0   # 白怪掉金 = 2*level; 精英 *8

func health_at(level: int) -> int:
	var l: int = clampi(level, 1, level_cap)
	return int(round(base_health * pow(health_growth, l - 1) * health_mult))

func attack_at(level: int) -> int:
	var l: int = clampi(level, 1, level_cap)
	return int(round(base_attack * pow(attack_growth, l - 1) * attack_mult))

func xp_at(level: int) -> int:
	var l: int = clampi(level, 1, level_cap)
	return int(round(base_xp * pow(xp_growth, l - 1)))
