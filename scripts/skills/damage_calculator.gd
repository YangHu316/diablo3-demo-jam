extends RefCounted

# 伤害公式集中点。V3.0:全部锁死为 player_loadout.csv 中期 build 数值,不接装备/升级。
# damage = weapon_avg * skill_multiplier * (1 + dexterity/100) * crit * (1 + elemental%)
#
# 注:不使用 class_name + 跨文件类型注解,避免 Godot 4 首次扫描时的全局类解析顺序问题。
# 调用方式:const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")
#          DamageCalculator.compute(sd)

# ── V3.0 锁死面板(数值表/player_loadout.csv 爽快割草版)──────────────
# weapon_avg 40, dexterity 400, crit 35%(微调·原45%), crit_damage ×6.0(+500%), elem +40%
const LOCKED_WEAPON_AVG: float = 40.0
const LOCKED_DEXTERITY: int = 400
const LOCKED_CRIT_RATE: float = 0.35
const LOCKED_CRIT_DAMAGE: float = 6.0      # +500% = ×6.0
const LOCKED_ELEMENTAL_BONUS: float = 0.40 # +40%

# 仍然以 static var 暴露(向后兼容旧调用),但不再接 Inventory.stats_changed,
# 也不再被 apply_precision_passive 修改 — V3.0 取消"成长/被动加成"。
static var weapon_avg: float = LOCKED_WEAPON_AVG
static var dexterity: int = LOCKED_DEXTERITY
static var crit_rate: float = LOCKED_CRIT_RATE
static var crit_damage: float = LOCKED_CRIT_DAMAGE
static var elemental_bonus: float = LOCKED_ELEMENTAL_BONUS

# 功能塔·伤害塔全局乘区 (TowerBuffManager 写: 激活=1+加成, 清除=1.0). 套公式末端, 零侵入锁死面板.
static var tower_dmg_mult: float = 1.0

# V3.0:取消装备聚合驱动。skill_executor 不再调用此函数;留空实现避免老代码误调报错。
static func refresh_from_stats(_total_stats: Dictionary) -> void:
	# no-op:面板锁死,装备词缀不再改战斗数值。
	pass

# V3.0:取消"成长向"被动。留空避免老 unlock 触发报错。
static func apply_precision_passive() -> void:
	pass

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
	base *= tower_dmg_mult
	return {
		"damage": int(round(base)),
		"is_crit": is_crit,
		"element": String(sd.element),
	}
