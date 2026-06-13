extends Resource
class_name AffixDef

# Affix definition: one rollable stat line (词缀池条目).
# Source: 04-Demo装备与掉落 §4, 附录A §11. 10 affixes total (6 attack / 3 defense / 1 utility).

enum Category { ATTACK, DEFENSE, UTILITY }
enum StatKind {
	AGILITY,          # ① 主属性敏捷 +1% 技能伤害/点
	CRIT_CHANCE,      # ② 暴击率 %
	CRIT_DAMAGE,      # ③ 暴击伤害 %
	ATTACK_SPEED,     # ④ 攻击速度 %
	WEAPON_DAMAGE,    # ⑤ 武器伤害 min~max (仅弓)
	SKILL_DAMAGE,     # ⑥ 技能伤害 %
	VITALITY,         # ⑦ 体能
	ARMOR,            # ⑧ 护甲
	ALL_RESIST,       # ⑨ 全抗性
	MOVE_SPEED        # ⑩ 移动速度 % (仅靴)
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var category: Category = Category.ATTACK
@export var stat_kind: StatKind = StatKind.AGILITY
@export var is_percent: bool = false          # 数值是百分比还是绝对值
@export var max_per_item: int = 99            # 功能类(移速)每件最多 1 条

# Tier 数值范围 [min, max]. T2 在 T1/T3 间线性内插.
@export var t1_min: float = 0.0
@export var t1_max: float = 0.0
@export var t3_min: float = 0.0
@export var t3_max: float = 0.0

# 可出现部位 (EquipSlot.Slot 的字符串名集合; 空 = 全部位).
@export var allowed_slots: Array[StringName] = []

# 在指定 tier(1/2/3) roll 出一个具体数值.
func roll_value(tier: int, rng: RandomNumberGenerator) -> float:
	var lo: float
	var hi: float
	match tier:
		1:
			lo = t1_min
			hi = t1_max
		3:
			lo = t3_min
			hi = t3_max
		_:
			lo = (t1_min + t3_min) * 0.5
			hi = (t1_max + t3_max) * 0.5
	return rng.randf_range(lo, hi)

# 指定 tier 的范围上限 (顶值). 史诗"保送1条顶值词缀"用.
func max_value(tier: int) -> float:
	match tier:
		1:
			return t1_max
		3:
			return t3_max
		_:
			return (t1_max + t3_max) * 0.5
