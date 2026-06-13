extends SceneTree

# Verify DropSystem + Inventory (任务3). Run headless:
#   godot --headless --path . --script res://tools/verify_drop_system.gd < /dev/null
#
# DropSystem 是 RefCounted 纯逻辑, 直接 new; Inventory 是 autoload 脚本, 手动实例化.

func _qname(q: int) -> String:
	return ItemInstance.QUALITY_NAMES.get(q, "?")

func _init() -> void:
	var DataTablesScript = load("res://scripts/autoload/data_tables.gd")
	var dt = DataTablesScript.new()
	dt._load_all()
	print("DataTables loaded = ", dt.is_loaded)

	var gen = ItemGenerator.new(dt, 999)
	# DropSystem 的 class_name 尚未进全局类缓存(headless --script 不刷新缓存),
	# 显式 load 脚本资源, 通过资源访问其 enum/const/new (与 DataTables/Inventory 同法).
	var DropSystemScript = load("res://scripts/systems/drop_system.gd")
	var ds = DropSystemScript.new(dt, gen, 999)   # 固定种子可复现

	# === 完成判定①: 普通怪掉落率 ~18% ===
	print("\n=== 判定①: 普通怪(TRASH)掉落率 (期望 ~18%) ===")
	var drops: int = 0
	var trials: int = 5000
	for i in range(trials):
		var r: Array = ds.roll_drop(DropSystemScript.Source.TRASH, 1)
		if not r.is_empty():
			drops += 1
	var rate: float = float(drops) / float(trials) * 100.0
	print("  掉落率 = %.1f%% (%d/%d)" % [rate, drops, trials])
	assert(rate > 13.0 and rate < 23.0, "TRASH 掉落率应接近 18%%")

	# === 完成判定②: 精英 100% 掉落 + 5 档品质分布 ===
	print("\n=== 判定②: 蓝名精英(ELITE_BLUE) 100% 掉落, 5 档品质分布 ===")
	var ds2 = DropSystemScript.new(dt, gen, 42)
	var qcount := { 0: 0, 1: 0, 2: 0, 3: 0, 4: 0 }
	var total_items: int = 0
	for i in range(3000):
		var r: Array = ds2.roll_drop(DropSystemScript.Source.ELITE_BLUE, 5)
		# 精英每次必产出 (drop_rate=1.0).
		assert(not r.is_empty(), "精英应 100%% 掉落")
		for it in r:
			qcount[it.quality] += 1
			total_items += 1
		# 重置保底状态, 避免 pity_stack/leg 干扰纯权重观测.
		ds2.pity_stack = 0
		ds2.leg_count = 99   # 跳过传奇定向逻辑干扰(允许重复)
		ds2._dropped_legendaries.clear()
	print("  共 %d 件: 白=%.0f%% 蓝=%.0f%% 黄=%.0f%% 紫=%.0f%% 橙=%.0f%% (期望 ~10/48/33/6/3)" % [
		total_items,
		qcount[0] * 100.0 / total_items,
		qcount[1] * 100.0 / total_items,
		qcount[2] * 100.0 / total_items,
		qcount[3] * 100.0 / total_items,
		qcount[4] * 100.0 / total_items])
	# ELITE_BLUE 权重 [白10,蓝48,黄33,紫6,橙3]: 蓝>黄>白>紫>橙.
	assert(qcount[1] > qcount[2], "蓝应多于黄")
	assert(qcount[2] > qcount[0], "黄应多于白")
	assert(qcount[0] > qcount[3] and qcount[3] > qcount[4], "白>紫>橙")

	# === 完成判定③: 首橙白名单 ===
	print("\n=== 判定③: 首件传奇必∈白名单(女妖弓/冰霜箭袋/疾风靴) ===")
	var wl: Array = DropSystemScript.FIRST_ORANGE_WHITELIST
	var checked: int = 0
	for trial in range(200):
		var d3 = DropSystemScript.new(dt, gen, trial)
		# 触发硬保底首橙: leg_count=0 + pity_timer≥8min + 保底载体.
		d3.tick(500.0)
		var first_leg: ItemInstance = null
		while first_leg == null:
			var r: Array = d3.roll_drop(DropSystemScript.Source.ELITE_BLUE, 8)
			for it in r:
				if it.is_legendary():
					first_leg = it
					break
		assert(wl.has(first_leg.legendary_id), "首橙 %s 不在白名单" % first_leg.legendary_id)
		checked += 1
	print("  %d 局首橙全部命中白名单 ✓" % checked)

	# === 完成判定④: 硬保底(leg=0 且 pity≥8min 的保底载体强制橙) ===
	print("\n=== 判定④: 硬保底首橙 ===")
	var d4 = DropSystemScript.new(dt, gen, 7)
	d4.tick(481.0)   # 超 8 分钟
	var r4: Array = d4.roll_drop(DropSystemScript.Source.ELITE_BLUE, 8)
	var has_orange: bool = false
	for it in r4:
		if it.is_legendary():
			has_orange = true
	print("  pity_timer=481s + 精英载体 -> 首件含橙 = ", has_orange)
	assert(has_orange, "硬保底应强制首橙")
	assert(d4.leg_count == 1, "掉橙后 leg_count 应=1")
	assert(d4.pity_timer == 0.0, "掉橙后 pity_timer 应清零")

	# === 完成判定⑤: 前4件传奇查重不重复 ===
	# 注: BUTCHER 单次最多产 4 件, 越过第4件后系统按 §7.2 允许重复(正确行为),
	# 故只校验"前4件传奇互不重复", 收满 4 件即停.
	print("\n=== 判定⑤: 前4件传奇查重 ===")
	var d5 = DropSystemScript.new(dt, gen, 3)
	var seen: Array = []
	var guard: int = 0
	while seen.size() < 4 and guard < 100000:
		d5.tick(500.0)   # 持续喂硬保底以快速凑齐传奇
		var r5: Array = d5.roll_drop(DropSystemScript.Source.BUTCHER, 8)
		for it in r5:
			if it.is_legendary() and seen.size() < 4:
				assert(not seen.has(it.legendary_id), "前4件出现重复传奇 %s" % it.legendary_id)
				seen.append(it.legendary_id)
		guard += 1
	print("  前4件传奇 = ", seen, " (无重复 ✓)")
	assert(seen.size() == 4)

	# === 完成判定⑥: 入包 + 满包返回 false ===
	print("\n=== 判定⑥: Inventory 入包 / 满包 ===")
	var InvScript = load("res://scripts/autoload/inventory.gd")
	var inv = InvScript.new()
	var ok_count: int = 0
	for i in range(inv.BAG_CAPACITY + 5):
		var item := gen.generate(EquipSlots.Slot.GLOVES, 5, ItemInstance.Quality.MAGIC)
		if inv.add_item(item):
			ok_count += 1
	print("  入包成功 %d 件 (容量 %d), 溢出被拒" % [ok_count, inv.BAG_CAPACITY])
	assert(ok_count == inv.BAG_CAPACITY, "应正好装满 %d 件" % inv.BAG_CAPACITY)
	assert(inv.is_full(), "应已满包")
	assert(not inv.add_item(gen.generate(EquipSlots.Slot.BOW, 5)), "满包应返回 false")

	print("\nVERIFY OK")
	quit()
