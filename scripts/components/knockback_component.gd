extends Node

# knockback_component.gd — 挂在敌人 (CharacterBody3D) 子节点,命名 "KnockbackComponent"。
# 接受 (direction, distance, duration),在 duration 内沿 direction 推 distance 米。
# 速度线性衰减 -> 自然贴地滑出,移动用 move_and_slide,碰墙自动止。
#
# 用法: $KnockbackComponent.apply(hit_direction, 2.5, 0.4)
#
# 注:
#   - 父节点必须是 CharacterBody3D
#   - 父节点的 _physics_process 在 is_active() 期间应跳过自身 AI 移动,
#     否则两边都调用 move_and_slide 会冲突。enemy_zombie 当前没 AI,直接用没问题。

signal knockback_started(direction: Vector3, duration: float)
signal knockback_ended()

# 线性衰减:总位移 = 0.5 * v0 * T = distance => v0 = 2 * distance / T
# 我们记录 initial_speed,然后每帧按 t 比例衰减。

var _direction: Vector3 = Vector3.ZERO
var _initial_speed: float = 0.0
var _remaining: float = 0.0
var _duration_total: float = 0.0
var _body: CharacterBody3D = null

func _ready() -> void:
	var p: Node = get_parent()
	if p is CharacterBody3D:
		_body = p
	else:
		push_warning("KnockbackComponent: parent is not CharacterBody3D")

func is_active() -> bool:
	return _remaining > 0.0

func apply(direction: Vector3, distance: float, duration: float) -> void:
	if _body == null or not is_instance_valid(_body):
		return
	if duration <= 0.0 or distance <= 0.0:
		return
	var d: Vector3 = direction
	d.y = 0.0
	if d.length() < 0.001:
		return
	_direction = d.normalized()
	_duration_total = duration
	_remaining = duration
	_initial_speed = (2.0 * distance) / duration  # 线性衰减下的初速
	knockback_started.emit(_direction, duration)

func cancel() -> void:
	if _remaining > 0.0:
		_remaining = 0.0
		if _body != null and is_instance_valid(_body):
			_body.velocity = Vector3.ZERO
		knockback_ended.emit()

func _physics_process(delta: float) -> void:
	if _remaining <= 0.0:
		return
	if _body == null or not is_instance_valid(_body):
		_remaining = 0.0
		return
	# 防御:本体正在销毁(死亡演出会把 scale 补间到 0)时停止接管物理,
	# 否则对退化基底(det==0)调 move_and_slide 会每帧刷屏报错。
	if _body.is_queued_for_deletion():
		cancel()
		return

	_remaining = max(0.0, _remaining - delta)
	# 线性衰减:t = remaining / total in [0, 1],speed = v0 * t
	var t: float = 0.0
	if _duration_total > 0.0:
		t = _remaining / _duration_total
	var current_speed: float = _initial_speed * t

	# 贴地滑:y velocity = 0 (顶视图无重力)
	_body.velocity = _direction * current_speed
	_body.move_and_slide()  # 碰墙自动停(velocity 投影掉)

	if _remaining <= 0.0:
		_body.velocity = Vector3.ZERO
		knockback_ended.emit()
