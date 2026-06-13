extends Area3D

# Arrow: straight-line projectile, hits enemies group for damage.

const SPEED: float = 30.0
const MAX_DISTANCE: float = 40.0
const DAMAGE: int = 25

var _direction: Vector3 = Vector3.FORWARD
var _travelled: float = 0.0
var _consumed: bool = false

func _ready() -> void:
	# Forward derived from look_at by spawner; use -global_basis.z.
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.001:
		_direction = fwd.normalized()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)

func set_direction(dir: Vector3) -> void:
	var d: Vector3 = dir
	d.y = 0.0
	if d.length() > 0.001:
		_direction = d.normalized()

func _physics_process(delta: float) -> void:
	if _consumed:
		return
	var step: float = SPEED * delta
	global_position += _direction * step
	_travelled += step
	if _travelled >= MAX_DISTANCE:
		_consumed = true
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _consumed:
		return
	if not is_instance_valid(body):
		return
	if body.is_in_group("enemies"):
		_apply_hit(body)

func _on_area_entered(area: Area3D) -> void:
	if _consumed:
		return
	if not is_instance_valid(area):
		return
	if area.is_in_group("enemies"):
		_apply_hit(area)

func _apply_hit(target: Node) -> void:
	if _consumed:
		return
	if not is_instance_valid(target):
		return
	_consumed = true
	if target.has_method("take_damage"):
		target.take_damage(DAMAGE, self)
	var cm = get_node_or_null("/root/CombatManager")
	if cm != null and is_instance_valid(target):
		var hit_pos: Vector3 = global_position
		cm.hit_landed.emit(self, target, DAMAGE, false, "physical", hit_pos, _direction)
	queue_free()
