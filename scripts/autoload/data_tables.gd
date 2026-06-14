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

# V3.0 大秘境: 守门人固定爆装清单 (直接读 CSV, 单一事实源).
const BOSS_DROP_LIST_PATH: String = "res://数值表/boss_drop_list.csv"

# V3.0 大秘境: 玩家固定面板 (开局即中期满装档; 展示面板写死, 换装不改数值).
const PLAYER_LOADOUT_PATH: String = "res://数值表/player_loadout.csv"

# 功能塔 buff 表 (伤害塔/加速塔: 加成幅度/持续/CD, 热调).
const TOWER_BUFFS_PATH: String = "res://数值表/tower_buffs.csv"

# 功能塔布点表 (手动布置: 每行一座塔 tower_id+坐标+朝向, 关卡由 TowerSpawner 读表实例化).
const TOWER_LAYOUT_PATH: String = "res://数值表/tower_layout.csv"

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

# V3.0: 守门人固定爆装 (boss_drop_list.csv 解析后的原始行: 名称/部位/is_set/特效).
var _boss_drops: Array[Dictionary] = []

# V3.0: 玩家固定面板 (player_loadout.csv 的 key->value 原始行).
var _player_loadout: Dictionary = {}

# 功能塔 buff (tower_buffs.csv): id -> { buff_type, magnitude, duration, cooldown, note }.
var _tower_buffs: Dictionary = {}
var _tower_layout: Array = []                # [{tower_id, pos:Vector3, rot_y_deg, note}, ...]

var is_loaded: bool = false

func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_load_affixes()
	_load_base_items()
	_load_epics()
	_load_legendaries()
	_load_monsters()
	_load_boss_drops()
	_load_player_loadout()
	_load_tower_buffs()
	_load_tower_layout()
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

# V3.0: 直接解析 boss_drop_list.csv (单一事实源, importer=keep). 末行"约束"跳过.
# 每行 -> { name, slot_zh, is_set, effect }. 部位中文留到取件时按枚举映射.
func _load_boss_drops() -> void:
	_boss_drops.clear()
	if not FileAccess.file_exists(BOSS_DROP_LIST_PATH):
		push_warning("DataTables: missing %s" % BOSS_DROP_LIST_PATH)
		return
	var f := FileAccess.open(BOSS_DROP_LIST_PATH, FileAccess.READ)
	if f == null:
		return
	var headers: PackedStringArray = f.get_csv_line()
	while not f.eof_reached():
		var cols: PackedStringArray = f.get_csv_line()
		if cols.size() <= 1 and (cols.is_empty() or cols[0] == ""):
			continue
		var row: Dictionary = {}
		for i in headers.size():
			row[String(headers[i]).strip_edges()] = String(cols[i]).strip_edges() if i < cols.size() else ""
		# 跳过末尾"约束"说明行 (序号列非数字).
		if not String(row.get("序号", "")).is_valid_int():
			continue
		_boss_drops.append({
			"name": String(row.get("名称", "")),
			"slot_zh": String(row.get("部位", "")),
			"is_set": String(row.get("is_set", "false")).to_lower() == "true",
			"effect": String(row.get("特效(展示用·中期毕业档)", "")),
		})
	f.close()

func _load_player_loadout() -> void:
	_player_loadout.clear()
	if not FileAccess.file_exists(PLAYER_LOADOUT_PATH):
		push_warning("DataTables: missing %s" % PLAYER_LOADOUT_PATH)
		return
	var f := FileAccess.open(PLAYER_LOADOUT_PATH, FileAccess.READ)
	if f == null:
		return
	var _headers: PackedStringArray = f.get_csv_line()   # key,value,note
	while not f.eof_reached():
		var cols: PackedStringArray = f.get_csv_line()
		if cols.size() < 2 or String(cols[0]).strip_edges() == "":
			continue
		_player_loadout[String(cols[0]).strip_edges()] = String(cols[1]).strip_edges()
	f.close()

# 功能塔 buff 表. 每行 id,buff_type,加成幅度,持续秒,冷却秒,备注 -> _tower_buffs[id]=Dict.
func _load_tower_buffs() -> void:
	_tower_buffs.clear()
	if not FileAccess.file_exists(TOWER_BUFFS_PATH):
		push_warning("DataTables: missing %s" % TOWER_BUFFS_PATH)
		return
	var f := FileAccess.open(TOWER_BUFFS_PATH, FileAccess.READ)
	if f == null:
		return
	var headers: PackedStringArray = f.get_csv_line()  # id,buff_type,加成幅度,持续秒,冷却秒,备注
	while not f.eof_reached():
		var cols: PackedStringArray = f.get_csv_line()
		if cols.size() < 5 or String(cols[0]).strip_edges() == "":
			continue
		var row: Dictionary = {}
		for i in headers.size():
			row[String(headers[i]).strip_edges()] = String(cols[i]).strip_edges() if i < cols.size() else ""
		var id: String = String(row.get("id", ""))
		if id == "":
			continue
		_tower_buffs[id] = {
			"buff_type": String(row.get("buff_type", "")),
			"magnitude": float(row.get("加成幅度", "0")),
			"duration": float(row.get("持续秒", "0")),
			"cooldown": float(row.get("冷却秒", "0")),
			"note": String(row.get("备注", "")),
		}
	f.close()

