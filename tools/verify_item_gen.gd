extends SceneTree

# Verify ItemGenerator (任务2). Run headless:
#   godot --headless --path . --script res://tools/verify_item_gen.gd

func _affix_str(a: Dictionary) -> String:
	var v = a["value"]
	var suffix: String = "%" if a["is_percent"] else ""
	return "%s +%s%s" % [a["display_name"], str(v), suffix]

func _print_item(item: ItemInstance) -> void:
	var qname: String = ItemInstance.QUALITY_NAMES[item.quality]
	var line: String = "  [%s] %s (iLvl %d, T%d, slot=%d)" % [qname, item.display_name, item.item_level, item.tier, item.slot]
	print(line)
	if item.is_legendary():
		print("     ★橙字: %s [%s]" % [item.legendary_effect_text, item.legendary_effect_id])
	for a in item.affixes:
		print("     - ", _affix_str(a))

func _init() -> void:
	var DataTablesScript = load("res://scripts/autoload/data_tables.gd")
	var dt = DataTablesScript.new()
	dt._load_all()
	print("DataTables loaded = ", dt.is_loaded)

	var gen = ItemGenerator.new(dt, 12345)   # 固定种子, 结果可复现

	print("\n=== 完成判定: roll 一件蓝装 + 一件黄装 ===")
	var magic = gen.generate(EquipSlots.Slot.GLOVES, 5, ItemInstance.Quality.MAGIC)
	_print_item(magic)
	assert(magic.quality == ItemInstance.Quality.MAGIC)
	assert(magic.affixes.size() >= 1 and magic.affixes.size() <= 2, "蓝装应 1~2 词缀")

	var rare = gen.generate(EquipSlots.Slot.BOW, 7, ItemInstance.Quality.RARE)
	_print_item(rare)
	assert(rare.quality == ItemInstance.Quality.RARE)
	assert(rare.affixes.size() >= 3 and rare.affixes.size() <= 4, "黄装应 3~4 词缀")

	print("\n=== 各槽位随机生成 (品质按权重) ===")
	for slot in [EquipSlots.Slot.HEAD, EquipSlots.Slot.BOOTS, EquipSlots.Slot.AMULET, EquipSlots.Slot.QUIVER]:
		_print_item(gen.generate(slot, 8))

	print("\n=== 指定传奇 ===")
	for lid in [&"windforce_boots", &"banshee_bow", &"focus_engine"]:
		_print_item(gen.generate_legendary(lid, 8))

	print("\n=== 词缀部位约束校验 (靴子不应出现暴击率/武器伤害) ===")
	var bad: int = 0
	for i in range(200):
		var it = gen.generate(EquipSlots.Slot.BOOTS, 8, ItemInstance.Quality.RARE)
		for a in it.affixes:
			var k: int = int(a["stat_kind"])
			if k == AffixDef.StatKind.WEAPON_DAMAGE or k == AffixDef.StatKind.CRIT_CHANCE:
				bad += 1
	print("  200 件靴子中非法词缀数 = ", bad, " (应为 0)")
	assert(bad == 0, "靴子出现了不该有的词缀")

	print("\n=== 品质权重抽样 (10000 次) ===")
	var counts := { ItemInstance.Quality.MAGIC: 0, ItemInstance.Quality.RARE: 0, ItemInstance.Quality.LEGENDARY: 0 }
	for i in range(10000):
		counts[gen.roll_quality()] += 1
	print("  蓝=%.1f%%  黄=%.1f%%  橙=%.1f%%  (期望 85 / 14.5 / 0.5)" % [
		counts[ItemInstance.Quality.MAGIC] / 100.0,
		counts[ItemInstance.Quality.RARE] / 100.0,
		counts[ItemInstance.Quality.LEGENDARY] / 100.0])

	print("\n=== 属性聚合 ===")
	var sample = gen.generate(EquipSlots.Slot.CHEST, 8, ItemInstance.Quality.RARE)
	_print_item(sample)
	print("  aggregate_stats = ", sample.aggregate_stats())

	print("\nVERIFY OK")
	quit()
