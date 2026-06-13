extends SceneTree

# One-shot tool: builds all data/*.tres from authoritative 策划案 numbers.
# Run headless:  godot --headless --path . --script res://tools/gen_data_tables.gd
# Safe to re-run; overwrites the .tres files.

func _make_affix(id: StringName, name: String, cat: int, kind: int, pct: bool,
		t1mn: float, t1mx: float, t3mn: float, t3mx: float,
		slots: Array, max_per: int = 99) -> AffixDef:
	var a := AffixDef.new()
	a.id = id
	a.display_name = name
	a.category = cat
	a.stat_kind = kind
	a.is_percent = pct
	a.t1_min = t1mn
	a.t1_max = t1mx
	a.t3_min = t3mn
	a.t3_max = t3mx
	a.max_per_item = max_per
	var typed: Array[StringName] = []
	for s in slots:
		typed.append(StringName(s))
	a.allowed_slots = typed
	return a

func _build_affixes() -> AffixTable:
	var C_ATK := AffixDef.Category.ATTACK
	var C_DEF := AffixDef.Category.DEFENSE
	var C_UTL := AffixDef.Category.UTILITY
	var K := AffixDef.StatKind
	var t := AffixTable.new()
	var list: Array[AffixDef] = [
		# id, name, category, stat_kind, is_percent, t1min,t1max, t3min,t3max, slots
		_make_affix(&"agility", "敏捷", C_ATK, K.AGILITY, false, 2, 4, 10, 18, []),
		_make_affix(&"crit_chance", "暴击率", C_ATK, K.CRIT_CHANCE, true, 1, 2, 3, 6, ["gloves","ring","amulet","head"]),
		_make_affix(&"crit_damage", "暴击伤害", C_ATK, K.CRIT_DAMAGE, true, 10, 15, 25, 50, ["amulet","gloves","ring"]),
		_make_affix(&"attack_speed", "攻击速度", C_ATK, K.ATTACK_SPEED, true, 3, 4, 5, 7, ["bow","gloves","ring"]),
		_make_affix(&"weapon_damage", "武器伤害", C_ATK, K.WEAPON_DAMAGE, false, 1, 2, 4, 9, ["bow"]),
		_make_affix(&"skill_damage", "技能伤害", C_ATK, K.SKILL_DAMAGE, true, 5, 8, 10, 20, ["head","chest","boots","quiver"]),
		_make_affix(&"vitality", "体能", C_DEF, K.VITALITY, false, 2, 4, 10, 18, []),
		_make_affix(&"armor", "护甲", C_DEF, K.ARMOR, false, 4, 8, 15, 30, ["head","shoulder","chest","wrist","gloves","waist","legs","boots"]),
		_make_affix(&"all_resist", "全抗性", C_DEF, K.ALL_RESIST, false, 2, 3, 6, 12, ["head","shoulder","chest","wrist","gloves","waist","legs","boots","amulet","ring"]),
		_make_affix(&"move_speed", "移动速度", C_UTL, K.MOVE_SPEED, true, 4, 6, 8, 12, ["boots"], 1),
	]
	t.affixes = list
	return t

func _make_leg(id: StringName, name: String, slot: String, eff_id: StringName, eff: String, whitelist: bool) -> LegendaryDef:
	var l := LegendaryDef.new()
	l.id = id
	l.display_name = name
	l.slot = StringName(slot)
	l.effect_id = eff_id
	l.effect_text = eff
	l.is_first_orange_whitelist = whitelist
	return l

func _build_legendaries() -> LegendaryTable:
	var t := LegendaryTable.new()
	var list: Array[LegendaryDef] = [
		_make_leg(&"banshee_bow", "女妖之弓", "bow", &"multishot_plus2",
			"多重射击额外 +2 投射物", true),
		_make_leg(&"frost_quiver", "冰霜之箭袋", "quiver", &"frozen_take_30",
			"冰冻/冻缓状态目标受到的伤害 +30%", true),
		_make_leg(&"windforce_boots", "疾风之靴", "boots", &"roll_no_cd_decoy",
			"翻滚回避无 CD(改为消耗 25 专注);翻滚留下诱饵", true),
		_make_leg(&"valkyrie_crown", "女武神之冠", "head", &"valkyrie_plus1",
			"女武神召唤数 +1, 持续时间 +50%", false),
		_make_leg(&"focus_engine", "专注引擎", "amulet", &"crit_restore_focus",
			"暴击回 6 专注", false),
	]
	t.legendaries = list
	return t

