extends Node3D

# EnemyArrow — 弓手射出的简化箭矢。
# 直线飞行 → 距离/时间到 / 命中玩家 = 销毁。
# 由 enemy_archer.gd 实例化,通过公开字段注入参数。

@export var speed: float = 18.0
@export var damage: int = 33
@export var max_lifetime: float = 1.6  # 18 m/s × 1.6 s ≈ 29 m,够 18~30 码弓手射程
@export var direction: Vector3 = Vector3.FORWARD

# 射手引用,避免飞过自己时打到自己(弓手没有玩家友军判定)
var shooter: Node = null

const HIT_RADIUS: float = 0.6  # 球检测半径(玩家胶囊 0.4)

var _life: float = 0.0
var _consumed: bool = false

func _ready() -> void:
	# 朝向方向
	var d: Vector3 = direction
	d.y = 0.0
	if d.length() > 0.001:
		direction = d.normalized()
		look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	if _consumed:
		return
	_life += delta
	if _life >= max_lifetime:
		queue_free()
		return
	# 移动
	global_position += direction * speed * delta
	# 命中检测:简单距离检测玩家(无需 Area3D)
	var players: Array = get_tree().get_nodes_in_group("player")
	for p in players:
		if not is_instance_valid(p) or not (p is Node3D):
			continue
		var pp: Vector3 = (p as Node3D).global_position + Vector3(0, 0.9, 0)
		if global_position.distance_to(pp) <= HIT_RADIUS:
			_on_hit_player(p)
			return

func _on_hit_player(player: Node) -> void:
	_consumed = true
	if player.has_method("take_damage"):
		player.take_damage(damage, shooter)
	queue_free()
