extends Node

# DataTables (Autoload): central data registry. Loads all .tres tables at startup
# and exposes typed query APIs. This is the dependency 战斗① is waiting on.
#
# Hour-0 contract — query API stays stable; underlying .tres can be swapped when
# 关卡C finalizes numbers (Day1 上午先用占位/初版数值).

const AFFIX_TABLE_PATH: String = "res://data/affixes.tres"
const BASE_ITEM_TABLE_PATH: String = "res://data/base_items.tres"
const EPIC_ITEM_TABLE_PATH: String = "res://data/epic_items.tres"
const LEGENDARY_TABLE_PATH: String = "res://data/legendaries.tres"
const MONSTER_TABLE_PATH: String = "res://data/monsters.tres"
const XP_CURVE_PATH: String = "res://data/xp_curve.tres"
const TIER_TABLE_PATH: String = "res://data/tier_table.tres"

var _affixes: Array[AffixDef] = []
var _affix_by_id: Dictionary = {}            # StringName -> AffixDef
var _affixes_by_slot: Dictionary = {}        # slot StringName -> Array[AffixDef]

var _base_items: Array[ItemBaseDef] = []
var _base_by_slot: Dictionary = {}           # slot StringName -> ItemBaseDef

var _epics: Array[EpicItemDef] = []
var _epic_by_id: Dictionary = {}             # StringName -> EpicItemDef
var _epics_by_slot: Dictionary = {}          # slot StringName -> Array[EpicItemDef]

var _legendaries: Array[LegendaryDef] = []
var _legendary_by_id: Dictionary = {}

var _monsters: Array[MonsterDef] = []
var _monster_by_id: Dictionary = {}

var xp_curve: XPCurve = null
var tier_table: TierTable = null

var is_loaded: bool = false

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_load_affixes()
	_load_base_items()
	_load_epics()
	_load_legendaries()
	_load_monsters()
	xp_curve = _load_res(XP_CURVE_PATH) as XPCurve
	tier_table = _load_res(TIER_TABLE_PATH) as TierTable
	is_loaded = true

func _load_res(path: String) -> Resource:
	if not ResourceLoader.exists(path):
		push_warning("DataTables: missing resource %s" % path)
		return null
	return ResourceLoader.load(path)

func _load_affixes() -> void:
	_affixes.clear()
	_affix_by_id.clear()
	_affixes_by_slot.clear()
	var pack: Resource = _load_res(AFFIX_TABLE_PATH)
	if pack == null or not (&"affixes" in pack):
		return
	for a in pack.get(&"affixes"):
		var ad: AffixDef = a as AffixDef
		if ad == null:
			continue
		_affixes.append(ad)
		_affix_by_id[ad.id] = ad

func _load_base_items() -> void:
	_base_items.clear()
	_base_by_slot.clear()
	var pack: Resource = _load_res(BASE_ITEM_TABLE_PATH)
	if pack == null or not (&"base_items" in pack):
		return
	for b in pack.get(&"base_items"):
		var bd: ItemBaseDef = b as ItemBaseDef
		if bd == null:
			continue
		_base_items.append(bd)
		_base_by_slot[bd.slot] = bd

func _load_epics() -> void:
	_epics.clear()
	_epic_by_id.clear()
	_epics_by_slot.clear()
	var pack: Resource = _load_res(EPIC_ITEM_TABLE_PATH)
	if pack == null or not (&"epics" in pack):
		return
	for e in pack.get(&"epics"):
		var ed: EpicItemDef = e as EpicItemDef
		if ed == null:
			continue
		_epics.append(ed)
		_epic_by_id[ed.id] = ed
		if not _epics_by_slot.has(ed.slot):
			_epics_by_slot[ed.slot] = []
		_epics_by_slot[ed.slot].append(ed)

func _load_legendaries() -> void:
	_legendaries.clear()
	_legendary_by_id.clear()
	var pack: Resource = _load_res(LEGENDARY_TABLE_PATH)
	if pack == null or not (&"legendaries" in pack):
		return
	for l in pack.get(&"legendaries"):
		var ld: LegendaryDef = l as LegendaryDef
		if ld == null:
			continue
		_legendaries.append(ld)
		_legendary_by_id[ld.id] = ld

func _load_monsters() -> void:
	_monsters.clear()
	_monster_by_id.clear()
	var pack: Resource = _load_res(MONSTER_TABLE_PATH)
	if pack == null or not (&"monsters" in pack):
		return
	for m in pack.get(&"monsters"):
		var md: MonsterDef = m as MonsterDef
		if md == null:
			continue
		_monsters.append(md)
		_monster_by_id[md.id] = md

# ---------------------------------------------------------------------------
# Query API (对外稳定接口)
# ---------------------------------------------------------------------------

func get_all_affixes() -> Array[AffixDef]:
	return _affixes

func get_affix(id: StringName) -> AffixDef:
	return _affix_by_id.get(id, null)

# 某装备槽可出现的词缀 (allowed_slots 为空表示全部位).
func get_affixes_for_slot(slot_name: StringName) -> Array[AffixDef]:
	var out: Array[AffixDef] = []
	for ad in _affixes:
		if ad.allowed_slots.is_empty() or ad.allowed_slots.has(slot_name):
			out.append(ad)
	return out

# ---- 基底装备 (base_items.tres) ----
func get_all_base_items() -> Array[ItemBaseDef]:
	return _base_items

# 某槽位的基底 (戒指两槽共用 "ring").
func get_base_item(slot_name: StringName) -> ItemBaseDef:
	return _base_by_slot.get(slot_name, null)

# 某槽位在指定 tier 的基底名 (短弓/猎弓/战弓); 无则空串.
func get_base_name(slot_name: StringName, tier: int) -> String:
	var bd: ItemBaseDef = get_base_item(slot_name)
	return bd.name_for_tier(tier) if bd != null else ""

# ---- 史诗具名件 (epic_items.tres) ----
func get_all_epics() -> Array[EpicItemDef]:
	return _epics

func get_epic(id: StringName) -> EpicItemDef:
	return _epic_by_id.get(id, null)

func get_epics_for_slot(slot_name: StringName) -> Array[EpicItemDef]:
	var out: Array[EpicItemDef] = []
	for ed in _epics_by_slot.get(slot_name, []):
		out.append(ed)
	return out

func get_legendary(id: StringName) -> LegendaryDef:
	return _legendary_by_id.get(id, null)

func get_all_legendaries() -> Array[LegendaryDef]:
	return _legendaries

func get_first_orange_whitelist() -> Array[LegendaryDef]:
	var out: Array[LegendaryDef] = []
	for ld in _legendaries:
		if ld.is_first_orange_whitelist:
			out.append(ld)
	return out

func get_monster(id: StringName) -> MonsterDef:
	return _monster_by_id.get(id, null)

# 怪物在指定等级的结算数值. 返回 { health, attack, xp }.
func get_monster_stats(id: StringName, level: int) -> Dictionary:
	var md: MonsterDef = get_monster(id)
	if md == null:
		return {}
	return {
		"health": md.health_at(level),
		"attack": md.attack_at(level),
		"xp": md.xp_at(level)
	}

# 从 level 升到 level+1 所需 XP (-1 = 已满级).
func get_xp_to_next(level: int) -> int:
	if xp_curve == null:
		return -1
	return xp_curve.xp_required(level)

func get_max_level() -> int:
	return xp_curve.max_level if xp_curve != null else 1

func get_tier_for_level(level: int) -> int:
	return tier_table.tier_for_level(level) if tier_table != null else 1
