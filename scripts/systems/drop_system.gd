extends RefCounted
class_name DropSystem

# 掉落判定系统 (任务3). 纯逻辑, 无场景依赖, 可 headless 验证.
# 输入: 掉落源类型 + 玩家等级 + 梦魇层数; 输出: Array[ItemInstance] (可能为空).
# 规则来源: 04-Demo装备与掉落 §6.1 掉落源×品质权重 / §2.3 保底状态机 / §7 智能掉落.
#
# 用法:
#   var ds := DropSystem.new(DataTables, item_generator)
#   var items := ds.roll_drop(DropSystem.Source.TRASH, player_level)
#   # items 为空 = 本次不掉; 否则逐件已是 ItemInstance, 交 Inventory / 地面 spawn.

enum Source {
	TRASH,            # 普通白怪
	ELITE_BLUE,       # 蓝名精英 (成群)
	CHAMPION_YELLOW,  # 黄名首领
	BUTCHER,          # 屠夫 (唯一 Boss)
	CHEST_COMMON,     # 普通宝箱/罐桶群
	CHEST_FANCY,      # 华丽宝箱
}

# 每个掉落源的配置: 装备掉落率 / 件数[min,max] / 蓝黄橙基础权重 / 是否保底载体.
# 数值严格对齐策划 §6.1.
const SOURCE_CONFIG := {
	Source.TRASH:           { "drop_rate": 0.18, "count": [1, 1], "w": [85.0, 14.5, 0.5],  "pity_carrier": false },
	Source.ELITE_BLUE:      { "drop_rate": 1.00, "count": [1, 2], "w": [60.0, 37.0, 3.0],  "pity_carrier": true  },
	Source.CHAMPION_YELLOW: { "drop_rate": 1.00, "count": [2, 2], "w": [48.0, 47.0, 5.0],  "pity_carrier": true  },
	Source.BUTCHER:         { "drop_rate": 1.00, "count": [4, 4], "w": [0.0, 75.0, 25.0],  "pity_carrier": true  },
	Source.CHEST_COMMON:    { "drop_rate": 0.35, "count": [1, 1], "w": [90.0, 10.0, 0.0],  "pity_carrier": false },
	Source.CHEST_FANCY:     { "drop_rate": 1.00, "count": [2, 2], "w": [40.0, 55.0, 5.0],  "pity_carrier": true  },
}

# 首橙白名单 (§7.3): 本局第 1 件传奇必从这三件核心件抽.
const FIRST_ORANGE_WHITELIST: Array[StringName] = [
	&"banshee_bow", &"frost_quiver", &"windforce_boots"
]

const PITY_TIMER_HARD_THRESHOLD: float = 480.0   # 8 分钟 (秒). 硬保底首橙.

# 掉落物可出现的槽位池 (亚马逊弓系; 随机选一个槽生成).
const DROP_SLOTS: Array[int] = [
	EquipSlots.Slot.HEAD, EquipSlots.Slot.SHOULDER, EquipSlots.Slot.CHEST,
	EquipSlots.Slot.WRIST, EquipSlots.Slot.GLOVES, EquipSlots.Slot.WAIST,
	EquipSlots.Slot.LEGS, EquipSlots.Slot.BOOTS, EquipSlots.Slot.AMULET,
	EquipSlots.Slot.RING_1, EquipSlots.Slot.BOW, EquipSlots.Slot.QUIVER,
]

var _dt: Object = null               # DataTables
var _gen: ItemGenerator = null       # ItemGenerator (任务2)
var _rng: RandomNumberGenerator

# ---- 保底状态 (§2.3 给程序的状态机) ----
var pity_timer: float = 0.0          # 自上次传奇以来累计游戏时间 (秒)
var pity_stack: int = 0              # 自上次传奇以来击杀精英组数
var leg_count: int = 0               # 本局已掉传奇总数
var nightmare_tier: int = 0          # 0=主线 1=梦魇1层 2=梦魇2层
var _dropped_legendaries: Array[StringName] = []   # 已掉传奇 id (前4件查重)

func _init(data_tables: Object, generator: ItemGenerator, seed_value: int = -1) -> void:
	_dt = data_tables
	_gen = generator
	_rng = RandomNumberGenerator.new()
	if seed_value >= 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()

# 梦魇层数 -> 橙权重系数 (§6.2).
func _nightmare_mult() -> float:
	match nightmare_tier:
		1: return 1.5
		2: return 2.0
		_: return 1.0

# 精英组累计 (战斗① 杀完一组精英时调一次, 喂软保底).
func register_elite_kill() -> void:
	pity_stack += 1

# 游戏时间推进 (暂停/过场不计, 由上层每帧喂 delta).
func tick(delta: float) -> void:
	pity_timer += delta

