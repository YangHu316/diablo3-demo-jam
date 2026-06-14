extends RefCounted

# 伤害公式集中点。后续接入装备/属性面板,改这里就行。
# damage = weapon_avg * skill_multiplier * (1 + dexterity/100) * crit * (1 + elemental%)
#
# 注:不使用 class_name + 跨文件类型注解,避免 Godot 4 首次扫描时的全局类解析顺序问题。
# 调用方式:const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")
#          DamageCalculator.compute(sd)

# ── 装备聚合后的属性(由 SkillExecutor 监听 Inventory.stats_changed 写回)──────
# 口径(策划 数值表/player_combat_reference.csv + affixes.csv):
#   weapon_avg   : 完全由装备 WEAPON_DAMAGE 词缀决定,未装弓回退 BASE_WEAPON_AVG。
#   dexterity    : AGILITY 词缀 + 升级基础敏捷(get_total_stats 已含基础)。
#   crit_rate    : 基底 BASE_CRIT_RATE(5%) + CRIT_CHANCE 词缀(词缀单位是%,需 /100)。
#   crit_damage  : 基底 BASE_CRIT_DAMAGE(×1.5) + CRIT_DAMAGE 词缀(%,需 /100)。
#   elemental_bonus: 暂无对应词缀,占位 0.0。
# 这些值在每次 stats_changed 时由 refresh_from_stats() 整体重算,不做增量累加。
const BASE_WEAPON_AVG: float = 15.0
const BASE_CRIT_RATE: float = 0.05
const BASE_CRIT_DAMAGE: float = 1.5

static var weapon_avg: float = BASE_WEAPON_AVG
static var dexterity: int = 20
static var crit_rate: float = BASE_CRIT_RATE
static var crit_damage: float = BASE_CRIT_DAMAGE
static var elemental_bonus: float = 0.0  # 元素加成% (例如火焰 0.20 = +20%)

# 被动加成(与装备聚合解耦,独立累加;refresh_from_stats 重算时不会被覆盖)。
# 致命精准(策划 §4.3 a):暴击率 +8%,暴伤 +15%。
static var _precision_crit_bonus: float = 0.0
static var _precision_cd_bonus: float = 0.0

# AffixDef.StatKind 枚举(避免跨文件类型依赖,这里硬编码整数,与 affix_def.gd 对齐)。
const _SK_AGILITY: int = 0
const _SK_CRIT_CHANCE: int = 1
const _SK_CRIT_DAMAGE: int = 2
const _SK_WEAPON_DAMAGE: int = 4

# 由 SkillExecutor 在 Inventory.stats_changed 时调用,整体重算面板属性。
# total_stats: { AffixDef.StatKind(int): total_value(float) }。
# 词缀单位约定(数值表/affixes.csv):暴击/暴伤为百分数(8.0 = 8%),武器/敏捷为绝对值。
static func refresh_from_stats(total_stats: Dictionary) -> void:
	# 武器均伤:完全由装备 WEAPON_DAMAGE 词缀决定,未装弓(无该 key 或为 0)回退基底。
	var wd: float = float(total_stats.get(_SK_WEAPON_DAMAGE, 0.0))
	weapon_avg = wd if wd > 0.0 else BASE_WEAPON_AVG

	# 敏捷:get_total_stats 已含升级基础敏捷 + 词缀,直接取。
	dexterity = int(round(float(total_stats.get(_SK_AGILITY, float(dexterity)))))

	# 暴击率 / 暴伤:基底 + 词缀(词缀单位是%,/100 转小数)。再叠被动。
	crit_rate = BASE_CRIT_RATE + float(total_stats.get(_SK_CRIT_CHANCE, 0.0)) / 100.0 + _precision_crit_bonus
	crit_damage = BASE_CRIT_DAMAGE + float(total_stats.get(_SK_CRIT_DAMAGE, 0.0)) / 100.0 + _precision_cd_bonus

	# 元素加成暂无词缀,保持占位。

# 被动:致命精准(策划 §4.3 a)。
# 暴击率 +8%,暴伤 +15%(占位:不区分 15 码外条件,简化对所有距离生效)。
# 用独立被动字段累加,并把当前 crit 值直接补上;这样后续 refresh_from_stats 重算也不丢失。
static func apply_precision_passive() -> void:
	_precision_crit_bonus += 0.08
	_precision_cd_bonus += 0.15
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
