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
const AFFIX_COUNT := {
	ItemInstance.Quality.MAGIC: [1, 2],
	ItemInstance.Quality.RARE: [3, 4],
	ItemInstance.Quality.LEGENDARY: [4, 4],
}

# 普通掉落品质权重 (普通怪基准, 04-Demo §3.1). 不含保底/精英特殊表.
const QUALITY_WEIGHTS := {
	ItemInstance.Quality.MAGIC: 85.0,
	ItemInstance.Quality.RARE: 14.5,
	ItemInstance.Quality.LEGENDARY: 0.5,
}

var _dt: Object = null          # DataTables autoload
var _rng: RandomNumberGenerator

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
	item.affixes = _roll_affixes(slot, item.tier, _count_for(quality))
	item.display_name = _make_name(quality, slot)
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
func _roll_affixes(slot: int, tier: int, count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var slot_name: StringName = _slot_name(slot)
	var pool: Array = _dt.get_affixes_for_slot(slot_name).duplicate()
	# 洗牌后顺序取, 保证不重复词缀类型.
	_shuffle(pool)
	var picked: int = 0
	for ad in pool:
		if picked >= count:
			break
		var raw: float = ad.roll_value(tier, _rng)
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

func _slot_name(slot: int) -> StringName:
	return EquipSlots.SLOT_NAMES.get(slot, &"")

# 槽名 -> Slot 枚举 (戒指有两槽, 默认归 RING_1).
func _slot_from_name(slot_name: StringName) -> int:
	for s in EquipSlots.SLOT_NAMES:
		if EquipSlots.SLOT_NAMES[s] == slot_name:
			return s
	return EquipSlots.Slot.HEAD

func _make_name(quality: int, slot: int) -> String:
	var q: String = ItemInstance.QUALITY_NAMES.get(quality, "")
	var s: String = EquipSlots.SLOT_DISPLAY.get(slot, "装备")
	return "%s %s" % [q, s]
