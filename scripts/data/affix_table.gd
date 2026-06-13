extends Resource
class_name AffixTable

# Container resource holding the full affix pool (词缀池). Authored as data/affixes.tres.
@export var affixes: Array[AffixDef] = []
