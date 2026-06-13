extends Resource
class_name EpicItemTable

# Container resource holding the epic named-item pool (史诗具名池). Authored as data/epic_items.tres.
# Mirrors 数值表/epic_items.csv: 10 件史诗.
@export var epics: Array[EpicItemDef] = []
