extends Node

# 监听 SkillSlotManager.skill_activated,按 SkillData.skill_type 分发执行。
# 挂在 Player 子节点。需要 player 是 Node3D,且有 ArrowSpawnPoint 子节点。

const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")

const ARROW_SCENE_PATH: String = "res://scenes/projectiles/arrow.tscn"

# SkillType 枚举值(与 skill_data.gd 中 SkillType 保持同步)
const TYPE_PROJECTILE: int = 0
const TYPE_MOVEMENT: int = 1
const TYPE_SUMMON: int = 2
const TYPE_MELEE: int = 3
const TYPE_CHANNEL: int = 4

@export var slot_manager_path: NodePath = NodePath("../SkillSlotManager")
@export var arrow_spawn_point_path: NodePath = NodePath("../ArrowSpawnPoint")

var _arrow_scene: PackedScene = null
var _player: Node3D = null
var _spawn_point: Node3D = null
var _slot_manager: Node = null

# ── 引导(CHANNEL)状态 ─────────────────────────────
var _channeling_slot: int = -1
var _channel_skill: Resource = null
var _channel_tick_timer: float = 0.0
var _channel_focus_acc: float = 0.0  # 累积应扣专注(每帧 += per_sec*delta,够 1 即扣 1)

func _ready() -> void:
	_arrow_scene = load(ARROW_SCENE_PATH)
	var p: Node = get_parent()
	if p is Node3D:
		_player = p
	else:
		push_error("SkillExecutor: parent is not Node3D")
	_spawn_point = get_node_or_null(arrow_spawn_point_path) as Node3D
	_slot_manager = get_node_or_null(slot_manager_path)
	if _slot_manager != null:
		_slot_manager.skill_activated.connect(_on_skill_activated)
		# V3.0:引导技能信号
		if _slot_manager.has_signal("channel_started"):
			_slot_manager.channel_started.connect(_on_channel_started)
		if _slot_manager.has_signal("channel_stopped"):
			_slot_manager.channel_stopped.connect(_on_channel_stopped)
	else:
		push_error("SkillExecutor: SkillSlotManager not found at %s" % slot_manager_path)

	# V3.0:面板锁死,不再接系统组装备聚合(Inventory.stats_changed)。
	# DamageCalculator 直接使用 player_loadout.csv 锁死值,装备只换观感不改战斗数值。

# 兼容老接口:如有外部直接调用,保留空实现(V3.0 面板已锁死)。
func _on_stats_changed(_total_stats: Dictionary) -> void:
	pass

# sd 期望是 SkillData 资源
func _on_skill_activated(slot_index: int, sd: Resource) -> void:
	if sd == null:
		return
	var stype: int = int(sd.skill_type)
	match stype:
		TYPE_PROJECTILE:
			_execute_projectile(sd, slot_index)
		TYPE_MOVEMENT:
			_execute_movement(sd)
		TYPE_SUMMON:
			_execute_summon(sd)
		TYPE_MELEE:
			_execute_melee(sd)
		_:
			push_warning("SkillExecutor: unhandled skill_type %s for %s" % [stype, sd.skill_id])

# ── 引导(CHANNEL)─────────────────────────────────────
# 由 slot_manager.channel_started 触发,_process 每帧 tick;松开/专注耗尽 channel_stopped 触发停止
func _on_channel_started(slot: int, sd: Resource) -> void:
	if sd == null:
		return
	_channeling_slot = slot
	_channel_skill = sd
	_channel_tick_timer = 0.0  # 立即放第一轮
	_channel_focus_acc = 0.0
	# 通知 player 进引导态(50% 移速,不 freeze)
	if _player != null and _player.has_method("set_channeling"):
		_player.set_channeling(true, float(sd.channel_movement_mult))

func _on_channel_stopped(slot: int, _sd: Resource) -> void:
	if _channeling_slot != slot:
		return
	_channeling_slot = -1
	_channel_skill = null
	_channel_tick_timer = 0.0
	_channel_focus_acc = 0.0
	if _player != null and _player.has_method("set_channeling"):
		_player.set_channeling(false, 1.0)

