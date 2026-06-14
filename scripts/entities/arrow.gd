extends Area3D

# Arrow: 直线投射物。伤害/穿透/回蓝/AOE/状态 由 SkillExecutor 通过 configure_from_skill 注入。

const SPEED: float = 30.0
const MAX_DISTANCE: float = 40.0
const DEFAULT_DAMAGE: int = 25

# Runtime properties (由 configure_from_skill 注入,默认值用于直接 spawn 调试)
var damage: int = DEFAULT_DAMAGE
var is_crit: bool = false
var element: String = "physical"
var focus_gain_on_hit: float = 0.0
var can_penetrate: bool = false
# 命中范围扩展(冰冻箭等)
var aoe_radius: float = 0.0       # >0 时命中后做范围状态附加
var status_effect: String = ""     # frost / burn / ...
var status_duration: float = 0.0
# 纯观感箭(箭雨风暴):不打人,只飞固定 lifetime 后销毁
var is_visual_only: bool = false
var lifetime: float = 0.0  # >0 时启用计时销毁(代替 MAX_DISTANCE)
var _life_timer: float = 0.0

var _direction: Vector3 = Vector3.FORWARD
var _travelled: float = 0.0
var _consumed: bool = false
var _hit_targets: Array = []  # 穿透/AOE 去重,避免反复伤害/上状态

func _ready() -> void:
	# Forward 由 spawner 通过 look_at 设置;以 -basis.z 为初始方向。
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() > 0.001:
		_direction = fwd.normalized()
	# 注:body_entered / area_entered 已在 arrow.tscn 通过编辑器连接,无需重复 connect。

func set_direction(dir: Vector3) -> void:
	var d: Vector3 = dir
	d.y = 0.0
	if d.length() > 0.001:
		_direction = d.normalized()

# 由 SkillExecutor 调用:把技能数据 + 已计算的伤害打包注入箭矢。
func configure_from_skill(sd, dmg_info: Dictionary) -> void:
	if sd == null:
		return
	damage = int(dmg_info.get("damage", DEFAULT_DAMAGE))
	is_crit = bool(dmg_info.get("is_crit", false))
	element = String(dmg_info.get("element", "physical"))
	focus_gain_on_hit = float(sd.focus_gain_on_hit)
	can_penetrate = bool(sd.can_penetrate)
	# 新字段(SkillData 的可选字段,duck typing)
	aoe_radius = float(sd.aoe_radius) if "aoe_radius" in sd else 0.0
	status_effect = String(sd.status_effect) if "status_effect" in sd else ""
	status_duration = float(sd.status_duration) if "status_duration" in sd else 0.0
	# V3.2:按 element 给箭矢 + 拖尾染色(冰箭蓝、火箭橙、毒箭绿…)
	_apply_element_tint(element)

# 按 element 给箭头染色 / 替换尾迹。physical 不动,保留默认观感。
func _apply_element_tint(elem: String) -> void:
	if elem == "" or elem == "physical":
		return
	# V3.5:用户反馈"冰箭不要火光" — 任何非物理 element,直接干掉默认 mprojectile 火焰拖尾。
	# 不再加光源 / 光晕(那些反而看起来像火),只把箭模型 mesh 本身染成对应元素色。
	var trail: Node = get_node_or_null("TrailVFX")
	if trail != null:
		trail.queue_free()
	var tint: Color
	var emit: Color
	match elem:
		"frost":
			tint = Color(0.55, 0.85, 1.0, 1.0)
			emit = Color(0.45, 0.85, 1.0, 1.0)
		"fire":
			tint = Color(1.0, 0.55, 0.2, 1.0)
			emit = Color(1.0, 0.4, 0.1, 1.0)
		"poison":
			tint = Color(0.55, 1.0, 0.4, 1.0)
			emit = Color(0.4, 1.0, 0.3, 1.0)
		_:
			return
	var pivot: Node = get_node_or_null("ModelPivot")
	if pivot != null:
		_tint_meshes(pivot, tint, emit)
		# V3.7:冰箭整体放大,但比上一版克制(1.8x → 1.3x)
		if elem == "frost" and pivot is Node3D:
			(pivot as Node3D).scale = (pivot as Node3D).scale * 1.3

