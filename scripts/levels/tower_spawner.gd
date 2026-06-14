extends Node3D

# TowerSpawner: 关卡加载时读功能塔布点表, 自动实例化 tower_trigger.tscn 到场景.
# 手动布置入口 = 数值表/tower_layout.csv (改坐标/增删塔只编辑 CSV, 不动场景文件).
#
# 挂法: 作为关卡场景(level_02_play)的直接子节点; _ready 里向上找关卡根作为塔的父节点,
# 逐行 DataTables.get_tower_layout() 实例化 → 设 tower_id + global_position + rot_y.
# 参照 spawn_manager 的 instantiate→设属性→add_child→后置 transform 范式.

const TOWER_TRIGGER_SCENE: PackedScene = preload("res://scenes/props/tower_trigger.tscn")

# 实例化到哪个父节点 (留空=塔挂到本 spawner 的父节点, 即关卡根, 与原硬编码摆位同级).
@export var spawn_parent_path: NodePath

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	# 延迟一帧: 关卡根 _ready 期间父节点正忙于建子树, 直接 add_child 会被拒.
	_spawn_from_layout.call_deferred()

func _spawn_from_layout() -> void:
	var dt: Node = get_node_or_null("/root/DataTables")
	if dt == null or not dt.has_method("get_tower_layout"):
		push_warning("TowerSpawner: DataTables 不可用, 跳过布塔")
		return
	var parent: Node = get_node_or_null(spawn_parent_path) if not spawn_parent_path.is_empty() else get_parent()
	if parent == null:
		parent = self
	var layout: Array = dt.get_tower_layout()
	for entry in layout:
		_spawn_one(parent, entry)

func _spawn_one(parent: Node, entry: Dictionary) -> void:
	var tower := TOWER_TRIGGER_SCENE.instantiate()
	# add_child 前设导出属性 (tower_id 影响 _ready 里的颜色推断/信号过滤).
	tower.tower_id = StringName(String(entry.get("tower_id", "damage_tower")))
	parent.add_child(tower)
	# 后置世界变换.
	if tower is Node3D:
		var t := tower as Node3D
		t.global_position = entry.get("pos", Vector3.ZERO)
		t.rotation.y = deg_to_rad(float(entry.get("rot_y_deg", 0.0)))