func _process(delta: float) -> void:
	if _channel_skill == null or _channeling_slot < 0:
		return
	# 1) 持续耗专注(每秒 channel_focus_per_sec)
	var per_sec: float = float(_channel_skill.channel_focus_per_sec)
	if per_sec > 0.0:
		_channel_focus_acc += per_sec * delta
		if _channel_focus_acc >= 1.0:
			var to_consume: float = floor(_channel_focus_acc)
			_channel_focus_acc -= to_consume
			var fr: Node = get_node_or_null("/root/FocusResource")
			if fr != null and not fr.consume(to_consume):
				# 专注耗尽 → 强行停掉引导
				if _slot_manager != null and _slot_manager.has_method("stop_channel_external"):
					_slot_manager.stop_channel_external(_channeling_slot)
				return
	# 2) tick 命中
	_channel_tick_timer -= delta
	if _channel_tick_timer <= 0.0:
		_channel_tick_timer = float(_channel_skill.channel_tick_interval)
		_emit_channel_tick(_channel_skill)

# 一轮 tick:在玩家脚下做 360° 范围伤害 + 视觉 N 支箭从中心向外飞
func _emit_channel_tick(sd: Resource) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center: Vector3 = _player.global_position
	var radius: float = float(sd.channel_radius)
	# 命中:范围内每个敌人一次伤害(独立暴击卷点)
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var dist: float = (e as Node3D).global_position.distance_to(center)
		if dist > radius:
			continue
		if not e.has_method("take_damage"):
			continue
		var hit: Dictionary = DamageCalculator.compute(sd)
		var dmg: int = int(hit.get("damage", 0))
		var is_crit: bool = bool(hit.get("is_crit", false))
		e.take_damage(dmg, _player)
		# 飘字 + hit_landed
		var pool: Node = get_node_or_null("/root/DamageNumberPool")
		if pool != null and pool.has_method("show_damage"):
			pool.show_damage((e as Node3D).global_position + Vector3(0, 1.6, 0), dmg, is_crit)
		var cm: Node = get_node_or_null("/root/CombatManager")
		if cm != null and cm.has_signal("hit_landed"):
			var dir: Vector3 = ((e as Node3D).global_position - center).normalized()
			cm.hit_landed.emit(_player, e, dmg, is_crit, String(sd.element), (e as Node3D).global_position, dir)
	# 视觉:N 支箭从玩家上方往四周外飞(纯观感,不参与伤害)
	_spawn_storm_arrows(center, radius, int(sd.channel_projectiles_per_tick))

func _spawn_storm_arrows(center: Vector3, radius: float, count: int) -> void:
	if _arrow_scene == null:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var spawn_pos: Vector3 = center + Vector3(0, 1.4, 0)
	var n: int = max(4, count)
	for i in range(n):
		var angle: float = (float(i) / float(n)) * TAU
		var dir: Vector3 = Vector3(cos(angle), 0.0, sin(angle))
		var arrow: Node = _arrow_scene.instantiate()
		if arrow == null:
			continue
		scene_root.add_child(arrow)
		if arrow is Node3D:
			(arrow as Node3D).global_position = spawn_pos
			(arrow as Node3D).look_at(spawn_pos + dir, Vector3.UP)
		# 视觉箭:不打人(伤害已由上面 enemies 群组直接计算),寿命 = radius/speed
		if arrow.has_method("set_direction"):
			arrow.set_direction(dir)
		# 让箭只飞 radius 距离就消失(arrow.gd 默认有 lifetime 字段)
		if "lifetime" in arrow:
			arrow.lifetime = max(0.2, radius / 18.0)
		if "is_visual_only" in arrow:
			arrow.is_visual_only = true

