extends Camera3D

# Top-down camera: smooth follow + shake/push hooks.

@export var follow_speed: float = 5.0
@export var height: float = 12.0
@export var pitch_deg: float = 55.0

var _target: Node3D = null
var _base_offset: Vector3 = Vector3.ZERO
var _shake_offset: Vector3 = Vector3.ZERO
var _push_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	# Compute base offset from pitch + height (angle below horizon).
	var pitch_rad: float = deg_to_rad(pitch_deg)
	var horiz: float = height / tan(pitch_rad)
	_base_offset = Vector3(0, height, horiz)
	rotation_degrees = Vector3(-pitch_deg, 0, 0)
	# Find player in scene after one frame.
	call_deferred("_acquire_target")

func _acquire_target() -> void:
	var players: Array = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_target = players[0]

func _process(delta: float) -> void:
	if not is_instance_valid(_target):
		_acquire_target()
		return
	var desired: Vector3 = _target.global_position + _base_offset + _push_offset + _shake_offset
	global_position = global_position.lerp(desired, clamp(follow_speed * delta, 0.0, 1.0))

func apply_shake(intensity: float, duration: float) -> void:
	var tw: Tween = create_tween()
	var dir: Vector3 = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * intensity
	tw.tween_property(self, "_shake_offset", dir, duration * 0.5)
	tw.tween_property(self, "_shake_offset", Vector3.ZERO, duration * 0.5)

func push_toward(target_pos: Vector3, amount: float, duration: float) -> void:
	if not is_instance_valid(_target):
		return
	var dir: Vector3 = (target_pos - _target.global_position)
	dir.y = 0.0
	if dir.length() < 0.001:
		return
	var push: Vector3 = dir.normalized() * amount
	var tw: Tween = create_tween()
	tw.tween_property(self, "_push_offset", push, duration * 0.4)
	tw.tween_property(self, "_push_offset", Vector3.ZERO, duration * 0.6)
