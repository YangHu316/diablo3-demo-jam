extends RefCounted
class_name ItemGenerator

# Item/affix generator (任务2). Produces ItemInstance from quality + slot + level
# by rolling affixes out of the DataTables pool.
# Source rules: 04-Demo装备与掉落 §3.1 (品质词缀数), §4 (词缀池), §5 (传奇).
#
# 用法:
#   var gen := ItemGenerator.new(DataTables)      # 传入 DataTables autoload
#   var item := gen.generate(EquipSlots.Slot.BOOTS, 7)            # 随机品质
#   var rare := gen.generate(EquipSlots.Slot.GLOVES, 5, ItemInstance.Quality.RARE)
#   var leg  := gen.generate_legendary(&"windforce_boots", 8)    # 指定传奇

# 品质 -> [最少词缀, 最多词缀] 条数. 传奇固定 4 条普通 + 1 橙字(不占位).
# 5 档 (扩展层): 普通 0~1 / 精良 1~2 / 稀有 3~4 / 史诗 4~5(保送1顶值) / 传说 4.
const AFFIX_COUNT := {
	ItemInstance.Quality.COMMON: [0, 1],
	ItemInstance.Quality.MAGIC: [1, 2],
	ItemInstance.Quality.RARE: [3, 4],
	ItemInstance.Quality.EPIC: [4, 5],
	ItemInstance.Quality.LEGENDARY: [4, 4],
}

# 普通掉落品质权重 (普通怪基准, drop_table.csv「缓行走尸」行: 55/33/10/1.5/0.5).
# 不含保底/精英特殊表; 精英/Boss/箱的 5 元权重在 drop_system.SOURCE_CONFIG.
const QUALITY_WEIGHTS := {
	ItemInstance.Quality.COMMON: 55.0,
	ItemInstance.Quality.MAGIC: 33.0,
	ItemInstance.Quality.RARE: 10.0,
	ItemInstance.Quality.EPIC: 1.5,
	ItemInstance.Quality.LEGENDARY: 0.5,
}

var _dt: Object = null          # DataTables autoload
var _rng: RandomNumberGenerator

# 程序化命名素材 (affix_naming.csv 镜像; 按 affix id 索引).
# 精良: 前缀+基底(+后缀若2词缀); 稀有: 两段稀有名素材+基底. 命名是表现层, 用 const 即可.
const NAMING := {
	&"agility":       {"prefix": "敏锐的", "suffix": "之力",   "rare": "鹰"},
	&"crit_chance":   {"prefix": "致命的", "suffix": "之精准", "rare": "蛇牙"},
	&"crit_damage":   {"prefix": "残酷的", "suffix": "之毁灭", "rare": "血"},
	&"attack_speed":  {"prefix": "迅捷的", "suffix": "之疾风", "rare": "风"},
	&"weapon_damage": {"prefix": "凶蛮的", "suffix": "之利刃", "rare": "獠牙"},
	&"skill_damage":  {"prefix": "奥能的", "suffix": "之奥义", "rare": "奥术"},
	&"vitality":      {"prefix": "坚韧的", "suffix": "之活力", "rare": "熊"},
	&"armor":         {"prefix": "铁壁的", "suffix": "之守护", "rare": "龟甲"},
	&"all_resist":    {"prefix": "抗御的", "suffix": "之屏障", "rare": "棱光"},
	&"move_speed":    {"prefix": "疾行的", "suffix": "之疾步", "rare": "豹"},
}

func _init(data_tables: Object, seed_value: int = -1) -> void:
	_dt = data_tables
	_rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

# 按权重随机一个品质.
func roll_quality() -> int:
	var total: float = 0.0
	for w in QUALITY_WEIGHTS.values():
		total += w
	var r: float = _rng.randf() * total
	var acc: float = 0.0
	for q in QUALITY_WEIGHTS:
		acc += QUALITY_WEIGHTS[q]
		if r <= acc:
			return q
	return ItemInstance.Quality.MAGIC

# 生成一件物品. quality < 0 时按权重随机.
func generate(slot: int, item_level: int, quality: int = -1) -> ItemInstance:
	if quality < 0:
		quality = roll_quality()
	if quality == ItemInstance.Quality.LEGENDARY:
		var leg_id: StringName = _pick_legendary_for_slot(slot)
		if leg_id != &"":
			return generate_legendary(leg_id, item_level)
		# 该槽位无对应传奇 -> 退化成稀有.
		quality = ItemInstance.Quality.RARE

	var item := ItemInstance.new()
	item.slot = slot
	item.item_level = item_level
	item.quality = quality
	item.tier = _tier_for(item_level)
	# 史诗: 从具名池抽一件, 保送其指定顶值词缀 (扩展层 §一); 其余正常 roll.
	if quality == ItemInstance.Quality.EPIC:
		var ep = _pick_epic_for_slot(slot)
		if ep != null:
			item.affixes = _roll_affixes(slot, item.tier, _count_for(quality), ep.guaranteed_affix_id)
			item.display_name = ep.display_name
			return item
		# 该槽位无对应史诗 -> 退化成保送该槽首条顶值的匿名史诗.
		item.affixes = _roll_affixes(slot, item.tier, _count_for(quality), &"__TOP__")
		item.display_name = _make_name(quality, slot, item.affixes, item.tier)
		return item
	item.affixes = _roll_affixes(slot, item.tier, _count_for(quality))
	item.display_name = _make_name(quality, slot, item.affixes, item.tier)
	return item

