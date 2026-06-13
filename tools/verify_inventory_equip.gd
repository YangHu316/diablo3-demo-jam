extends SceneTree

# 任务4 验证: 背包(40格) + 装备(13槽) + 属性聚合生效.
# 覆盖: 满包溢出 / 装备-卸下信号 / 基础属性+词缀聚合 / 换装替换 / 戒指双槽 / quick_equip 自动选槽.
# Run headless:
#   godot --headless --path . --script res://tools/verify_inventory_equip.gd

var _fail := 0

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  - ", msg)
	else:
		_fail += 1
		print("  FAIL- ", msg)

# 最小 ProgressionManager 替身 (Inventory.get_total_stats 只读 agility/vitality).
class FakeProg:
	extends Node
	var agility: int = 50
	var vitality: int = 30

# 造一件带词缀的物品.
func _make_item(name: String, slot: int, stat_kind: int, value: float, q: int = 0) -> ItemInstance:
	var it := ItemInstance.new()
	it.display_name = name
	it.slot = slot
	it.quality = q
	var affs: Array[Dictionary] = []
	affs.append({
		"stat_kind": stat_kind,
		"value": value,
		"is_percent": false,
		"affix_id": &"test"
	})
	it.affixes = affs
	return it

func _init() -> void:
	var Inv = load("res://scripts/autoload/inventory.gd")
	var inv = Inv.new()
	var prog := FakeProg.new()
	inv._progression = prog   # 依赖注入, 绕过 autoload

	# --- 信号捕获 ---
	var equipped_events: Array = []
	var unequipped_events: Array = []
	var stats_events: Array = []
	inv.item_equipped.connect(func(s, i): equipped_events.append([s, i]))
	inv.item_unequipped.connect(func(s, i): unequipped_events.append([s, i]))
	inv.stats_changed.connect(func(st): stats_events.append(st))

	# =====================================================================
	print("\n=== 判定①: 背包 40 格 + 溢出 ===")
	for i in range(40):
		inv.add_item(_make_item("trash_%d" % i, EquipSlots.Slot.HEAD, AffixDef.StatKind.ARMOR, 1.0))
	_ck(inv.bag_count() == 40, "装满 40 格 (bag_count=%d)" % inv.bag_count())
	_ck(inv.is_full(), "is_full() == true")
	var overflow: bool = inv.add_item(_make_item("overflow", EquipSlots.Slot.HEAD, AffixDef.StatKind.ARMOR, 1.0))
	_ck(overflow == false, "第 41 件被拒 (满包返回 false)")
	_ck(inv.bag_count() == 40, "溢出后仍为 40 格")
	_ck(inv.add_item(null) == false, "add_item(null) 返回 false")

	# 清空重来 (新 inv).
	inv = Inv.new()
	inv._progression = prog
	equipped_events.clear(); unequipped_events.clear(); stats_events.clear()
	inv.item_equipped.connect(func(s, i): equipped_events.append([s, i]))
	inv.item_unequipped.connect(func(s, i): unequipped_events.append([s, i]))
	inv.stats_changed.connect(func(st): stats_events.append(st))

	# =====================================================================
	print("\n=== 判定②: 装备 / 卸下 + 信号 ===")
	var helm := _make_item("敏捷头盔", EquipSlots.Slot.HEAD, AffixDef.StatKind.AGILITY, 12.0)
	inv.add_item(helm)
	_ck(inv.bag_count() == 1, "入包后 bag=1")
	var ok: bool = inv.equip(EquipSlots.Slot.HEAD, helm)
	_ck(ok, "equip(HEAD, helm) 成功")
	_ck(inv.get_equipped(EquipSlots.Slot.HEAD) == helm, "HEAD 槽 == helm")
	_ck(inv.bag_count() == 0, "装备后从背包移除 (bag=0)")
	_ck(equipped_events.size() == 1, "item_equipped 触发 1 次")
	_ck(stats_events.size() >= 1, "stats_changed 已触发")

	var back: ItemInstance = inv.unequip(EquipSlots.Slot.HEAD)
	_ck(back == helm, "unequip 返回 helm")
	_ck(inv.get_equipped(EquipSlots.Slot.HEAD) == null, "卸下后 HEAD 空")
	_ck(inv.bag_count() == 1, "卸下后回背包 (bag=1)")
	_ck(unequipped_events.size() == 1, "item_unequipped 触发 1 次")
	_ck(inv.equip(99, helm) == false, "非法槽位 99 被拒")

	# =====================================================================
	print("\n=== 判定③: 属性聚合 (基础 + 词缀) ===")
	# helm 在背包, 先装上. 基础: agility=50, vitality=30.
	inv.equip(EquipSlots.Slot.HEAD, helm)   # +12 敏捷
	var chest := _make_item("体能胸甲", EquipSlots.Slot.CHEST, AffixDef.StatKind.VITALITY, 8.0)
	inv.add_item(chest)
	inv.equip(EquipSlots.Slot.CHEST, chest) # +8 体能
	var st: Dictionary = inv.get_total_stats()
	_ck(int(st.get(AffixDef.StatKind.AGILITY, 0)) == 62, "敏捷 = 50(基础)+12(头) = 62 (实=%d)" % int(st.get(AffixDef.StatKind.AGILITY, 0)))
	_ck(int(st.get(AffixDef.StatKind.VITALITY, 0)) == 38, "体能 = 30(基础)+8(胸) = 38 (实=%d)" % int(st.get(AffixDef.StatKind.VITALITY, 0)))

	# =====================================================================
	print("\n=== 判定④: 换装替换 (净占用不变) ===")
	var helm2 := _make_item("敏捷头盔V2", EquipSlots.Slot.HEAD, AffixDef.StatKind.AGILITY, 20.0)
	inv.add_item(helm2)
	var bag_before: int = inv.bag_count()
	inv.equip(EquipSlots.Slot.HEAD, helm2)  # 旧 helm 回包, 新 helm2 出包 -> 净占用不变
	_ck(inv.get_equipped(EquipSlots.Slot.HEAD) == helm2, "HEAD 换成 helm2")
	_ck(inv.bag_count() == bag_before, "换装后净占用不变 (bag=%d)" % inv.bag_count())
	_ck(inv.get_bag_items().has(helm), "旧 helm 回到背包")
	var st2: Dictionary = inv.get_total_stats()
	_ck(int(st2.get(AffixDef.StatKind.AGILITY, 0)) == 70, "换装后敏捷 = 50+20 = 70 (实=%d)" % int(st2.get(AffixDef.StatKind.AGILITY, 0)))

	# =====================================================================
	print("\n=== 判定⑤: 戒指双槽 + quick_equip 自动选槽 ===")
	var inv2 = Inv.new()
	inv2._progression = prog
	var ring_a := _make_item("戒指A", EquipSlots.Slot.RING_1, AffixDef.StatKind.CRIT_CHANCE, 5.0)
	var ring_b := _make_item("戒指B", EquipSlots.Slot.RING_1, AffixDef.StatKind.CRIT_CHANCE, 7.0)
	inv2.add_item(ring_a); inv2.add_item(ring_b)
	var s1: int = inv2.quick_equip(ring_a)
	var s2: int = inv2.quick_equip(ring_b)
	_ck(s1 == EquipSlots.Slot.RING_1, "第一枚戒指 -> RING_1 (slot=%d)" % s1)
	_ck(s2 == EquipSlots.Slot.RING_2, "第二枚戒指自动 -> RING_2 (slot=%d)" % s2)
	_ck(inv2.get_equipped(EquipSlots.Slot.RING_1) == ring_a and inv2.get_equipped(EquipSlots.Slot.RING_2) == ring_b,
		"两戒分别落入 RING_1 / RING_2")

	# =====================================================================
	print("\n========================================")
	if _fail == 0:
		print("VERIFY OK - 背包+装备+属性聚合全部通过")
	else:
		print("VERIFY FAIL - %d 项未通过" % _fail)
	quit()
