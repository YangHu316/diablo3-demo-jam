@tool
extends Node3D

# tower_orb_glow.gd —— 功能塔「发光球」模型上色 + 微弱自发光 + 复刻互动变色(关卡C 蓝图助手)。
# 挂在发光球 FBX 实例下作子节点:给球整棵子树所有 mesh 叠一层 material_override
# (就绪 = 塔色 / 冷却 = 暗灰,均带微弱自发光 emission_energy≈0.45)。
# 运行期监听 TowerBuffManager.tower_ready / tower_cooldown_changed(按 tower_id 过滤)切色,
# 复刻原 tower_trigger 的变色机制 —— **不改原塔脚本/场景**。两种塔用不同 ready_color 区分。
# @tool:编辑器里也按 ready_color 染色 + 自发光,所见即所得。

@export var tower_id: StringName = &"damage_tower":
	set(v):
		tower_id = v
@export var ready_color: Color = Color(1.0, 0.25, 0.25):
	set(v):
		ready_color = v
		_paint(ready_color)
@export var cooldown_color: Color = Color(0.35, 0.35, 0.4)
@export_range(0.0, 2.0, 0.05) var emission_energy: float = 0.45:
	set(v):
		emission_energy = v
		_paint(ready_color)

var _mat: StandardMaterial3D = null

func _ready() -> void:
	_ensure_mat()
	_paint(ready_color)
	_apply_override(get_parent())
	if Engine.is_editor_hint():
		return
	var tbm: Node = get_node_or_null("/root/TowerBuffManager")
	if tbm != null:
		if tbm.has_signal("tower_ready"):
			tbm.tower_ready.connect(_on_ready)
		if tbm.has_signal("tower_cooldown_changed"):
			tbm.tower_cooldown_changed.connect(_on_cd_changed)

func _on_ready(tid: StringName) -> void:
	if tid == tower_id:
		_paint(ready_color)

func _on_cd_changed(tid: StringName, cd_remaining: float, _cd_total: float) -> void:
	if tid == tower_id:
		_paint(cooldown_color if cd_remaining > 0.0 else ready_color)

func _ensure_mat() -> void:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.emission_enabled = true

func _paint(c: Color) -> void:
	_ensure_mat()
	_mat.albedo_color = c
	_mat.emission = c
	_mat.emission_energy_multiplier = emission_energy

func _apply_override(node: Node) -> void:
	if node == null:
		return
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = _mat
	for ch in node.get_children():
		_apply_override(ch)