# 生成指定传奇 (4 条普通词缀 + 橙字特效).
func generate_legendary(legendary_id: StringName, item_level: int) -> ItemInstance:
	var ld = _dt.get_legendary(legendary_id)
	var item := ItemInstance.new()
	item.quality = ItemInstance.Quality.LEGENDARY
	item.item_level = item_level
	item.tier = _tier_for(item_level)
	if ld != null:
		item.slot = _slot_from_name(ld.slot)
		item.legendary_id = ld.id
		item.legendary_effect_text = ld.effect_text
		item.legendary_effect_id = ld.effect_id
		item.display_name = ld.display_name
	else:
		push_warning("ItemGenerator: unknown legendary %s" % legendary_id)
		item.display_name = "未知传奇"
	item.affixes = _roll_affixes(item.slot, item.tier, 4)
	return item

# ---------------------------------------------------------------------------
# internal
# ---------------------------------------------------------------------------

func _count_for(quality: int) -> int:
	var rng_pair = AFFIX_COUNT.get(quality, [1, 1])
	return _rng.randi_range(int(rng_pair[0]), int(rng_pair[1]))

func _tier_for(item_level: int) -> int:
	if _dt != null and _dt.tier_table != null:
		return _dt.tier_table.tier_for_level(item_level)
	return 1

# 从该槽位合法词缀池里, 不重复抽 count 条并 roll 数值.
# guaranteed_id: 史诗保送一条该词缀(取该 tier 顶值)并置于首位. &"__TOP__" = 保送该池第一条的顶值.
func _roll_affixes(slot: int, tier: int, count: int, guaranteed_id: StringName = &"") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var slot_name: StringName = _slot_name(slot)
	var pool: Array = _dt.get_affixes_for_slot(slot_name).duplicate()
	_shuffle(pool)
	# 史诗保送: 把指定词缀(或池首条)提到队首, 后续以顶值产出.
	var forced: Object = null
	if guaranteed_id == &"__TOP__":
		if not pool.is_empty():
			forced = pool[0]
	elif guaranteed_id != &"":
		for ad in pool:
			if ad.id == guaranteed_id:
				forced = ad
				break
	if forced != null:
		pool.erase(forced)
		pool.insert(0, forced)
	var picked: int = 0
	for ad in pool:
		if picked >= count:
			break
		var is_top: bool = (forced != null and picked == 0)
		var raw: float = (ad.max_value(tier) if is_top else ad.roll_value(tier, _rng))
		# 百分比保留 1 位小数, 绝对值取整.
		var value: float = (round(raw * 10.0) / 10.0) if ad.is_percent else float(round(raw))
		out.append({
			"affix_id": ad.id,
			"stat_kind": ad.stat_kind,
			"value": value,
			"is_percent": ad.is_percent,
			"display_name": ad.display_name,
		})
		picked += 1
	return out

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp

func _pick_legendary_for_slot(slot: int) -> StringName:
	var slot_name: StringName = _slot_name(slot)
	var matches: Array = []
	for ld in _dt.get_all_legendaries():
		if ld.slot == slot_name:
			matches.append(ld.id)
	if matches.is_empty():
		return &""
	return matches[_rng.randi_range(0, matches.size() - 1)]

# 该槽位随机一件史诗具名件 (无则 null).
func _pick_epic_for_slot(slot: int) -> Object:
	var slot_name: StringName = _slot_name(slot)
	var matches: Array = _dt.get_epics_for_slot(slot_name)
	if matches.is_empty():
		return null
	return matches[_rng.randi_range(0, matches.size() - 1)]

func _slot_name(slot: int) -> StringName:
	return EquipSlots.SLOT_NAMES.get(slot, &"")

# 槽名 -> Slot 枚举 (戒指有两槽, 默认归 RING_1).
func _slot_from_name(slot_name: StringName) -> int:
	for s in EquipSlots.SLOT_NAMES:
		if EquipSlots.SLOT_NAMES[s] == slot_name:
			return s
	return EquipSlots.Slot.HEAD

func _make_name(quality: int, slot: int, affixes: Array[Dictionary], tier: int) -> String:
	var slot_name: StringName = _slot_name(slot)
	var base: String = _dt.get_base_name(slot_name, tier)
	if base == "":
		base = EquipSlots.SLOT_DISPLAY.get(slot, "装备")
	match quality:
		ItemInstance.Quality.COMMON:
			# 普通: 基底名.
			return base
		ItemInstance.Quality.MAGIC:
			# 精良: 前缀+基底 (+后缀若 ≥2 词缀).
			if affixes.is_empty():
				return base
			var p: String = _naming_of(affixes[0]).get("prefix", "")
			var name: String = p + base
			if affixes.size() >= 2:
				name += " " + _naming_of(affixes[1]).get("suffix", "")
			return name
		ItemInstance.Quality.RARE:
			# 稀有: 生成式两段名 + 基底类型 (取前两条词缀的稀有名素材).
			var seg1: String = _naming_of(affixes[0]).get("rare", "") if affixes.size() >= 1 else ""
			var seg2: String = _naming_of(affixes[1]).get("rare", "") if affixes.size() >= 2 else ""
			var two: String = seg1
			if seg2 != "":
				two += "·" + seg2
			return ("%s %s" % [two, base]) if two != "" else base
		_:
			# 史诗/传说 走具名, 不应到此; 兜底用基底名.
			return base

# 取某条已 roll 词缀的命名素材 dict (无则空 dict).
func _naming_of(affix: Dictionary) -> Dictionary:
	return NAMING.get(affix.get("affix_id", &""), {})
