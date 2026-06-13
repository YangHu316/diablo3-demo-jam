extends Node

# Inventory (Autoload): 40-slot bag + 13 equip slots + aggregated stats.
# Day1 任务3/4 完整实现; 此处先定下对外信号契约 (Hour-0 与角色D敲定).
#
# 信号契约:
#   loot_dropped(quality, world_pos)  -> 角色D 挂光柱/音效 (quality = ItemInstance.Quality)
#   item_picked_up(item)              -> 拾取入包反馈
#   item_equipped(slot, item)         -> 装备槽刷新 (slot = EquipSlots.Slot)
#   item_unequipped(slot, item)
#   stats_changed(total_stats)        -> HUD/角色面板刷新 (total_stats: { StatKind: value })

signal loot_dropped(quality: int, world_pos: Vector3)
signal item_picked_up(item: ItemInstance)
signal item_equipped(slot: int, item: ItemInstance)
signal item_unequipped(slot: int, item: ItemInstance)
signal stats_changed(total_stats: Dictionary)

const BAG_CAPACITY: int = 40

var bag: Array[ItemInstance] = []                 # 容量 BAG_CAPACITY
var equipped: Dictionary = {}                     # EquipSlots.Slot -> ItemInstance

# 依赖注入: 默认走 autoload (/root/ProgressionManager); 测试 harness 可直接赋值.
var _progression: Node = null

func _ready() -> void:
	pass

# 任务3: 拾取入包. 满包返回 false (不丢弃, 物品留在地面).
func add_item(item: ItemInstance) -> bool:
	if item == null:
		return false
	if bag.size() >= BAG_CAPACITY:
		return false
	bag.append(item)
	item_picked_up.emit(item)
	return true

# 当前背包占用 / 是否已满.
func bag_count() -> int:
	return bag.size()

func is_full() -> bool:
	return bag.size() >= BAG_CAPACITY

# 背包物品只读快照 (UI 渲染用).
func get_bag_items() -> Array[ItemInstance]:
	var out: Array[ItemInstance] = []
	out.assign(bag)
	return out

# ---------------------------------------------------------------------------
# 任务4: 装备 / 卸下
# ---------------------------------------------------------------------------

# 槽位合法性: 0 .. SLOT_COUNT-1.
func _is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < EquipSlots.SLOT_COUNT

# 查询某槽当前装备 (空返回 null).
func get_equipped(slot: int) -> ItemInstance:
	return equipped.get(slot, null)

# 把 item 装到指定 slot:
#   - 物品须在背包内 (从背包移除)
#   - 该槽已有装备则先卸到背包 (背包满则装备失败, 保持原状)
#   - 发 item_unequipped(旧) / item_equipped(新) + stats_changed
func equip(slot: int, item: ItemInstance) -> bool:
	if item == null or not _is_valid_slot(slot):
		return false

	var bag_idx: int = bag.find(item)
	var prev: ItemInstance = equipped.get(slot, null)

	# 换装时, 若物品来自背包, 旧装备回填到它腾出的格子 -> 净占用不变.
	# 若物品不在背包(如直接装备掉落物), 旧装备需新增一格 -> 满包则失败.
	if prev != null and bag_idx < 0 and is_full():
		return false

	if bag_idx >= 0:
		bag.remove_at(bag_idx)

	equipped[slot] = item

	if prev != null:
		bag.append(prev)
		item_unequipped.emit(slot, prev)

	item_equipped.emit(slot, item)
	_emit_stats()
	return true

# 卸下指定槽, 物品回背包 (满包则失败, 保持装备状态). 返回卸下的物品 (失败/空槽返回 null).
func unequip(slot: int) -> ItemInstance:
	if not _is_valid_slot(slot):
		return null
	var item: ItemInstance = equipped.get(slot, null)
	if item == null:
		return null
	if is_full():
		return null
	equipped.erase(slot)
	bag.append(item)
	item_unequipped.emit(slot, item)
	_emit_stats()
	return item

# 快速装备: 按 item.slot 自动选槽. 戒指自动路由到空戒指位 (RING_1 满则用 RING_2).
# 返回最终落位的 slot, 失败返回 -1.
func quick_equip(item: ItemInstance) -> int:
	if item == null:
		return -1
	var target: int = item.slot
	if target == EquipSlots.Slot.RING_1 or target == EquipSlots.Slot.RING_2:
		if get_equipped(EquipSlots.Slot.RING_1) == null:
			target = EquipSlots.Slot.RING_1
		elif get_equipped(EquipSlots.Slot.RING_2) == null:
			target = EquipSlots.Slot.RING_2
		else:
			target = EquipSlots.Slot.RING_1   # 两戒满 -> 替换 RING_1
	if not _is_valid_slot(target):
		return -1
	if equip(target, item):
		return target
	return -1

# ---------------------------------------------------------------------------
# 任务4: 属性聚合 (基础属性 + 已装备词缀)
# ---------------------------------------------------------------------------

# 取 ProgressionManager: 优先注入引用, 否则在树内时取 autoload.
func _prog() -> Node:
	if _progression != null:
		return _progression
	if is_inside_tree():
		_progression = get_node_or_null("/root/ProgressionManager")
	return _progression

# 汇总: 升级基础主属性 (敏捷/体能) + 所有已装备物品的词缀加成.
# 返回 { AffixDef.StatKind(int): total_value(float) }.
func get_total_stats() -> Dictionary:
	var out: Dictionary = {}

	# 基础主属性 (来自 ProgressionManager 升级成长).
	var p: Node = _prog()
	if p != null:
		out[AffixDef.StatKind.AGILITY] = float(p.agility)
		out[AffixDef.StatKind.VITALITY] = float(p.vitality)

	# 叠加已装备词缀.
	for slot in equipped:
		var it: ItemInstance = equipped[slot]
		if it == null:
			continue
		var item_stats: Dictionary = it.aggregate_stats()
		for k in item_stats:
			out[k] = float(out.get(k, 0.0)) + float(item_stats[k])

	return out

func _emit_stats() -> void:
	stats_changed.emit(get_total_stats())
