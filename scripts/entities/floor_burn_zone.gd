extends Area3D

# floor_burn_zone.gd — 屠夫烧地板单象限版本(策划 03 §6.3 简化)。
# V3.0 爽快版:WARNING(2s 红光预警,无伤)→ BURNING(6s 燃烧,玩家在内每 0.5s 掉 max_hp×2%,即 ~4%/s)→ 自毁。
# 玩家进 / 出 zone 由 body_entered / body_exited 跟踪。

@export var radius: float = 4.0
@export var warning_duration: float = 2.0
@export var burning_duration: float = 6.0
@export var damage_tick_interval: float = 0.5
@export var damage_pct_per_tick: float = 0.02  # V3.0 爽快版: 2%/tick × 2 tick/s = 4%/s

enum Phase { WARNING, BURNING, DONE }
var _phase: int = Phase.WARNING
var _phase_timer: float = 0.0
var _tick_timer: float = 0.0
var _player_inside: Node = null

@onready var mesh_inst: MeshInstance3D = $MeshInstance3D if has_node("MeshInstance3D") else null
@onready var collision: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null

var _mat: StandardMaterial3D = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_phase = Phase.WARNING
	_phase_timer = warning_duration
	_apply_radius()
	_init_material()
	_set_visual_warning()

func _apply_radius() -> void:
	# 把 mesh + collision shape 的尺寸调成 export 的 radius
	if mesh_inst != null and mesh_inst.mesh is CylinderMesh:
		var cm: CylinderMesh = mesh_inst.mesh as CylinderMesh
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = 0.05
	if collision != null and collision.shape is CylinderShape3D:
		var cs: CylinderShape3D = collision.shape as CylinderShape3D
		cs.radius = radius
		cs.height = 0.5

func _init_material() -> void:
	if mesh_inst == null or mesh_inst.mesh == null:
		return
	# 复制材质保证每实例独立
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

func _set_visual_warning() -> void:
	if _mat == null:
		return
	# 警示阶段:橙红半透,边缘脉动,不伤(强烈高光提示)
	_mat.albedo_color = Color(1.0, 0.4, 0.15, 0.55)
	_mat.emission = Color(1.0, 0.35, 0.05, 1.0)
	_mat.emission_energy_multiplier = 3.0

func _set_visual_burning() -> void:
	if _mat == null:
		return
	# 燃烧阶段:深橙红 + 极高 emission
	_mat.albedo_color = Color(1.0, 0.55, 0.1, 0.75)
	_mat.emission = Color(1.0, 0.55, 0.08, 1.0)
	_mat.emission_energy_multiplier = 5.5

func _process(delta: float) -> void:
	if _phase == Phase.DONE:
		return
	_phase_timer -= delta
	if _phase == Phase.WARNING:
		# 简单脉动:emission 强度跟着时间正弦波动,提示倒计时
		if _mat != null:
			var pulse: float = 1.0 + 0.5 * sin(Time.get_ticks_msec() / 100.0)
			_mat.emission_energy_multiplier = 3.0 * pulse
		if _phase_timer <= 0.0:
			_phase = Phase.BURNING
			_phase_timer = burning_duration
			_tick_timer = 0.0
			_set_visual_burning()
	elif _phase == Phase.BURNING:
		# 持续伤害(玩家在内时每 tick 掉血)
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			_tick_timer = damage_tick_interval
			_apply_tick_damage()
		if _phase_timer <= 0.0:
			_phase = Phase.DONE
			# 淡出 + 自毁
			if _mat != null:
				var tw: Tween = create_tween()
				tw.tween_property(_mat, "albedo_color:a", 0.0, 0.3)
				tw.tween_callback(Callable(self, "queue_free"))
			else:
				queue_free()

func _apply_tick_damage() -> void:
	if _player_inside == null or not is_instance_valid(_player_inside):
		return
	if not ("max_health" in _player_inside) or not _player_inside.has_method("take_damage"):
		return
	var max_hp: int = int(_player_inside.max_health)
	var dmg: int = int(round(float(max_hp) * damage_pct_per_tick))
	if dmg <= 0:
		return
	_player_inside.take_damage(dmg, self)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_inside = body

func _on_body_exited(body: Node) -> void:
	if body == _player_inside:
		_player_inside = null