func _tint_meshes(node: Node, tint: Color, emit: Color) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		# V3.3:用 material_overlay 在原材质之上叠加发光色 → 保留 Synty 贴图,
		# 同时让箭整体看起来"被冰/火笼罩"。surface_override 之前不生效是因为
		# FBX 内部多 surface 且材质来自 mesh 资源本身,改 surface_override(0) 只能盖住第一个面。
		var overlay: StandardMaterial3D = StandardMaterial3D.new()
		# 半透明 albedo 让原色透出
		overlay.albedo_color = Color(tint.r, tint.g, tint.b, 0.55)
		overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		overlay.emission_enabled = true
		overlay.emission = emit
		overlay.emission_energy_multiplier = 2.0
		overlay.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_overlay = overlay
	for c in node.get_children():
		_tint_meshes(c, tint, emit)

func _tint_particles(node: Node, tint: Color) -> void:
	# GPUParticles3D 通过 ParticleProcessMaterial.color 染色;CPUParticles3D 直接 .color。
	if node is GPUParticles3D:
		var p: GPUParticles3D = node
		var pm: Material = p.process_material
		if pm is ParticleProcessMaterial:
			# duplicate 避免影响其他箭实例(资源共享时)
			var pm_copy: ParticleProcessMaterial = (pm as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
			pm_copy.color = tint
			p.process_material = pm_copy
	elif node is CPUParticles3D:
		(node as CPUParticles3D).color = tint
	for c in node.get_children():
		_tint_particles(c, tint)

func _physics_process(delta: float) -> void:
	if _consumed:
		return
	var step: float = SPEED * delta
	global_position += _direction * step
	_travelled += step
	if lifetime > 0.0:
		_life_timer += delta
		if _life_timer >= lifetime:
			_consumed = true
			queue_free()
			return
	if _travelled >= MAX_DISTANCE:
		_consumed = true
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _consumed or is_visual_only:
		return
	if not is_instance_valid(body):
		return
	if body.is_in_group("enemies"):
		_apply_hit(body)

func _on_area_entered(area: Area3D) -> void:
	if _consumed or is_visual_only:
		return
	if not is_instance_valid(area):
		return
	if area.is_in_group("enemies"):
		_apply_hit(area)

func _apply_hit(target: Node) -> void:
	if not is_instance_valid(target):
		return
	# 穿透时去重,避免反复伤害同一个敌人
	if target in _hit_targets:
		return
	_hit_targets.append(target)

	# 主目标伤害
	if target.has_method("take_damage"):
		target.take_damage(damage, self)

	# SFX 命中肉感
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("arrow_hit", global_position, -3.0, 0.1)

	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null:
		var hit_pos: Vector3 = global_position
		cm.hit_landed.emit(self, target, damage, is_crit, element, hit_pos, _direction)

	# 命中回蓝
	if focus_gain_on_hit > 0.0:
		var fr: Node = get_node_or_null("/root/FocusResource")
		if fr != null:
			fr.gain(focus_gain_on_hit)

	# 主目标状态(冰冻箭主目标也吃 freeze)
	if status_effect != "" and status_duration > 0.0 and target.has_method("apply_status"):
		target.apply_status(status_effect, status_duration)

	# AOE 范围状态(冰冻箭 3m 爆裂)
	if aoe_radius > 0.0:
		_apply_aoe(target)
		_spawn_aoe_visual()

	# 不穿透则消耗箭矢
	if not can_penetrate:
		_consumed = true
		queue_free()

# 命中点周围 aoe_radius 内,所有敌人(除主目标)上同样的状态。
# 注:AOE 不再造成主伤害(冰冻箭单体伤,范围只是冻住),后续若要"伤害+冻"可以加 aoe_damage_ratio。
func _apply_aoe(primary_target: Node) -> void:
	if status_effect == "" or status_duration <= 0.0:
		return
	var center: Vector3 = global_position
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e == primary_target:
			continue
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var dist: float = (e as Node3D).global_position.distance_to(center)
		if dist > aoe_radius:
			continue
		if e.has_method("apply_status"):
			e.apply_status(status_effect, status_duration)

# 占位 VFX:在命中点放一个半透明球,缩放进出 + 淡出,提示玩家 AOE 范围。
func _spawn_aoe_visual() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var ind: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = aoe_radius
	sphere.height = aoe_radius * 2.0
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.7, 1.0, 0.30)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.7, 1.0, 1.0)
	mat.emission_energy_multiplier = 0.6
	sphere.material = mat
	ind.mesh = sphere
	ind.scale = Vector3.ZERO
	scene_root.add_child(ind)
	ind.global_position = global_position
	var tw: Tween = ind.create_tween()
	tw.tween_property(ind, "scale", Vector3.ONE, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ind, "scale", Vector3.ONE * 1.05, 0.10)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.30)
	tw.tween_callback(Callable(ind, "queue_free"))
