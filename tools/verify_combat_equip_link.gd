extends SceneTree

# 运行时验证(战斗组①: 装备聚合 → 伤害计算 联通,2026-06-13 P0 修复)。
# 复现 SkillExecutor._on_stats_changed 的真实代码路径:
#   Inventory.stats_changed(total_stats) → DamageCalculator.refresh_from_stats(total_stats)
# 覆盖:
#   ① 武器伤害完全由装备决定(未装弓回退基底 15)
#   ② 敏捷/暴击/暴伤 词缀按口径(%/100)聚合进伤害公式
#   ③ 精准被动重构:换装重算后被动加成不丢失
#   ④ 随从伤害实时跟随 weapon_avg(女武神×2 / 圣堂武士×1.5)
#   ⑤ 换装变强 端到端:换更好的弓 → compute() 伤害上升
# Run headless:
#   godot --headless --path . --script res://tools/verify_combat_equip_link.gd

const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")

var _fail := 0

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  - ", msg)
	else:
		_fail += 1
		print("  FAIL- ", msg)

class FakeProg:
	extends Node
	var agility: int = 20
	var vitality: int = 30
	var level: int = 1

func _make_item(name: String, slot: int, stat_kind: int, value: float, q: int = 0) -> ItemInstance:
	var it := ItemInstance.new()
	it.display_name = name
	it.slot = slot
	it.quality = q
	var affs: Array[Dictionary] = []
	affs.append({"stat_kind": stat_kind, "value": value, "is_percent": false, "affix_id": &"test"})
	it.affixes = affs
	return it

# 一件可带多条词缀的物品(测多词缀聚合)。
func _make_multi(name: String, slot: int, lines: Array) -> ItemInstance:
	var it := ItemInstance.new()
	it.display_name = name
	it.slot = slot
	var affs: Array[Dictionary] = []
	for l in lines:
		affs.append({"stat_kind": int(l[0]), "value": float(l[1]), "is_percent": false, "affix_id": &"test"})
	it.affixes = affs
	return it

# 复现 SkillExecutor._on_stats_changed:把 inv 聚合结果推给 DamageCalculator。
func _sync(inv) -> void:
	DamageCalculator.refresh_from_stats(inv.get_total_stats())

