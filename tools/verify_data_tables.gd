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
	for id in [&"trash", &"elite_blue", &"champion_yellow", &"butcher"]:
		var s5 = loader.get_monster_stats(id, 5)
		var s7 = loader.get_monster_stats(id, 7)
		var s8 = loader.get_monster_stats(id, 8)
		print("  %s  L5=%s  L7=%s  L8=%s" % [id, s5, s7, s8])

	print("\n-- XP curve --")
	for lvl in range(1, loader.get_max_level() + 1):
		print("  L%d -> next needs %d xp; tier=%d; agi=%d vit=%d hp=%d; unlock=%s" % [
			lvl, loader.get_xp_to_next(lvl), loader.get_tier_for_level(lvl),
			loader.xp_curve.agility_at(lvl), loader.xp_curve.vitality_at(lvl),
			loader.xp_curve.max_hp_at(lvl), str(loader.xp_curve.unlocks_at(lvl))])

	print("\nVERIFY OK")
	quit()