# ── 射击类 ─────────────────────────────────────────────
# slot_index == 0(LMB 利箭)用玩家 basis(玩家追打时已 look_at 锁敌人);
# slot_index >= 1(RMB/Q/E)用光标方向(D3 经典:朝光标施法)。
func _execute_projectile(sd: Resource, slot_index: int = -1) -> void:
	if _arrow_scene == null or _player == null:
		return
	var fwd: Vector3
	if slot_index >= 1 and _player.has_method("get_aim_direction"):
		fwd = _player.get_aim_direction()
	else:
		fwd = -_player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	fwd = fwd.normalized()

	var spawn_pos: Vector3
	if _spawn_point != null and is_instance_valid(_spawn_point):
		spawn_pos = _spawn_point.global_position
	else:
		spawn_pos = _player.global_position + Vector3(0, 1.0, 0)

	var count: int = max(1, int(sd.projectile_count))
	var spread: float = float(sd.projectile_spread_angle)
	var scene_root: Node = get_tree().current_scene

	for i in range(count):
		# 每发箭独立计算伤害(各自暴击/不暴击)
		var dmg_info: Dictionary = DamageCalculator.compute(sd)
		var dir: Vector3 = fwd
		if count > 1 and spread > 0.0:
			# 均匀分布 [-spread/2, +spread/2]
			var t: float = float(i) / float(count - 1)
			var angle_deg: float = lerp(-spread * 0.5, spread * 0.5, t)
			dir = fwd.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var arrow: Node = _arrow_scene.instantiate()
		if arrow == null:
			continue
		scene_root.add_child(arrow)
		if arrow is Node3D:
			(arrow as Node3D).global_position = spawn_pos
			(arrow as Node3D).look_at(spawn_pos + dir, Vector3.UP)
		if arrow.has_method("set_direction"):
			arrow.set_direction(dir)
		if arrow.has_method("configure_from_skill"):
			arrow.configure_from_skill(sd, dmg_info)

# ── 位移类(翻滚) ─────────────────────────────────────
func _execute_movement(sd: Resource) -> void:
	if _player == null:
		return
	# 拿位移方向:优先 WASD 输入,无输入则用 player 当前面前方向
	var direction: Vector3 = Vector3.ZERO
	if _player.has_method("get_movement_input_direction"):
		direction = _player.get_movement_input_direction()
	if direction.length() < 0.001 and _player.has_method("get_forward"):
		direction = _player.get_forward()
	direction.y = 0.0
	if direction.length() < 0.001:
		return

	var distance: float = float(sd.move_distance) if "move_distance" in sd else 4.0
	var duration: float = float(sd.move_duration) if "move_duration" in sd else 0.4
	if not _player.has_method("dodge"):
		push_warning("SkillExecutor: player.dodge() missing")
		return
	var ok: bool = _player.dodge(direction, distance, duration)
	if not ok:
		return
	# 取消攻击 CD(让翻滚立即可接射击)
	var cancels: bool = bool(sd.cancels_attack_cooldowns) if "cancels_attack_cooldowns" in sd else false
	if cancels and _slot_manager != null and _slot_manager.has_method("cancel_cooldown"):
		_slot_manager.cancel_cooldown(0)  # LMB 利箭
		_slot_manager.cancel_cooldown(1)  # RMB 多重射击

# ── 召唤类(女武神) ───────────────────────────────────
const SUMMON_GROUP_PREFIX: String = "summon_"

