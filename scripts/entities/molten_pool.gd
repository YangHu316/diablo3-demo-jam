extends Area3D

# molten_pool.gd — 熔火精英词缀的"地面延爆"(策划 03 §5.1)
# 精英怪死亡 → 1.0s 后在尸体处生成本节点 → 1.5s 红光警示 → 一次爆炸 AOE 伤害 → 自毁
# 只伤玩家,不伤其他敌人

@export var radius: float = 3.0
@export var warning_duration: float = 1.5
@export var explosion_damage: int = 40

enum Phase { WARNING, EXPLODED }
var _phase: int = Phase.WARNING
var _phase_timer: float = 0.0

@onready var mesh_inst: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var collision: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null
var _mat: StandardMaterial3D = null

func _ready() -> void:
	_phase = Phase.WARNING
	_phase_timer = warning_duration
	_apply_radius()
	_init_material()

func _apply_radius() -> void:
	if mesh_inst != null and mesh_inst.mesh is CylinderMesh:
		var cm: CylinderMesh = mesh_inst.mesh as CylinderMesh
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = 0.06
	if collision != null and collision.shape is CylinderShape3D:
		var cs: CylinderShape3D = collision.shape as CylinderShape3D
		cs.radius = radius
		cs.height = 0.5

func _init_material() -> void:
	if mesh_inst == null or mesh_inst.mesh == null:
		return
	var src: Material = mesh_inst.get_active_material(0)
	if src is StandardMaterial3D:
		_mat = (src as StandardMaterial3D).duplicate()
	else:
		_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.emission_enabled = true
	mesh_inst.set_surface_override_material(0, _mat)

func _process(delta: float) -> void:
	if _phase == Phase.EXPLODED:
		return
	_phase_timer -= delta
	# 越接近爆炸,频闪越快
	if _mat != null:
		var t: float = clamp(1.0 - _phase_timer / warning_duration, 0.0, 1.0)
		var pulse: float = 1.0 + 0.6 * sin(Time.get_ticks_msec() / (60.0 + (1.0 - t) * 10.0))
		_mat.emission_energy_multiplier = (2.0 + 4.0 * t) * pulse
		_mat.albedo_color = Color(1.0, 0.5 - 0.3 * t, 0.1, 0.4 + 0.3 * t)
	if _phase_timer <= 0.0:
		_explode()

func _explode() -> void:
	_phase = Phase.EXPLODED
	# 大屏震 + 一次性 AOE 伤害
	for body in get_overlapping_bodies():
		if body.is_in_group("player") and body.has_method("take_damage"):
			body.take_damage(explosion_damage, self)
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("_trigger_screen_shake"):
		cjm._trigger_screen_shake()
	# 爆炸视觉:橙黄强光,快速淡出
	if _mat != null:
		_mat.albedo_color = Color(1.0, 0.85, 0.3, 0.85)
		_mat.emission = Color(1.0, 0.7, 0.2, 1.0)
		_mat.emission_energy_multiplier = 8.0
		var tw: Tween = create_tween()
		tw.tween_property(_mat, "albedo_color:a", 0.0, 0.3)
		tw.tween_property(_mat, "emission_energy_multiplier", 0.0, 0.3)
		tw.tween_callback(Callable(self, "queue_free"))
	else:
		queue_free()
