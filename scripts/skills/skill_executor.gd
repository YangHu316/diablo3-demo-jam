extends Node

# 监听 SkillSlotManager.skill_activated,按 SkillData.skill_type 分发执行。
# 挂在 Player 子节点。需要 player 是 Node3D,且有 ArrowSpawnPoint 子节点。

const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")

const ARROW_SCENE_PATH: String = "res://scenes/projectiles/arrow.tscn"
# V3.2:E 技能视觉 = 5~6 支箭以不同角速度/方向/半径绕主角公转(伤害逻辑不变)
const ORBIT_ARROW_MODEL_PATH: String = "res://assets/PolygonDungeon/Models/FX/SM_Arrow_01.fbx"
const ORBIT_ARROW_TRAIL_PATH: String = "res://assets/MagicVFX/assets/BinbunVFX/magic_projectiles/effects/mprojectile_basic/mprojectile_basic_vfx_01.tscn"

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
# V3.2:绕身公转的箭(数据 = [pivot_node, angular_speed, radius, height, phase])
var _orbit_arrows: Array = []
var _orbit_time: float = 0.0
var _orbit_arrow_scene: PackedScene = null
var _orbit_trail_scene: PackedScene = null
# V3.6:E AOE 边界指引环(细圆环,持续显示直到松手)
var _channel_boundary: MeshInstance3D = null

func _ready() -> void:
	_arrow_scene = load(ARROW_SCENE_PATH)
	_orbit_arrow_scene = load(ORBIT_ARROW_MODEL_PATH)
	_orbit_trail_scene = load(ORBIT_ARROW_TRAIL_PATH)
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
	# V3.2:生成 5~6 支绕身公转的箭(纯视觉,伤害还是 _emit_channel_tick 的 AOE)
	_spawn_orbit_arrows(float(sd.channel_radius))
	# V3.9:用户反馈圈圈不需要,删掉边界环
	# _spawn_channel_boundary(float(sd.channel_radius))
	# SFX:开始引导(咏唱声)
	var sfx_start: Node = get_node_or_null("/root/Sfx")
	if sfx_start != null and sfx_start.has_method("play") and _player is Node3D:
		sfx_start.play("channel_charge", (_player as Node3D).global_position, -2.0, 0.05)

func _on_channel_stopped(slot: int, _sd: Resource) -> void:
	if _channeling_slot != slot:
		return
	_channeling_slot = -1
	_channel_skill = null
	_channel_tick_timer = 0.0
	_channel_focus_acc = 0.0
	if _player != null and _player.has_method("set_channeling"):
		_player.set_channeling(false, 1.0)
	_despawn_orbit_arrows()
	_despawn_channel_boundary()

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
	# 2) 公转箭跟随玩家 + 旋转
	_update_orbit_arrows(delta)
	# 2.5) 边界环跟随玩家
	if _channel_boundary != null and is_instance_valid(_channel_boundary) and _player != null and is_instance_valid(_player):
		_channel_boundary.global_position = (_player as Node3D).global_position + Vector3(0, 0.02, 0)
	# 3) tick 命中
	_channel_tick_timer -= delta
	if _channel_tick_timer <= 0.0:
		_channel_tick_timer = float(_channel_skill.channel_tick_interval)
		_emit_channel_tick(_channel_skill)

# V3.1:一轮 tick = 在玩家脚下 360° 火域 AOE 伤害 + 短促脉冲环视觉
# (废弃了之前每 tick 生成 12 支视觉箭的子弹观感,改为参考王者马可波罗大招的纯 AOE 体验)
func _emit_channel_tick(sd: Resource) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var center: Vector3 = _player.global_position
	var radius: float = float(sd.channel_radius)
	# 命中:范围内每个敌人一次伤害(独立暴击卷点)
	var enemies: Array = EntityRegistry.enemies
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
	# V3.4:删掉一波一波的圆圈涟漪(用户反馈很丑),纯靠公转箭+飘字呈现命中节奏
	# _spawn_channel_pulse(center, radius)

# V3.2:5~6 支箭绕主角公转(伤害不变,纯观感)
# 每支箭参数(angular_speed/radius/height/phase/dir)随机化,看起来更乱更有"魔法围绕"感
func _spawn_orbit_arrows(channel_radius: float) -> void:
	_despawn_orbit_arrows()
	if _orbit_arrow_scene == null or _player == null or not (_player is Node3D):
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	_orbit_time = 0.0
	# V3.4:用户反馈最大半径太小 → 改为基于 channel_radius 的更大区间。
	# channel_radius=6 → r ∈ [3.0, 5.5],最远箭已经接近 AOE 边界,绕得开。
	var r_min: float = max(2.0, channel_radius * 0.5)
	var r_max: float = max(r_min + 1.0, channel_radius * 0.95)
	var n: int = 6   # V3.10:从 12 调回 6;每箭挂 mprojectile VFX(内部多 GPU 粒子),12 支 ≈ 36+ 发射器,低端 GPU 顶不住
	for i in range(n):
		# 用一个 pivot Node3D 作为绕主角的支点(每帧设到玩家位置),
		# 子节点是箭模型,绕 Y 转 angle 后向前推 radius → 公转
		var pivot: Node3D = Node3D.new()
		scene_root.add_child(pivot)
		pivot.global_position = (_player as Node3D).global_position
		# 箭模型(纯视觉,无碰撞)
		var arrow_model: Node = _orbit_arrow_scene.instantiate()
		if arrow_model == null:
			pivot.queue_free()
			continue
		var anchor: Node3D = Node3D.new()  # 用 anchor 控制 z = -radius 让箭离 pivot 一段距离
		pivot.add_child(anchor)
		anchor.add_child(arrow_model)
		# V3.4:加回一条魔法尾迹 — 但用程序化 CPUParticles3D(冰蓝拉丝)替代 mprojectile
		# 火焰拖尾。火粒子是 fire-base 模板很难调出"圣箭"质感,所以自己拼一个简短的
		# 冷光蓝白拖尾,挂在 anchor 上,跟着箭走。
		# V3.7→V3.8:首尾反了,从 Y-90° 翻 180° → Y+90°
		var trail: Node = null
		if _orbit_trail_scene != null:
			trail = _orbit_trail_scene.instantiate()
			if trail != null and trail is Node3D:
				anchor.add_child(trail)
				(trail as Node3D).rotation = Vector3(0, deg_to_rad(90.0), 0)
				(trail as Node3D).scale = Vector3.ONE * 0.5
		# 随机参数(V3.3:速度上调,V3.4:再加一档)
		var ang_speed: float = randf_range(3.0, 5.8)        # rad/s
		if randf() < 0.5:
			ang_speed = -ang_speed                          # 顺/逆时针
		var radius: float = randf_range(r_min, r_max)
		var height: float = randf_range(0.4, 2.2)
		var phase: float = randf() * TAU
		# anchor 位置:相对 pivot 朝 -Z 推 radius,箭尖朝飞行切向(切向在 _update 里 look_at 设)
		anchor.position = Vector3(0, height, -radius)
		_orbit_arrows.append({
			"pivot": pivot,
			"anchor": anchor,
			"speed": ang_speed,
			"radius": radius,
			"height": height,
			"phase": phase,
		})

