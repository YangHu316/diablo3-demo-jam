extends CharacterBody3D

# Player: WASD 移动 + 鼠标朝向 + 翻滚位移。
# 攻击逻辑由 SkillSlotManager / SkillExecutor 子节点处理。
# 本脚本:移动、转向、生命值、翻滚、死亡。

signal health_changed(current: int, max_hp: int)
signal player_died()
signal dodge_started(direction: Vector3, duration: float)
signal dodge_ended()

const SPEED: float = 7.0

@export var max_health: int = 200

var current_health: int = 200
var is_moving: bool = false
var is_invulnerable: bool = false
var is_frozen: bool = false
var is_dead: bool = false

# ── 翻滚状态 ────────────────────────────────────────
var is_dodging: bool = false
var _dodge_velocity: Vector3 = Vector3.ZERO
var _dodge_timer: float = 0.0

# ── 被动:闪避本能(策划 02 §4.3 b)─────────────────
# 翻滚结束后 EVADE_BUFFER_TIME 内受到伤害 -EVADE_DAMAGE_REDUCTION
const EVADE_BUFFER_TIME: float = 2.0
const EVADE_DAMAGE_REDUCTION: float = 0.20  # 20% 减伤
var _evade_buffer_timer: float = 0.0

var _last_forward: Vector3 = Vector3.FORWARD
var _camera: Camera3D = null
var _ground_plane: Plane = Plane(Vector3.UP, 0.0)

@onready var arrow_spawn_point: Marker3D = $ArrowSpawnPoint

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	health_changed.emit(current_health, max_health)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# 闪避本能 buffer 衰减(独立于状态机)
	if _evade_buffer_timer > 0.0:
		_evade_buffer_timer -= delta

	# 翻滚优先级最高:期间不响应 WASD/鼠标朝向,只走 dodge 速度
	if is_dodging:
		_tick_dodge(delta)
		return

	_update_camera_ref()
	_face_mouse()
	_handle_movement(delta)

func _update_camera_ref() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()

func _handle_movement(_delta: float) -> void:
	if is_frozen or Input.is_action_pressed("force_stand"):
		velocity.x = 0.0
		velocity.z = 0.0
		is_moving = false
		move_and_slide()
		return

	var input_vec: Vector2 = _get_movement_input_2d()
	if input_vec.length() > 0.001:
		is_moving = true
	else:
		is_moving = false

	velocity.x = input_vec.x * SPEED
	velocity.z = input_vec.y * SPEED
	# 顶视图,无重力。
	move_and_slide()

func _get_movement_input_2d() -> Vector2:
	var v: Vector2 = Vector2.ZERO
	v.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	v.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	if v.length() > 0.001:
		v = v.normalized()
	return v

func _face_mouse() -> void:
	var aim_point: Vector3 = _get_mouse_ground_point()
	var to_target: Vector3 = aim_point - global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		look_at(global_position + _last_forward, Vector3.UP)
		return
	var forward: Vector3 = to_target.normalized()
	_last_forward = forward
	look_at(global_position + forward, Vector3.UP)

func _get_mouse_ground_point() -> Vector3:
	if _camera == null or not is_instance_valid(_camera):
		return global_position + _last_forward
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = _camera.project_ray_origin(mouse_pos)
	var normal: Vector3 = _camera.project_ray_normal(mouse_pos)
	var hit = _ground_plane.intersects_ray(origin, normal)
	if hit == null:
		return global_position + _last_forward
	return hit

# ── 公共 API:朝向/出生点 ──────────────────────────
func get_forward() -> Vector3:
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return _last_forward
	return fwd.normalized()

func get_arrow_spawn_position() -> Vector3:
	if is_instance_valid(arrow_spawn_point):
		return arrow_spawn_point.global_position
	return global_position + Vector3(0, 1.0, 0)

# 供 SkillExecutor 翻滚技能查询移动输入方向(优先 WASD 输入,无输入则面前方向)
func get_movement_input_direction() -> Vector3:
	var v2: Vector2 = _get_movement_input_2d()
	if v2.length() > 0.001:
		return Vector3(v2.x, 0.0, v2.y)
	# 没移动输入,用当前面向(鼠标方向)
	return get_forward()

# ── 翻滚(供 SkillExecutor._execute_movement 调用)──
# direction 应为水平单位向量;期间无敌 + 穿怪(玩家本来就不与敌人 layer 碰撞,所以已天然穿怪)
func dodge(direction: Vector3, distance: float, duration: float) -> bool:
	if is_dead or is_dodging:
		return false
	var d: Vector3 = direction
	d.y = 0.0
	if d.length() < 0.001:
		d = get_forward()
	if d.length() < 0.001 or distance <= 0.0 or duration <= 0.0:
		return false
	d = d.normalized()
	is_dodging = true
	is_invulnerable = true
	_dodge_timer = duration
	_dodge_velocity = d * (distance / duration)  # 匀速,duration 内移动 distance
	# 翻滚朝向锁死到位移方向
	look_at(global_position + d, Vector3.UP)
	_last_forward = d
	dodge_started.emit(d, duration)
	return true

func _tick_dodge(delta: float) -> void:
	_dodge_timer -= delta
	if _dodge_timer <= 0.0:
		_end_dodge()
		return
	velocity = _dodge_velocity
	move_and_slide()

func _end_dodge() -> void:
	is_dodging = false
	is_invulnerable = false
	_dodge_velocity = Vector3.ZERO
	velocity = Vector3.ZERO
	# 闪避本能:翻滚结束后 2s 内受伤减 20%
	_evade_buffer_timer = EVADE_BUFFER_TIME
	dodge_ended.emit()

# ── 受伤 / 死亡 ─────────────────────────────────────────
func take_damage(amount: int, source = null) -> void:
	if is_dead or is_invulnerable or amount <= 0:
		return
	# 闪避本能:翻滚后 2s 内受伤 -20%
	var actual: int = amount
	if _evade_buffer_timer > 0.0:
		actual = max(1, int(round(float(amount) * (1.0 - EVADE_DAMAGE_REDUCTION))))
	current_health = clamp(current_health - actual, 0, max_health)
	health_changed.emit(current_health, max_health)
	var cm = get_node_or_null("/root/CombatManager")
	if cm != null:
		cm.player_damaged.emit(actual, source)
	if current_health <= 0:
		_die()

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	player_died.emit()
