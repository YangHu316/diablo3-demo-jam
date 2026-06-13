extends SceneTree

# Verification harness for DataTables loader (任务1/3). Run headless:
#   godot --headless --path . --script res://tools/verify_data_tables.gd

func _init() -> void:
	# Autoloads aren't active for --script SceneTree; instantiate the loader manually
	# and trigger loading directly (don't rely on _ready firing in this harness).
	var DataTablesScript = load("res://scripts/autoload/data_tables.gd")
	var loader = DataTablesScript.new()
	loader._load_all()
	print("is_loaded = ", loader.is_loaded)

	print("\n-- Affixes (%d) --" % loader.get_all_affixes().size())
	for a in loader.get_all_affixes():
		print("  %s [%s] T1(%.0f~%.0f) T3(%.0f~%.0f) slots=%s" % [
			a.display_name, a.id, a.t1_min, a.t1_max, a.t3_min, a.t3_max,
			str(a.allowed_slots)])

	print("\n-- get_affixes_for_slot('boots') --")
	for a in loader.get_affixes_for_slot(&"boots"):
		print("  ", a.display_name)

	print("\n-- Legendaries (%d), 首橙白名单: --" % loader.get_all_legendaries().size())
	for l in loader.get_first_orange_whitelist():
		print("  %s (%s) effect=%s" % [l.display_name, l.slot, l.effect_id])

	print("\n-- Monster stats by level --")
	for id in [&"trash", &"elite_blue", &"champion_yellow", &"skeleton_guard", &"butcher"]:
		var s5 = loader.get_monster_stats(id, 5)
		var s7 = loader.get_monster_stats(id, 7)
		var s8 = loader.get_monster_stats(id, 8)
		print("  %s  L5=%s  L7=%s  L8=%s" % [id, s5, s7, s8])

	# === 与 数值表/*.csv (V2.1) 锁定值对照 ===
	# 注: CSV 是逐级"预取整"绝对值, schema 是"基数×增长率^(L-1)"公式,
	# 两者天然存在 ±1~2 取整差; 断言用容差校验"在取整范围内一致".
	print("\n-- 数值表锁定值断言 --")
	# 白怪 L8 生命 265 / 攻 45 / 经验 ≈107 (monsters.csv).
	var trash8 = loader.get_monster_stats(&"trash", 8)
	assert(trash8.health == 265, "白怪@8 生命应 265, 实际 %d" % trash8.health)
	assert(trash8.attack == 45, "白怪@8 攻击应 45, 实际 %d" % trash8.attack)
	assert(abs(trash8.xp - 107) <= 1, "白怪@8 经验应≈107, 实际 %d" % trash8.xp)
	# 屠夫 @7 生命≈11000 / 攻≈75 (constants.csv 锁定).
	var b7 = loader.get_monster_stats(&"butcher", 7)
	assert(abs(b7.health - 11000) < 600, "屠夫@7 生命应≈11000, 实际 %d" % b7.health)
	assert(abs(b7.attack - 75) < 5, "屠夫@7 攻击应≈75, 实际 %d" % b7.attack)
	# 骸骨卫士 @5 生命≈189 (白怪118×1.6) / 经验≈53 (35×1.5) (monsters.csv).
	var sg5 = loader.get_monster_stats(&"skeleton_guard", 5)
	assert(abs(sg5.health - 189) <= 2, "骸骨卫士@5 生命应≈189, 实际 %d" % sg5.health)
	assert(abs(sg5.xp - 53) <= 2, "骸骨卫士@5 经验应≈53, 实际 %d" % sg5.xp)
	print("  白怪@8=%s / 屠夫@7=%s / 骸骨卫士@5=%s  ✓" % [trash8, b7, sg5])

	print("\n-- XP curve --")
	for lvl in range(1, loader.get_max_level() + 1):
		print("  L%d -> next needs %d xp; tier=%d; agi=%d vit=%d hp=%d; unlock=%s" % [
			lvl, loader.get_xp_to_next(lvl), loader.get_tier_for_level(lvl),
			loader.xp_curve.agility_at(lvl), loader.xp_curve.vitality_at(lvl),
			loader.xp_curve.max_hp_at(lvl), str(loader.xp_curve.unlocks_at(lvl))])

	print("\nVERIFY OK")
	quit()
