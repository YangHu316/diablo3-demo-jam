extends CharacterBody3D

# EnemyZombie: stationary target. Flash white on hit, scale to 0 on death.

signal died(enemy)

@export var max_health: int = 80

var current_health: int = 80
var is_dying: bool = false

const FLASH_COLOR: Color = Color(1, 1, 1, 1)
const FLASH_DURATION: float = 0.1
const DEATH_DURATION: float = 0.35

@onready var body_mesh: MeshInstance3D = $BodyMesh

var _base_color: Color = Color(0.827, 0.184, 0.184, 1)
var _material: StandardMaterial3D = null
var _flash_tween: Tween = null

func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	_setup_unique_material()

func _setup_unique_material() -> void:
	if not is_instance_valid(body_mesh):
		return
	var mat = body_mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		# Ensure unique per-instance material.
		var dup: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
		_material = dup
		body_mesh.set_surface_override_material(0, _material)
		_base_color = _material.albedo_color
	else:
		_material = StandardMaterial3D.new()
		_material.albedo_color = _base_color
		body_mesh.set_surface_override_material(0, _material)

func take_damage(amount: int, source = null) -> void:
	if is_dying or current_health <= 0 or amount <= 0:
		return
	current_health = clamp(current_health - amount, 0, max_health)
	_flash_white()
	if current_health <= 0:
		_die(source, amount)

func _flash_white() -> void:
	if _material == null:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_material.albedo_color = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(_material, "albedo_color", _base_color, FLASH_DURATION)

func _die(source, overkill: int) -> void:
	if is_dying:
		return
	is_dying = true
	var cm = get_node_or_null("/root/CombatManager")
	if cm != null:
		var kill_dir: Vector3 = Vector3.FORWARD
		if source != null and source is Node3D and is_instance_valid(source):
			var d: Vector3 = global_position - (source as Node3D).global_position
			d.y = 0.0
			if d.length() > 0.001:
				kill_dir = d.normalized()
		cm.enemy_killed.emit(self, source, overkill, kill_dir)
	died.emit(self)
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, DEATH_DURATION)
	tw.tween_callback(Callable(self, "queue_free"))
