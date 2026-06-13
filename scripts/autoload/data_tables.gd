extends Node

# DataTables (Autoload): central data registry. Loads all .tres tables at startup
# and exposes typed query APIs. This is the dependency 战斗① is waiting on.
#
# Hour-0 contract — query API stays stable; underlying .tres can be swapped when
# 关卡C finalizes numbers (Day1 上午先用占位/初版数值).

const AFFIX_TABLE_PATH: String = "res://data/affixes.tres"
const LEGENDARY_TABLE_PATH: String = "res://data/legendaries.tres"
const MONSTER_TABLE_PATH: String = "res://data/monsters.tres"
const XP_CURVE_PATH: String = "res://data/xp_curve.tres"
const TIER_TABLE_PATH: String = "res://data/tier_table.tres"

var _affixes: Array[AffixDef] = []
var _affix_by_id: Dictionary = {}            # StringName -> AffixDef
var _affixes_by_slot: Dictionary = {}        # slot StringName -> Array[AffixDef]

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
