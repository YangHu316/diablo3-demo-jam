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

func _ready() -> void:
	pass

# 任务3/4 实现占位 —— 签名先定, 下游可对接.
func add_item(_item: ItemInstance) -> bool:
	return false

func equip(_slot: int, _item: ItemInstance) -> void:
	pass

func get_total_stats() -> Dictionary:
	return {}