# 功能塔布点表. 每行 tower_id,pos_x,pos_y,pos_z,rot_y,备注 -> _tower_layout 追加一座塔.
# 手动布置: 改塔位置/增删塔只编辑此 CSV, 不动场景文件. TowerSpawner 据此实例化.
func _load_tower_layout() -> void:
	_tower_layout.clear()
	if not FileAccess.file_exists(TOWER_LAYOUT_PATH):
		push_warning("DataTables: missing %s" % TOWER_LAYOUT_PATH)
		return
	var f := FileAccess.open(TOWER_LAYOUT_PATH, FileAccess.READ)
	if f == null:
		return
	var headers: PackedStringArray = f.get_csv_line()  # tower_id,pos_x,pos_y,pos_z,rot_y,备注
	while not f.eof_reached():
		var cols: PackedStringArray = f.get_csv_line()
		if cols.size() < 4 or String(cols[0]).strip_edges() == "":
			continue
		var row: Dictionary = {}
		for i in headers.size():
			row[String(headers[i]).strip_edges()] = String(cols[i]).strip_edges() if i < cols.size() else ""
		var tid: String = String(row.get("tower_id", ""))
		if tid == "":
			continue
		_tower_layout.append({
			"tower_id": tid,
			"pos": Vector3(
				float(row.get("pos_x", "0")),
				float(row.get("pos_y", "0")),
				float(row.get("pos_z", "0"))),
			"rot_y_deg": float(row.get("rot_y", "0")),
			"note": String(row.get("备注", "")),
		})
	f.close()

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

# ---- V3.0 守门人固定爆装 (boss_drop_list.csv) ----

# 中文部位 -> EquipSlots.Slot 枚举. 戒指/肩等多件按出现顺序分配不同槽.
const _SLOT_ZH_MAP: Dictionary = {
	"头": EquipSlots.Slot.HEAD, "肩": EquipSlots.Slot.SHOULDER,
	"胸": EquipSlots.Slot.CHEST, "腕": EquipSlots.Slot.WRIST,
	"手套": EquipSlots.Slot.GLOVES, "腰": EquipSlots.Slot.WAIST,
	"腿": EquipSlots.Slot.LEGS, "靴": EquipSlots.Slot.BOOTS,
	"项链": EquipSlots.Slot.AMULET, "戒指": EquipSlots.Slot.RING_1,
	"弓": EquipSlots.Slot.BOW, "箭袋": EquipSlots.Slot.QUIVER,
}

# 守门人击杀时生成的全部爆装 (固定·非随机). 每次调用返回全新 ItemInstance 数组.
# quality 一律 LEGENDARY; 绿套装走 is_set 旁路 (boss_drop_list.csv 约束).
func get_boss_drop_items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	var ring_count: int = 0
	for row in _boss_drops:
		var item := ItemInstance.new()
		item.display_name = String(row.get("name", ""))
		item.quality = ItemInstance.Quality.LEGENDARY
		item.is_set = bool(row.get("is_set", false))
		item.legendary_effect_text = String(row.get("effect", ""))
		var slot_zh: String = String(row.get("slot_zh", ""))
		var slot: int = int(_SLOT_ZH_MAP.get(slot_zh, EquipSlots.Slot.HEAD))
		# 第二枚戒指落 RING_2 (展示用, 避免两枚同槽视觉重叠).
		if slot == EquipSlots.Slot.RING_1:
			if ring_count >= 1:
				slot = EquipSlots.Slot.RING_2
			ring_count += 1
		item.slot = slot
		out.append(item)
	return out

func get_boss_drop_count() -> int:
	return _boss_drops.size()

# ---- V3.0 玩家固定面板 (player_loadout.csv) ----

# 取 loadout 某 key 的原始字符串值 (如 "敏捷"->"150", "暴击率"->"45%").
func get_loadout_value(key: String) -> String:
	return String(_player_loadout.get(key, ""))

# ---- 功能塔 buff (tower_buffs.csv) ----

# 取某塔 buff 定义: { buff_type, magnitude, duration, cooldown, note }. 无则空 Dict.
func get_tower_buff(id: String) -> Dictionary:
	return _tower_buffs.get(id, {})

func get_all_tower_buff_ids() -> Array:
	return _tower_buffs.keys()

# 功能塔布点: 返回 [{tower_id:String, pos:Vector3, rot_y_deg:float, note:String}, ...].
func get_tower_layout() -> Array:
	return _tower_layout

# 把 "45%" / "+400%" / "约50%" 之类含符号字符串抽成纯数值 (float). 解析失败回退 fallback.
func _loadout_num(key: String, fallback: float) -> float:
	var raw: String = get_loadout_value(key)
	if raw == "":
		return fallback
	var digits: String = ""
	for ch in raw:
		if (ch >= "0" and ch <= "9") or ch == "." :
			digits += ch
	return float(digits) if digits != "" else fallback

# 展示面板写死的中期档属性 (StatKind -> value). 换装不改这些数值 (拾取仅观感).
# 数据源: player_loadout.csv (单一事实源); 缺项用 build 固定值兜底.
func get_fixed_panel_stats() -> Dictionary:
	return {
		AffixDef.StatKind.AGILITY: _loadout_num("敏捷", 150.0),
		AffixDef.StatKind.VITALITY: _loadout_num("最大生命", 1200.0),
		AffixDef.StatKind.ARMOR: _loadout_num("护甲减伤", 50.0),
		AffixDef.StatKind.ALL_RESIST: 50.0,
		AffixDef.StatKind.CRIT_CHANCE: _loadout_num("暴击率", 45.0),
		AffixDef.StatKind.CRIT_DAMAGE: _loadout_num("暴击伤害", 400.0),
		AffixDef.StatKind.ATTACK_SPEED: _loadout_num("攻速APS", 1.5),
		AffixDef.StatKind.SKILL_DAMAGE: _loadout_num("敏捷", 150.0),
		AffixDef.StatKind.WEAPON_DAMAGE: _loadout_num("武器均伤", 24.0),
		AffixDef.StatKind.MOVE_SPEED: 25.0,
	}

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
