extends SceneTree
# verify_fixed_panel.gd — 校验 P1-1 装备面板写死中期档:
#   ① player_loadout.csv 被解析 (敏捷=150)
#   ② get_fixed_panel_stats() 含 10 个 StatKind 键
#   ③ 关键数值取自 loadout (敏捷150/暴击45/暴伤400/攻速1.5/武器24/生命1200)
#   ④ 固定面板与"穿装聚合"解耦: 多次调用恒定 (换装不改数值)

func _init() -> void:
	var ok := 0
	var tot := 0
	# 直接实例化 DataTables 并触发加载, 避免依赖 autoload 树时序.
	var dt_script := load("res://scripts/autoload/data_tables.gd")
	var dt: Node = dt_script.new()
	dt.call("_load_all")

	# ① loadout 解析
	tot += 1
	var agi_raw: String = dt.get_loadout_value("敏捷")
	if agi_raw == "150":
		ok += 1; print("OK① loadout 解析 敏捷=%s" % agi_raw)
	else:
		printerr("FAIL① 敏捷 期望150 实得'%s'" % agi_raw)

	# ② 10 个 StatKind 键
	tot += 1
	var stats: Dictionary = dt.get_fixed_panel_stats()
	if stats.size() == 10:
		ok += 1; print("OK② 固定面板 %d 个属性" % stats.size())
	else:
		printerr("FAIL② 期望10 实得%d" % stats.size())

	# ③ 关键数值取自 loadout
	tot += 1
	var exp := {
		AffixDef.StatKind.AGILITY: 150.0,
		AffixDef.StatKind.CRIT_CHANCE: 45.0,
		AffixDef.StatKind.CRIT_DAMAGE: 400.0,
		AffixDef.StatKind.ATTACK_SPEED: 1.5,
		AffixDef.StatKind.WEAPON_DAMAGE: 24.0,
		AffixDef.StatKind.VITALITY: 1200.0,
	}
	var bad := ""
	for k in exp:
		if absf(float(stats.get(k, -999.0)) - float(exp[k])) > 0.01:
			bad += "[%d:期望%.1f得%.1f]" % [k, float(exp[k]), float(stats.get(k, -999.0))]
	if bad == "":
		ok += 1; print("OK③ 关键数值全部对齐 loadout")
	else:
		printerr("FAIL③ 数值不符 %s" % bad)

	# ④ 换装不改: 多次取值恒定 (固定源, 与 Inventory 装备状态无关)
	tot += 1
	var s2: Dictionary = dt.get_fixed_panel_stats()
	var stable := true
	for k in stats:
		if absf(float(stats[k]) - float(s2.get(k, -999.0))) > 0.0001:
			stable = false
	if stable:
		ok += 1; print("OK④ 固定面板数值恒定 (换装不改)")
	else:
		printerr("FAIL④ 两次取值不一致")

	print("==== verify_fixed_panel: %d/%d 判定通过 ====" % [ok, tot])
	dt.free()
	quit(0 if ok == tot else 1)
