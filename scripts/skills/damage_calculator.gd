extends RefCounted

# 伤害公式集中点。后续接入装备/属性面板,改这里就行。
# damage = weapon_avg * skill_multiplier * (1 + dexterity/100) * crit * (1 + elemental%)
#
# 注:不使用 class_name + 跨文件类型注解,避免 Godot 4 首次扫描时的全局类解析顺序问题。
# 调用方式:const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")
#          DamageCalculator.compute(sd)

# 当前为占位常量,后续替换为 player 属性面板/装备数据。
const WEAPON_AVG: float = 15.0
const DEXTERITY: int = 20
const CRIT_RATE: float = 0.05
const CRIT_DAMAGE: float = 1.5
const ELEMENTAL_BONUS: float = 0.0  # 元素加成% (例如火焰 0.20 = +20%)

# 计算一次命中的伤害,返回 { damage, is_crit, element }。
# sd: SkillData 资源(避免硬性类型注解,这里用 Variant)
static func compute(sd) -> Dictionary:
	if sd == null:
		return {"damage": 0, "is_crit": false, "element": "physical"}
	var base: float = WEAPON_AVG * float(sd.skill_multiplier) * (1.0 + float(DEXTERITY) / 100.0)
	var is_crit: bool = randf() < CRIT_RATE
	if is_crit:
		base *= CRIT_DAMAGE
	base *= (1.0 + ELEMENTAL_BONUS)
	return {
		"damage": int(round(base)),
		"is_crit": is_crit,
		"element": String(sd.element),
	}
