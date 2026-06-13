extends Resource
class_name EpicItemDef

# Epic (史诗紫) named-item definition. Source: 数值表/epic_items.csv (10 件).
# 史诗 = 手工具名件: 保送 1 条顶值词缀 (取该词缀 T3 顶值), 其余 3~4 条按部位随机.
# 与传说的根本区别: 无机制改写 (橙字特效只属传说).

@export var id: StringName = &""
@export var display_name: String = ""              # 固定具名 (裂风长弓)
@export var slot: StringName = &""                 # EquipSlots.SLOT_NAMES 的值
@export var guaranteed_affix_id: StringName = &""  # 保送顶值词缀 (= affixes.csv 的 id)
@export var secondary_hint: String = ""            # 次要倾向 (说明用, 不影响 roll)
@export var serves_build: String = ""              # 服务 Build (说明用)
