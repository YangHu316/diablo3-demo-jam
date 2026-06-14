extends Resource
class_name ItemInstance

# A concrete generated item carried in inventory / equipped.
# Produced by the item/affix generator (任务2). Not authored in editor — runtime only.
# Source: 04-Demo装备与掉落 §3.1 品质规则.

# 5 档稀有度阶梯 (扩展层, 数值表/扩展-稀有度-掉落-敌人差异化.md §一).
# 枚举值按 劣→优 单调递增 (COMMON=0 … LEGENDARY=4), 故可直接比大小判优劣 / 决定光柱强度.
# demo 主线仍可只跑 3 档 (精良/稀有/传说); 普通+史诗为 opt-in 扩展档.
enum Quality { COMMON, MAGIC, RARE, EPIC, LEGENDARY }   # 白 / 蓝 / 黄 / 紫 / 橙

const QUALITY_NAMES: Dictionary = {
	Quality.COMMON: "普通",
	Quality.MAGIC: "魔法",
	Quality.RARE: "稀有",
	Quality.EPIC: "史诗",
	Quality.LEGENDARY: "传奇"
}

const QUALITY_COLORS: Dictionary = {
	Quality.COMMON: Color(0.62, 0.62, 0.62),   # 白/灰
	Quality.MAGIC: Color(0.30, 0.45, 1.0),     # 蓝
	Quality.RARE: Color(1.0, 0.92, 0.25),      # 黄
	Quality.EPIC: Color(0.64, 0.21, 0.93),     # 紫
	Quality.LEGENDARY: Color(1.0, 0.55, 0.0)   # 橙
}

# 套装绿 (boss_drop_list.csv: is_set 件渲染色; 优先级 > 橙).
const SET_COLOR: Color = Color(0.13, 0.85, 0.18)   # 绿

@export var display_name: String = ""
@export var quality: Quality = Quality.MAGIC
@export var slot: int = 0                       # EquipSlots.Slot
@export var item_level: int = 1
@export var tier: int = 1

# 套装(绿装)旁路 (V3.0 大秘境: boss_drop_list.csv).
# is_set=true 的件 quality 仍 = LEGENDARY, 但渲染绿光柱(优先级 > 橙), 不新增 Quality 枚举档.
@export var is_set: bool = false

# Rolled affixes: 每条 = { "stat_kind": int, "value": float, "is_percent": bool, "affix_id": StringName }
@export var affixes: Array[Dictionary] = []

# 传奇专属.
@export var legendary_id: StringName = &""      # 非空表示传奇
@export var legendary_effect_text: String = ""
@export var legendary_effect_id: StringName = &""

func is_legendary() -> bool:
	return quality == Quality.LEGENDARY

# 名牌/光柱显示色: 套装绿优先于橙 (boss_drop_list.csv 约束: 绿柱优先级 > 橙).
func display_color() -> Color:
	if is_set:
		return SET_COLOR
	return QUALITY_COLORS.get(quality, Color.WHITE)

# 聚合本物品提供的属性 -> { StatKind: total_value }. 供 Inventory 计算面板.
func aggregate_stats() -> Dictionary:
	var out: Dictionary = {}
	for a in affixes:
		var k: int = int(a["stat_kind"])
		out[k] = float(out.get(k, 0.0)) + float(a["value"])
	return out
