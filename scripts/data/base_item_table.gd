extends Resource
class_name BaseItemTable

# Container resource holding the base-item pool (基底装备池). Authored as data/base_items.tres.
# Mirrors 数值表/base_items.csv: 12 部位类型 × 3 Tier 基底名.
@export var base_items: Array[ItemBaseDef] = []
