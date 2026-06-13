extends RefCounted

# 伤害公式集中点。后续接入装备/属性面板,改这里就行。
# damage = weapon_avg * skill_multiplier * (1 + dexterity/100) * crit * (1 + elemental%)
#
# 注:不使用 class_name + 跨文件类型注解,避免 Godot 4 首次扫描时的全局类解析顺序问题。
# 调用方式:const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")
#          DamageCalculator.compute(sd)

# ── 当前为占位常量,后续替换为 player 属性面板/装备数据 ─────────
# 注:从 const 改为 static var,以便被被动技能/装备 stats_changed 修改。
static var weapon_avg: float = 15.0
static var dexterity: int = 20
static var crit_rate: float = 0.05
static var crit_damage: float = 1.5
static var elemental_bonus: float = 0.0  # 元素加成% (例如火焰 0.20 = +20%)

# 被动:致命精准(策划 §4.3 a)
# 暴击率 +8%,暴伤 +15%(占位:不区分 15 码外条件,简化对所有距离生效)
# 后续接系统组装备聚合时,这里改成读 stats_changed 的 crit_rate / crit_damage 字段
static func apply_precision_passive() -> void:
	crit_rate += 0.08
	crit_damage += 0.15

# 计算一次命中的伤害,返回 { damage, is_crit, element }。
# sd: SkillData 资源(避免硬性类型注解,这里用 Variant)
static func compute(sd) -> Dictionary:
	if sd == null:
		return {"damage": 0, "is_crit": false, "element": "physical"}
	var base: float = weapon_avg * float(sd.skill_multiplier) * (1.0 + float(dexterity) / 100.0)
	var is_crit: bool = randf() < crit_rate
	if is_crit:
		base *= crit_damage
	base *= (1.0 + elemental_bonus)
	return {
		"damage": int(round(base)),
		"is_crit": is_crit,
		"element": String(sd.element),
	}
