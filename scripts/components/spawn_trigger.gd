extends Area3D

# spawn_trigger.gd — 挂在 Area3D 上的区域触发器。
# 玩家进入触发圈 → 调 SpawnManager.spawn_wave() 一次性生成一波怪。
# 默认 one_shot=true,触发一次后自动失效(可选保留节点供调试)。
#
# 节点结构:
#   Area3D (script = spawn_trigger.gd, monitoring=true, collision_mask=1=player)
#   └ CollisionShape3D (定义触发圈形状)
#
# 配置(Inspector):
#   enemy_scene:  PackedScene  → res://scenes/enemies/enemy_zombie.tscn
#   enemy_data:   Resource     → res://scripts/entities/data/walking_corpse.tres (可选)
#   count:        int          → 5
#   formation:    String       → "cluster" / "line" / "surround"
#   spawn_radius: float        → 3.0
#   spawn_at_self: bool        → true(在自己的位置生成),false 则用 spawn_center_path
#   spawn_center_path: NodePath → 自定义生成中心节点(例如远处的一个 Marker3D)
#   one_shot:     bool         → true
#   target_player: bool        → true(surround 阵型时围住玩家)

signal wave_triggered(wave_id: int)

@export var enemy_scene: PackedScene = null
@export var enemy_data: Resource = null
@export_range(1, 50, 1) var count: int = 5
@export_enum("cluster", "line", "surround") var formation: String = "cluster"
@export_range(0.5, 30.0, 0.5) var spawn_radius: float = 3.0
@export var spawn_at_self: bool = true
@export var spawn_center_path: NodePath = NodePath("")
@export var one_shot: bool = true
@export var target_player: bool = true

var _triggered: bool = false

func _ready() -> void:
	# Area3D 默认 monitoring=true,这里再保险设置;collision_mask 应在 .tscn 里设为 1(player layer)
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _triggered and one_shot:
		return
	if body == null or not body.is_in_group("player"):
		return
	_trigger_spawn(body)

func _trigger_spawn(player_body: Node) -> void:
	if enemy_scene == null:
		push_warning("SpawnTrigger '%s': enemy_scene not set" % name)
		return
	var sm: Node = get_node_or_null("/root/SpawnManager")
	if sm == null:
		push_warning("SpawnTrigger: SpawnManager autoload not found")
		return

	var center: Vector3 = global_position
	if not spawn_at_self and spawn_center_path != NodePath(""):
		var n: Node = get_node_or_null(spawn_center_path)
		if n is Node3D:
			center = (n as Node3D).global_position

	var target: Node3D = null
	if target_player and player_body is Node3D:
		target = player_body as Node3D

	var wid: int = sm.spawn_wave({
		"enemy_scene": enemy_scene,
		"enemy_data": enemy_data,
		"count": count,
		"formation": formation,
		"center": center,
		"radius": spawn_radius,
		"target": target,
	})
	if wid >= 0:
		_triggered = true
		wave_triggered.emit(wid)

# 公共 API:重置触发器(允许再次触发)
func reset() -> void:
	_triggered = false

# 公共 API:手动触发(调试 / 由关卡脚本调)
func force_trigger() -> void:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.is_empty():
		_trigger_spawn(null)
	else:
		_trigger_spawn(arr[0])
