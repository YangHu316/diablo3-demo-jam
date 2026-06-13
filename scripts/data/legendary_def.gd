extends Resource
class_name LegendaryDef

# Legendary item definition (传奇装备). 5 total, Amazon-specific.
# Source: 04-Demo装备与掉落 §5, 02-Demo职业与技能 §6.2.
# Orange effect 不占词缀位, 机制改写型.

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: StringName = &""              # 对应 EquipSlot 名 (bow/quiver/head/boots/amulet...)
@export_multiline var effect_text: String = ""  # 橙字特效描述 (Demo 简化版)
@export var effect_id: StringName = &""          # 程序钩子用的特效标识, 战斗①据此实现
@export var is_first_orange_whitelist: bool = false  # 首橙白名单 (女妖之弓/冰霜之箭袋/疾风之靴)