func _update_orbit_arrows(delta: float) -> void:
	if _orbit_arrows.is_empty():
		return
	_orbit_time += delta
	if _player == null or not is_instance_valid(_player):
		return
	var center: Vector3 = (_player as Node3D).global_position
	for d in _orbit_arrows:
		var pivot: Node3D = d.get("pivot") as Node3D
		var anchor: Node3D = d.get("anchor") as Node3D
		if pivot == null or not is_instance_valid(pivot):
			continue
		# pivot 跟随玩家
		pivot.global_position = center
		# pivot 绕 Y 转 angle = phase + speed * t
		var angle: float = float(d["phase"]) + float(d["speed"]) * _orbit_time
		pivot.rotation = Vector3(0, angle, 0)
		# 让箭尖朝公转切线方向(箭模型在 SM_Arrow_01.fbx 里 +Z 朝箭尖,
		# anchor.position = -Z*radius → 切向 = anchor.basis 关于 pivot 的导数;
		# 在 pivot 局部空间下,半径方向是 -Z,切向 = +X(speed>0 顺时针)或 -X(speed<0)
		# 简单做法:让 anchor 绕 Y 转 ±90° 让箭模型 +Z 对齐切向)
		if anchor != null and is_instance_valid(anchor):
			var sgn: float = 1.0 if float(d["speed"]) >= 0.0 else -1.0
			anchor.rotation = Vector3(0, deg_to_rad(90.0) * sgn, 0)

func _despawn_orbit_arrows() -> void:
	# V3.3:E 一结束箭立刻消失(之前有 0.6s 粒子衰减,用户反馈拖泥带水)
	for d in _orbit_arrows:
		var pivot = d.get("pivot")
		if pivot != null and is_instance_valid(pivot):
			pivot.queue_free()
	_orbit_arrows.clear()

# V3.6:E AOE 边界细环 — 让玩家清楚知道范围,持续显示直到松手
func _spawn_channel_boundary(radius: float) -> void:
	_despawn_channel_boundary()
	var scene_root: Node = get_tree().current_scene
	if scene_root == null or _player == null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.65, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.55, 0.15, 1.0)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = max(0.02, radius - 0.06)   # 极细的环(0.06m 厚)
	torus.outer_radius = radius
	torus.ring_segments = 64
	torus.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = torus
	scene_root.add_child(mi)
	mi.global_position = (_player as Node3D).global_position + Vector3(0, 0.02, 0)
	_channel_boundary = mi

func _despawn_channel_boundary() -> void:
	if _channel_boundary != null and is_instance_valid(_channel_boundary):
		_channel_boundary.queue_free()
	_channel_boundary = null

func _disable_emitters(node: Node) -> void:
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	elif node is CPUParticles3D:
		(node as CPUParticles3D).emitting = false
	for c in node.get_children():
		_disable_emitters(c)

# 每 tick 一次:橙红圆环 0.25s 由小到大扩到 radius,强化"伤害命中节拍"
func _spawn_channel_pulse(center: Vector3, radius: float) -> void:
	var ring_mat: StandardMaterial3D = StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.55, 0.15, 0.85)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.4, 0.1, 1.0)
	ring_mat.emission_energy_multiplier = 6.0
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = max(0.05, radius - 0.25)
	torus.outer_radius = radius
	torus.ring_segments = 56
	torus.material = ring_mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = torus
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(mi)
	mi.global_position = center + Vector3(0, 0.05, 0)
	mi.scale = Vector3.ONE * 0.15
	# tween 绑在 mi 上(独立于玩家移动)
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(ring_mat, "albedo_color:a", 0.0, 0.3)
	tw.tween_property(ring_mat, "emission_energy_multiplier", 0.0, 0.3)
	tw.chain().tween_callback(Callable(mi, "queue_free"))

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
	# SFX:射出(每次开火只播一次,即使 5 箭)
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("arrow_shoot", spawn_pos, -4.0, 0.08)

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
	var existing: Array = get_tree().get_nodes_in_group(group_name)  # 召唤物用专属 group，不能改
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
	var enemies: Array = EntityRegistry.enemies
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