func _make_monster(id: StringName, name: String, bh: float, ba: float, bx: float,
		hmul: float, amul: float, boss: bool, gold_mul: float) -> MonsterDef:
	var m := MonsterDef.new()
	m.id = id
	m.display_name = name
	m.base_health = bh
	m.base_attack = ba
	m.base_xp = bx
	m.health_growth = 1.31
	m.attack_growth = 1.17
	m.xp_growth = 1.45
	m.level_cap = 8
	m.health_mult = hmul
	m.attack_mult = amul
	m.is_boss = boss
	m.gold_per_kill_mult = gold_mul
	return m

func _build_monsters() -> MonsterTable:
	var t := MonsterTable.new()
	var list: Array[MonsterDef] = [
		_make_monster(&"trash", "普通怪", 40, 15, 8, 1.0, 1.0, false, 1.0),
		_make_monster(&"elite_blue", "蓝名精英", 40, 15, 8, 2.5, 1.3, false, 8.0),
		_make_monster(&"champion_yellow", "黄名首领", 40, 15, 8, 5.0, 1.4, false, 8.0),
		# 屠夫: 生命≈11000 (≈白怪L7 265*pow(1.31,6)≈ * 倍率). 用 health_mult 近似锚定.
		_make_monster(&"butcher", "屠夫", 40, 15, 8, 41.5, 5.0, true, 0.0),
	]
	t.monsters = list
	return t

func _build_xp_curve() -> XPCurve:
	var x := XPCurve.new()
	x.max_level = 8
	x.xp_to_next = PackedInt32Array([300, 480, 768, 1229, 1966, 3146, 5033])
	x.agility_per_level = 6
	x.vitality_per_level = 4
	x.base_agility = 10
	x.base_vitality = 10
	x.hp_base = 40
	x.hp_per_level = 10
	x.hp_per_vitality = 10
	x.unlocks = {
		1: ["slot_1", "skill_puncture"],
		2: ["slot_2", "skill_multishot"],
		3: ["slot_3", "skill_frost_arrow"],
		4: ["slot_4", "skill_roll", "rune_system", "tier2_weapon"],
		5: ["slot_5", "skill_valkyrie", "passive_slot_1"],
		6: ["rune_batch_2", "passive_pool"],
		7: ["passive_slot_2", "rune_batch_3"],
		8: ["rune_ultimate", "passive_ultimate"],
	}
	return x

func _build_tier_table() -> TierTable:
	var t := TierTable.new()
	t.tiers = [
		{ "tier": 1, "level_min": 1, "level_max": 3, "weapon_dps_min": 3.0,  "weapon_dps_max": 8.0,  "armor_min": 6,  "armor_max": 14 },
		{ "tier": 2, "level_min": 4, "level_max": 6, "weapon_dps_min": 9.0,  "weapon_dps_max": 18.0, "armor_min": 16, "armor_max": 32 },
		{ "tier": 3, "level_min": 7, "level_max": 8, "weapon_dps_min": 20.0, "weapon_dps_max": 32.0, "armor_min": 36, "armor_max": 70 },
	]
	return t

func _save(res: Resource, path: String) -> void:
	var err: int = ResourceSaver.save(res, path)
	if err == OK:
		print("  saved ", path)
	else:
		printerr("  FAILED ", path, " err=", err)

func _init() -> void:
	print("Generating data tables...")
	_save(_build_affixes(), "res://data/affixes.tres")
	_save(_build_legendaries(), "res://data/legendaries.tres")
	_save(_build_monsters(), "res://data/monsters.tres")
	_save(_build_xp_curve(), "res://data/xp_curve.tres")
	_save(_build_tier_table(), "res://data/tier_table.tres")
	print("Done.")
	quit()
