extends Resource
class_name ItemBaseDef

# Base item definition (基底装备条目). One per 部位类型, holds the three Tier 基底名.
# Source: 数值表/base_items.csv (12 部位类型 × 3 Tier = 36 基底).
# 普通/精良/稀有 共用同一组基底, 只是词缀条数/命名不同.

# 基础值类型 (白值): 弓=武器DPS / 防具=护甲 / 箭袋·首饰=纯词缀(无白值).
enum BaseValueKind { WEAPON_DPS, ARMOR, NONE }

@export var slot: StringName = &""          # EquipSlots.SLOT_NAMES 的值 (戒指两槽共用 "ring")
@export var display_part: String = ""        # 部位中文名 (弓/箭袋/头...)
@export var t1_name: String = ""             # T1 基底名 (短弓)
@export var t2_name: String = ""             # T2 基底名 (猎弓)
@export var t3_name: String = ""             # T3 基底名 (战弓)
@export var base_value_kind: BaseValueKind = BaseValueKind.NONE
# 该部位"主roll"词缀 id 集合 (遵 affixes.csv 部位约束); 命名/掉落倾向参考用.
@export var main_roll_affixes: Array[StringName] = []

# 按 tier(1/2/3) 取基底名.
func name_for_tier(tier: int) -> String:
	match tier:
		1: return t1_name
		3: return t3_name
		2: return t2_name
		_: return t2_name