func _execute_summon(sd: Resource) -> void:
	if _player == null:
		return
	var summon_scene: PackedScene = sd.summon_scene if "summon_scene" in sd else null
	if summon_scene == null:
		push_warning("SkillExecutor: summon_scene missing on %s" % sd.skill_id)
		return
	var max_count: int = int(sd.summon_max_count) if "summon_max_count" in sd else 1
	var duration: float = float(sd.summon_duration) if "summon_duration" in sd else 0.0
	var group_name: String = SUMMON_GROUP_PREFIX + String(sd.skill_id)

	# 检查同种召唤物上限,超出移除最旧的(get_nodes_in_group 返回顺序≈添加顺序)
	var existing: Array = get_tree().get_nodes_in_group(group_name)
	while existing.size() >= max_count and not existing.is_empty():
		var oldest: Node = existing[0]
		if is_instance_valid(oldest):
			if oldest.has_method("dismiss"):
				oldest.dismiss()
			else:
				oldest.queue_free()
		existing.remove_at(0)

	# 实例化召唤物
	var summon: Node = summon_scene.instantiate()
	if summon == null:
		return
	# 生命周期注入(在 add_child 之前设,_ready 时已就绪)
	if duration > 0.0 and "lifetime" in summon:
		summon.lifetime = duration
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(summon)
	# 生成位置:玩家面前 1.5m,稍偏左
	if summon is Node3D:
		var fwd: Vector3 = -_player.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.001:
			fwd = fwd.normalized()
		else:
			fwd = Vector3.FORWARD
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		(summon as Node3D).global_position = _player.global_position + fwd * 1.5 + right * 0.4
		# 朝玩家面向方向
		(summon as Node3D).look_at((summon as Node3D).global_position + fwd, Vector3.UP)
	summon.add_to_group(group_name)

# ── 近战类(预留) ───────────────────────────────────────
func _execute_melee(sd: Resource) -> void:
	# 圆形 AOE:在玩家脚下爆发,半径 sd.aoe_radius,伤害用 DamageCalculator。
	# 用例:女武神之击(原召唤大招,改为一次性 AOE 伤害)。
	if _player == null or not is_instance_valid(_player):
		return
	var radius: float = float(sd.aoe_radius) if "aoe_radius" in sd and sd.aoe_radius > 0.0 else 6.0
	var center: Vector3 = _player.global_position
	# 用 DamageCalculator 算一次伤害(吃暴击 / 武器均伤 / 敏捷),全场内敌人共享同一卷点
	var DC = preload("res://scripts/skills/damage_calculator.gd")
	var hit: Dictionary = DC.compute(sd)
	var dmg: int = int(hit.get("damage", 0))
	var is_crit: bool = bool(hit.get("is_crit", false))
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var hit_count: int = 0
	for e in enemies:
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		var dist: float = (e as Node3D).global_position.distance_to(center)
		if dist > radius:
			continue
		if not e.has_method("take_damage"):
			continue
		e.take_damage(dmg, _player)
		hit_count += 1
		# 飘字 + 命中信号
		var pool: Node = get_node_or_null("/root/DamageNumberPool")
		if pool != null and pool.has_method("show_damage"):
			var p: Vector3 = (e as Node3D).global_position + Vector3(0, 1.6, 0)
			pool.show_damage(p, dmg, is_crit)
		var cm: Node = get_node_or_null("/root/CombatManager")
		if cm != null and cm.has_signal("hit_landed"):
			var dir: Vector3 = ((e as Node3D).global_position - center).normalized()
			cm.hit_landed.emit(_player, e, dmg, is_crit, String(sd.element), (e as Node3D).global_position, dir)
	# 视觉:黄色光环 + 短屏震
	_spawn_blast_ring(center, radius)
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("_trigger_screen_shake"):
		cjm._trigger_screen_shake()

func _spawn_blast_ring(center: Vector3, radius: float) -> void:
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.95, 0.4, 0.85)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.85, 0.2, 1.0)
	ring_mat.emission_energy_multiplier = 5.0
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = max(0.1, radius - 0.3)
	torus.outer_radius = radius
	torus.ring_segments = 48
	torus.material = ring_mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = torus
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(mi)
	mi.global_position = center + Vector3(0, 0.05, 0)
	# 0.4s 由小变大 + 淡出
	mi.scale = Vector3.ONE * 0.3
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring_mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_property(ring_mat, "emission_energy_multiplier", 0.0, 0.4)
	tw.chain().tween_callback(Callable(mi, "queue_free"))
