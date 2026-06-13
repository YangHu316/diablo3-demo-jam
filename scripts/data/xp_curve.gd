extends Resource
class_name XPCurve

# Level / XP progression curve.
# Source: 05-Demo成长与数值 §4.1. Levels 1~8, XP_to_next(L+1) = XP_to_next(L) * 1.6.
# L1 base = 300 => [300, 480, 768, 1229, 1966, 3146, 5033] (XP to reach next level).

@export var max_level: int = 8
@export var xp_to_next: PackedInt32Array = PackedInt32Array([300, 480, 768, 1229, 1966, 3146, 5033])

# 每级主属性成长.
@export var agility_per_level: int = 6     # 敏捷: 初始10, +6/级 => L8=52
@export var vitality_per_level: int = 4    # 体能: 初始10, +4/级 => L8=38
@export var base_agility: int = 10
@export var base_vitality: int = 10

# 生命公式: 40 + 10*level + 10*vitality.
@export var hp_base: int = 40
@export var hp_per_level: int = 10
@export var hp_per_vitality: int = 10

# 每级解锁内容 (索引 = 等级). 程序据此发 level_up 的 unlocked payload.
# 战斗① 监听后据 unlocked 字符串解锁技能槽/技能/被动.
@export var unlocks: Dictionary = {}

func xp_required(level: int) -> int:
	# 从 level 升到 level+1 所需 XP. level 范围 1..max_level-1.
	var idx: int = level - 1
	if idx < 0 or idx >= xp_to_next.size():
		return -1   # 已满级或非法
	return xp_to_next[idx]

func agility_at(level: int) -> int:
	return base_agility + agility_per_level * (clampi(level, 1, max_level) - 1)

func vitality_at(level: int) -> int:
	return base_vitality + vitality_per_level * (clampi(level, 1, max_level) - 1)

func max_hp_at(level: int) -> int:
	return hp_base + hp_per_level * clampi(level, 1, max_level) + hp_per_vitality * vitality_at(level)

func unlocks_at(level: int) -> Array:
	if unlocks.has(level):
		return unlocks[level]
	return []
