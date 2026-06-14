@tool
extends Node3D

# elite_tint.gd —— 精英怪「异色」视觉标记(关卡C 蓝图助手·纯视觉)。
# 挂在「精英怪实例」下作子节点:给父节点(敌人)整棵子树里所有 MeshInstance3D
# 叠一层异色 material_overlay(保留原模型细节 + 染色 + 微发光)。
# 配合精英实例根的 1.5× 缩放 = 精英 = 普通怪「放大 + 异色」版本。
# 不改数值 / 不碰 enemy_base AI(数值仍由敌人自己的 data .tres 决定)。
# @tool:编辑器里也染色,所见即所得;结构无关(递归找 mesh,Synty 模型也适用)。

@export var tint_color: Color = Color(0.9, 0.1, 0.1):
	set(v):
		tint_color = v
		_apply()

# 精英 id(elites.csv): 决定击杀掉几个进度球 (elite_blue=1, champion_yellow=2).
# 场景里精英是「直接摆的实例」, 不走 spawn_trigger, 所以 monster_id meta 没人挂 ->
# LootManager._maybe_spawn_progress_balls 因 has_meta 失败而不掉球. 这里运行期补挂.
# 空串 = 不挂(纯染色, 不掉进度球).
@export var monster_id: StringName = &""

func _ready() -> void:
	_apply()
	if not Engine.is_editor_hint():
		_tag_parent_elite()

# 给父节点(精英 enemy_base)挂 monster_id meta, 使 LootManager 识别为精英并掉进度球.
func _tag_parent_elite() -> void:
	if monster_id == &"":
		return
	var parent: Node = get_parent()
	if parent != null:
		parent.set_meta("monster_id", monster_id)

func _apply() -> void:
	var parent: Node = get_parent()
	if parent == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(tint_color.r, tint_color.g, tint_color.b, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = tint_color
	mat.emission_energy_multiplier = 0.5
	_tint_recursive(parent, mat)

func _tint_recursive(node: Node, mat: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_overlay = mat
	for c in node.get_children():
		_tint_recursive(c, mat)