# ---------------------------------------------------------------------------
# 核心: 掷一次掉落. 返回本次掉落的物品数组 (可能为空).
# ---------------------------------------------------------------------------
func roll_drop(source: int, player_level: int) -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	var cfg: Dictionary = SOURCE_CONFIG.get(source, {})
	if cfg.is_empty():
		return out

	# 1) 是否产出装备.
	if _rng.randf() > float(cfg["drop_rate"]):
		return out

	# 2) 件数.
	var count_pair: Array = cfg["count"]
	var n: int = _rng.randi_range(int(count_pair[0]), int(count_pair[1]))

	# 3) 硬保底首橙判定 (仅保底载体, §2.3 边界): leg_count=0 且 pity_timer≥8min.
	var force_orange: bool = (
		bool(cfg["pity_carrier"])
		and leg_count == 0
		and pity_timer >= PITY_TIMER_HARD_THRESHOLD
	)

	for i in range(n):
		var quality: int = _roll_quality(cfg["w"], force_orange and i == 0)
		var item: ItemInstance = _make_item(quality, player_level)
		if item != null:
			out.append(item)
		# 同一载体单次最多 1 件保底橙.
		if force_orange and i == 0:
			force_orange = false
	return out

# 按权重(叠梦魇系数+软保底)掷品质. force=true 直接出橙.
func _roll_quality(base_w: Array, force_orange: bool) -> int:
	if force_orange:
		return ItemInstance.Quality.LEGENDARY
	var w_blue: float = float(base_w[0])
	var w_yellow: float = float(base_w[1])
	# P(橙) = 基础 × 梦魇系数 + pity_stack×2% (§2.3).
	var w_orange: float = float(base_w[2]) * _nightmare_mult() + float(pity_stack) * 2.0
	var total: float = w_blue + w_yellow + w_orange
	if total <= 0.0:
		return ItemInstance.Quality.MAGIC
	var r: float = _rng.randf() * total
	if r < w_blue:
		return ItemInstance.Quality.MAGIC
	if r < w_blue + w_yellow:
		return ItemInstance.Quality.RARE
	return ItemInstance.Quality.LEGENDARY

# 由品质生成一件具体物品; 传奇走白名单/查重定向.
func _make_item(quality: int, player_level: int) -> ItemInstance:
	if _gen == null:
		return null
	if quality == ItemInstance.Quality.LEGENDARY:
		return _make_legendary(player_level)
	var slot: int = DROP_SLOTS[_rng.randi_range(0, DROP_SLOTS.size() - 1)]
	return _gen.generate(slot, player_level, quality)

# 传奇定向: 首橙白名单 -> 前4件查重 -> 生成.
func _make_legendary(player_level: int) -> ItemInstance:
	var leg_id: StringName = _pick_legendary_id()
	if leg_id == &"":
		# 池子耗尽兜底: 退化稀有.
		var slot: int = DROP_SLOTS[_rng.randi_range(0, DROP_SLOTS.size() - 1)]
		return _gen.generate(slot, player_level, ItemInstance.Quality.RARE)
	var item: ItemInstance = _gen.generate_legendary(leg_id, player_level)
	leg_count += 1
	_dropped_legendaries.append(leg_id)
	# 任意传奇掉落后清零软/硬保底计时 (§2.3).
	pity_timer = 0.0
	pity_stack = 0
	return item

# 选传奇 id: 第1件∈白名单; 前4件查重不重复; 第5件起允许重复 (§7.2/7.3).
func _pick_legendary_id() -> StringName:
	var all_ids: Array[StringName] = []
	for ld in _dt.get_all_legendaries():
		all_ids.append(ld.id)
	if all_ids.is_empty():
		return &""

	# 第 1 件: 白名单内随机.
	if leg_count == 0:
		var wl: Array[StringName] = []
		for id in FIRST_ORANGE_WHITELIST:
			if all_ids.has(id):
				wl.append(id)
		if not wl.is_empty():
			return wl[_rng.randi_range(0, wl.size() - 1)]

	# 前 4 件查重: 从未掉过的里抽.
	if leg_count < 4:
		var fresh: Array[StringName] = []
		for id in all_ids:
			if not _dropped_legendaries.has(id):
				fresh.append(id)
		if not fresh.is_empty():
			return fresh[_rng.randi_range(0, fresh.size() - 1)]

	# 第 5 件起: 全池随机 (允许重复).
	return all_ids[_rng.randi_range(0, all_ids.size() - 1)]

# 已掉传奇数 / 清单 (结算页 n/5 钩子用).
func get_legendary_count() -> int:
	return leg_count

func get_dropped_legendaries() -> Array[StringName]:
	return _dropped_legendaries
