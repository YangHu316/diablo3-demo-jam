extends Resource
class_name ItemInstance

# A concrete generated item carried in inventory / equipped.
# Produced by the item/affix generator (任务2). Not authored in editor — runtime only.
# Source: 04-Demo装备与掉落 §3.1 品质规则.

enum Quality { MAGIC, RARE, LEGENDARY }   # 蓝 / 黄 / 橙

const QUALITY_NAMES: Dictionary = {
	Quality.MAGIC: "魔法",
	Quality.RARE: "稀有",
	Quality.LEGENDARY: "传奇"
}

const QUALITY_COLORS: Dictionary = {
	Quality.MAGIC: Color(0.30, 0.45, 1.0),     # 蓝
	Quality.RARE: Color(1.0, 0.92, 0.25),      # 黄
	Quality.LEGENDARY: Color(1.0, 0.55, 0.0)   # 橙
}

@export var display_name: String = ""
@export var quality: Quality = Quality.MAGIC
@export var slot: int = 0                       # EquipSlots.Slot
@export var item_level: int = 1
@export var tier: int = 1

# Rolled affixes: 每条 = { "stat_kind": int, "value": float, "is_percent": bool, "affix_id": StringName }
@export var affixes: Array[Dictionary] = []

# 传奇专属.
@export var legendary_id: StringName = &""      # 非空表示传奇
@export var legendary_effect_text: String = ""
@export var legendary_effect_id: StringName = &""

func is_legendary() -> bool:
	return quality == Quality.LEGENDARY

# 聚合本物品提供的属性 -> { StatKind: total_value }. 供 Inventory 计算面板.
func aggregate_stats() -> Dictionary:
	var out: Dictionary = {}
	for a in affixes:
		var k: int = int(a["stat_kind"])
		out[k] = float(out.get(k, 0.0)) + float(a["value"])
	return out