func _init() -> void:
	var Inv = load("res://scripts/autoload/inventory.gd")
	var prog := FakeProg.new()

	# 复位 DamageCalculator 被动累加状态(static var 跨实例持久,测试前归零)。
	DamageCalculator._precision_crit_bonus = 0.0
	DamageCalculator._precision_cd_bonus = 0.0

	# =====================================================================
	print("\n=== 判定①: 武器伤害完全由装备决定(未装弓回退基底 15)===")
	var inv = Inv.new()
	inv._progression = prog
	_sync(inv)  # 空背包
	_ck(is_equal_approx(DamageCalculator.weapon_avg, 15.0),
		"未装弓 weapon_avg 回退基底 15.0 (实=%.1f)" % DamageCalculator.weapon_avg)

	var bow := _make_item("利弓", EquipSlots.Slot.BOW, AffixDef.StatKind.WEAPON_DAMAGE, 40.0)
	inv.add_item(bow); inv.equip(EquipSlots.Slot.BOW, bow)
	_sync(inv)
	_ck(is_equal_approx(DamageCalculator.weapon_avg, 40.0),
		"装弓后 weapon_avg = 词缀值 40.0 (实=%.1f)" % DamageCalculator.weapon_avg)

	# =====================================================================
	print("\n=== 判定②: 敏捷/暴击/暴伤 词缀按口径聚合 ===")
	# 基础敏捷 20(prog) + 头盔 +30 = 50 → dexterity=50
	var helm := _make_item("敏捷头", EquipSlots.Slot.HEAD, AffixDef.StatKind.AGILITY, 30.0)
	inv.add_item(helm); inv.equip(EquipSlots.Slot.HEAD, helm)
	# 手套:暴击率 +10(%) → crit_rate = 0.05 + 0.10 = 0.15
	var glove := _make_multi("暴击手套", EquipSlots.Slot.GLOVES, [
		[AffixDef.StatKind.CRIT_CHANCE, 10.0],
		[AffixDef.StatKind.CRIT_DAMAGE, 50.0],   # 暴伤 +50% → 1.5 + 0.5 = 2.0
	])
	inv.add_item(glove); inv.equip(EquipSlots.Slot.GLOVES, glove)
	_sync(inv)
	_ck(DamageCalculator.dexterity == 50,
		"dexterity = 20(基础)+30(词缀) = 50 (实=%d)" % DamageCalculator.dexterity)
	_ck(is_equal_approx(DamageCalculator.crit_rate, 0.15),
		"crit_rate = 0.05基底 + 10%%/100 = 0.15 (实=%.3f)" % DamageCalculator.crit_rate)
	_ck(is_equal_approx(DamageCalculator.crit_damage, 2.0),
		"crit_damage = 1.5基底 + 50%%/100 = 2.0 (实=%.3f)" % DamageCalculator.crit_damage)

	# =====================================================================
	print("\n=== 判定③: 精准被动重构 — 换装重算后不丢失 ===")
	DamageCalculator.apply_precision_passive()  # +8% 暴击 / +15% 暴伤
	_ck(is_equal_approx(DamageCalculator.crit_rate, 0.23),
		"被动后 crit_rate = 0.15 + 0.08 = 0.23 (实=%.3f)" % DamageCalculator.crit_rate)
	_ck(is_equal_approx(DamageCalculator.crit_damage, 2.15),
		"被动后 crit_damage = 2.0 + 0.15 = 2.15 (实=%.3f)" % DamageCalculator.crit_damage)
	# 换一件手套(触发 stats_changed 重算)→ 被动加成必须仍在
	var glove2 := _make_multi("暴击手套V2", EquipSlots.Slot.GLOVES, [
		[AffixDef.StatKind.CRIT_CHANCE, 20.0],   # 暴击 +20% → 0.05 + 0.20 + 0.08(被动) = 0.33
		[AffixDef.StatKind.CRIT_DAMAGE, 50.0],
	])
	inv.add_item(glove2); inv.equip(EquipSlots.Slot.GLOVES, glove2)
	_sync(inv)
	_ck(is_equal_approx(DamageCalculator.crit_rate, 0.33),
		"换装重算后被动仍在: 0.05+0.20+0.08 = 0.33 (实=%.3f)" % DamageCalculator.crit_rate)
	_ck(is_equal_approx(DamageCalculator.crit_damage, 2.15),
		"换装重算后暴伤被动仍在: 1.5+0.5+0.15 = 2.15 (实=%.3f)" % DamageCalculator.crit_damage)

	# =====================================================================
	print("\n=== 判定④: 随从伤害实时跟随 weapon_avg ===")
	# weapon_avg 当前 = 40。女武神 ×2 = 80,圣堂武士 ×1.5 = 60。
	var Valk = load("res://scripts/entities/valkyrie.gd")
	var Templar = load("res://scripts/entities/templar.gd")
	var valk = Valk.new()
	var tmpl = Templar.new()
	_ck(valk._current_damage() == 80,
		"女武神 = weapon_avg(40)×2 = 80 (实=%d)" % valk._current_damage())
	_ck(tmpl._current_damage() == 60,
		"圣堂武士 = weapon_avg(40)×1.5 = 60 (实=%d)" % tmpl._current_damage())
	valk.free(); tmpl.free()

	# =====================================================================
	print("\n=== 判定⑤: 换装变强 端到端(更好的弓 → 伤害上升)===")
	# 用确定性技能倍率,关掉暴击随机性影响:取非暴击基线对比。
	var sd = null
	if ResourceLoader.exists("res://scripts/skills/skill_data.gd"):
		sd = load("res://scripts/skills/skill_data.gd").new()
	if sd != null:
		sd.skill_multiplier = 1.0
		sd.element = &"physical"
		# 当前弓 40 → 期望非暴基线 = 40 * 1.0 * (1+50/100) = 60
		DamageCalculator.crit_rate = 0.0  # 临时关暴击,只看基线
		var dmg_lo: int = int(DamageCalculator.compute(sd).get("damage", 0))
		# 换更强的弓(80)
		var bow2 := _make_item("强弓", EquipSlots.Slot.BOW, AffixDef.StatKind.WEAPON_DAMAGE, 80.0)
		inv.add_item(bow2); inv.equip(EquipSlots.Slot.BOW, bow2)
		_sync(inv)
		DamageCalculator.crit_rate = 0.0
		var dmg_hi: int = int(DamageCalculator.compute(sd).get("damage", 0))
		_ck(dmg_lo == 60, "弱弓(40) 基线伤害 = 40×1.0×1.5 = 60 (实=%d)" % dmg_lo)
		_ck(dmg_hi == 120, "强弓(80) 基线伤害 = 80×1.0×1.5 = 120 (实=%d)" % dmg_hi)
		_ck(dmg_hi > dmg_lo, "换更强的弓 → 伤害上升 (%d → %d) 换装变强 V2 联通" % [dmg_lo, dmg_hi])
	else:
		print("  (skip - skill_data.gd 不存在)")

	# =====================================================================
	print("\n=== 判定⑥: 真实数据锚点 — 真 piercing_arrow.tres × L8 策划参考体 ===")
	# 锚定 数值表/player_combat_reference.csv L8 标准体:
	#   武器均伤 30 / 敏捷 78 / 利箭(155%)单发期望 ≈ 82
	#   公式校验: 30 × 1.55 × (1 + 78/100) = 30 × 1.55 × 1.78 = 82.77 → round 83
	var real_skill = null
	if ResourceLoader.exists("res://scripts/skills/data/piercing_arrow.tres"):
		real_skill = load("res://scripts/skills/data/piercing_arrow.tres")
	if real_skill != null:
		_ck(is_equal_approx(float(real_skill.skill_multiplier), 1.55),
			"真 piercing_arrow.tres skill_multiplier = 1.55 (实=%.2f)" % float(real_skill.skill_multiplier))
		# 用一个新 inv 搭 L8 标准体:武器 30 + 敏捷词缀凑到 78(基础 20 → 补 58)。
		var inv8 = Inv.new()
		inv8._progression = prog
		var bow8 := _make_item("L8标准弓", EquipSlots.Slot.BOW, AffixDef.StatKind.WEAPON_DAMAGE, 30.0)
		var dex8 := _make_item("L8敏捷件", EquipSlots.Slot.AMULET, AffixDef.StatKind.AGILITY, 58.0)
		inv8.add_item(bow8); inv8.equip(EquipSlots.Slot.BOW, bow8)
		inv8.add_item(dex8); inv8.equip(EquipSlots.Slot.AMULET, dex8)
		_sync(inv8)
		DamageCalculator.crit_rate = 0.0  # 取非暴基线对齐"单发期望"列
		_ck(DamageCalculator.weapon_avg == 30.0 and DamageCalculator.dexterity == 78,
			"L8 标准体: weapon=30 dex=78 (实 weapon=%.0f dex=%d)" % [DamageCalculator.weapon_avg, DamageCalculator.dexterity])
		var arrow_dmg: int = int(DamageCalculator.compute(real_skill).get("damage", 0))
		_ck(arrow_dmg == 83,
			"利箭基线 = 30×1.55×1.78 = 82.77 → 83,匹配 CSV 期望 82±1 (实=%d)" % arrow_dmg)
	else:
		print("  (skip - piercing_arrow.tres 不存在)")

	print("\n========================================")
	if _fail == 0:
		print("VERIFY OK - 装备聚合↔伤害计算 运行时联通全部通过")
	else:
		print("VERIFY FAIL - %d 项未通过" % _fail)
	quit()
