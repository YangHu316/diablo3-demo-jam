extends CharacterBody3D

# Player: WASD movement, mouse-aim turn, left-click arrow shoot.

signal health_changed(current: int, max_hp: int)
signal player_died()

const SPEED: float = 7.0
const ATTACK_COOLDOWN: float = 0.3
const ARROW_SCENE_PATH: String = "res://scenes/projectiles/arrow.tscn"

@export var max_health: int = 200

var current_health: int = 200
var is_moving: bool = false
var is_attacking: bool = false
var is_invulnerable: bool = false
var is_frozen: bool = false
var is_dead: bool = false

var _attack_timer: float = 0.0
var _last_forward: Vector3 = Vector3.FORWARD
var _arrow_scene: PackedScene = null
var _camera: Camera3D = null
var _ground_plane: Plane = Plane(Vector3.UP, 0.0)

@onready var arrow_spawn_point: Marker3D = $ArrowSpawnPoint

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	_arrow_scene = load(ARROW_SCENE_PATH)
	health_changed.emit(current_health, max_health)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if _attack_timer > 0.0:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			is_attacking = false

	_update_camera_ref()
	_face_mouse()
	_handle_movement(delta)
	_handle_attack()

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

	var input_vec: Vector2 = Vector2.ZERO
	input_vec.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	input_vec.y = Input.get_action_strength("move_down") - Input.get_action_strength("move_up")
	if input_vec.length() > 0.001:
		input_vec = input_vec.normalized()
		is_moving = true
	else:
		is_moving = false

	velocity.x = input_vec.x * SPEED
	velocity.z = input_vec.y * SPEED
	# No gravity in this stage (top-down flat arena).
	move_and_slide()

func _face_mouse() -> void:
	var aim_point: Vector3 = _get_mouse_ground_point()
	var to_target: Vector3 = aim_point - global_position
	to_target.y = 0.0
	if to_target.length() < 0.01:
		# Fallback: keep last frame forward.
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
		# Fallback to last frame forward projection.
		return global_position + _last_forward
	return hit

func _handle_attack() -> void:
	if is_attacking or _attack_timer > 0.0:
		return
	if Input.is_action_pressed("attack_primary"):
		_fire_arrow()

func _fire_arrow() -> void:
	if _arrow_scene == null:
		return
	var arrow: Node = _arrow_scene.instantiate()
	if arrow == null:
		return
	get_tree().current_scene.add_child(arrow)
	var spawn_pos: Vector3 = arrow_spawn_point.global_position if is_instance_valid(arrow_spawn_point) else global_position + Vector3(0, 1.0, 0)
	if arrow is Node3D:
		(arrow as Node3D).global_position = spawn_pos
		# Align arrow forward to player forward.
		var fwd: Vector3 = -global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() < 0.001:
			fwd = _last_forward
		fwd = fwd.normalized()
		(arrow as Node3D).look_at(spawn_pos + fwd, Vector3.UP)
		if arrow.has_method("set_direction"):
			arrow.set_direction(fwd)
	is_attacking = true
	_attack_timer = ATTACK_COOLDOWN

func take_damage(amount: int, source = null) -> void:
	if is_dead or is_invulnerable or amount <= 0:
		return
	current_health = clamp(current_health - amount, 0, max_health)
	health_changed.emit(current_health, max_health)
	var cm = get_node_or_null("/root/CombatManager")
	if cm != null:
		cm.player_damaged.emit(amount, source)
	if current_health <= 0:
		_die()

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	player_died.emit()
