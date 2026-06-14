extends CharacterBody3D

# Player: 经典 D3 鼠标控制(V3.0,替换 WASD)。
# - LMB 点地: 寻路走过去;按住 = 持续更新目标点。
# - LMB 点敌: 走进利箭射程后由 SkillSlotManager 自动开火;按住 = 持续追打。
# - RMB / 1 / 2 / 3: SkillSlotManager 处理,朝光标方向。
# - Shift(force_stand): 原地站桩,左键朝光标射不移动。
# - 空格(force_move): 朝光标走,无视脚下敌人(经典 D3 Force-Move)。
# - Q(potion): 治疗药水(暂未接 — 留待 P0 后续)。
# - 翻滚由 SkillExecutor._execute_movement 通过 dodge() API 触发(W=朝光标前滚)。

signal health_changed(current: int, max_hp: int)
signal player_died()
signal dodge_started(direction: Vector3, duration: float)
signal dodge_ended()

const SPEED: float = 7.0
const ATTACK_RANGE: float = 18.0  # 利箭有效射程,目标在此范围内即停下射击
const ARRIVE_THRESHOLD: float = 0.2  # 到点判定半径

# 功能塔·加速塔全局乘区 (TowerBuffManager 写: 激活=1+加成, 清除=1.0).
var speed_buff_mult: float = 1.0

# V3.0 锁死玩家面板:HP 8000(策划案 player_loadout.csv 爽快割草版)
@export var max_health: int = 8000

var current_health: int = 8000
var is_moving: bool = false
var is_invulnerable: bool = false
var is_frozen: bool = false
var is_dead: bool = false

# ── 翻滚 ────────────────────────────────────────────
var is_dodging: bool = false
var _dodge_velocity: Vector3 = Vector3.ZERO
var _dodge_timer: float = 0.0

# ── 闪避本能(策划 02 §4.3 b)— V3.0 取消"成长向"被动,留代码不解锁 ──
const EVADE_BUFFER_TIME: float = 2.0
const EVADE_DAMAGE_REDUCTION: float = 0.20
var _evade_buffer_timer: float = 0.0

# ── 鼠标点击控制状态 ───────────────────────────────
var _move_target: Vector3 = Vector3.ZERO
var _has_move_target: bool = false
var _attack_target: Node3D = null

# 给 SkillSlotManager:LMB 现在不再每帧无脑触发,只在 _lmb_attack_armed 为真时才让槽 0 开火。
# 触发条件:Shift 站桩 / 攻击目标在射程内 / (上层判定后置)。
var _lmb_attack_armed: bool = false

# ── 施法急停(D3 手感)──────────────────────────────
# 释放 RMB / Q / W / E 时:急停 → 朝光标施法 → 计时结束自动恢复原移动目标。
# 翻滚(W)走 dodge() 流程,自身覆盖 _physics_process 的移动,所以 freeze 只影响 RMB/Q/E。
const CAST_FREEZE_DURATION: float = 0.18
var _cast_freeze_timer: float = 0.0

# ── 引导(箭雨风暴 E)────────────────────────────────
# 引导期间:不冻结,可移动但移速倍率 _channel_movement_mult(默认 0.5);
# 不触发施法急停(set_channeling 为 true 时 _on_skill_activated 跳过急停)
var _is_channeling: bool = false
var _channel_movement_mult: float = 1.0

var _last_forward: Vector3 = Vector3.FORWARD
var _camera: Camera3D = null
var _ground_plane: Plane = Plane(Vector3.UP, 0.0)
var _slot_manager: Node = null

@onready var arrow_spawn_point: Marker3D = $ArrowSpawnPoint

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	health_changed.emit(current_health, max_health)
	_slot_manager = get_node_or_null("SkillSlotManager")
	if _slot_manager == null:
		_slot_manager = get_node_or_null("../SkillSlotManager")  # 兼容兄弟节点摆放
	# 监听技能激活:非 LMB 技能触发施法急停(原地朝光标释放,然后恢复移动)
	if _slot_manager != null and _slot_manager.has_signal("skill_activated"):
		_slot_manager.skill_activated.connect(_on_skill_activated)

func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# 闪避 buffer 衰减
	if _evade_buffer_timer > 0.0:
		_evade_buffer_timer -= delta

	# 翻滚最高优先级
	if is_dodging:
		_tick_dodge(delta)
		return

	_update_camera_ref()

	# 施法急停:RMB/Q/E 触发后短暂(~0.18s)原地朝光标施法,移动目标保留,结束自动恢复
	if _cast_freeze_timer > 0.0:
		_cast_freeze_timer -= delta
		_face_mouse()
		_stop_horizontal_motion()
		_update_lmb_attack_armed()
		return

	_tick_input_and_movement(delta)
	_update_lmb_attack_armed()

func _update_camera_ref() -> void:
	if _camera == null or not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()

# ── 输入解析 + 移动 ────────────────────────────────
# 优先级:Shift 站桩 > 翻滚(在外层) > force_move > LMB 点击意图 > 当前移动/攻击目标 > 停
func _tick_input_and_movement(delta: float) -> void:
	var shift_held: bool = Input.is_action_pressed("force_stand")
	var force_move_held: bool = Input.is_action_pressed("force_move")
	var lmb_held: bool = Input.is_action_pressed("attack_primary")

	# 1) Shift 站桩 — 不动,面向光标(站桩射击)
	if shift_held:
		_clear_targets()
		_face_mouse()
		_stop_horizontal_motion()
		return

	# 2) 强制移动 — 朝光标地面点走,清攻击目标(无视敌人)
	if force_move_held:
		var p: Vector3 = _get_mouse_ground_point()
		_move_target = p
		_has_move_target = true
		_attack_target = null
		_face_toward(p)
		_move_toward(p, delta)
		return

	# 3) LMB 按下/按住 — 重新决策:点中敌人 = 攻击目标;点中地面 = 移动目标
	if lmb_held:
		_resolve_lmb_click()
	# 4) 攻击目标(从 LMB 点敌设置)— 走进射程,到了就停下让 SkillSlotManager 开火
	if is_instance_valid(_attack_target):
		var ep: Vector3 = (_attack_target as Node3D).global_position
		ep.y = global_position.y
		var dist: float = global_position.distance_to(ep)
		_face_toward(ep)
		if dist > ATTACK_RANGE:
			_move_toward(ep, delta)
		else:
			_stop_horizontal_motion()
		return

	# 5) 移动目标(从 LMB 点地设置)— 走过去,到了停
	if _has_move_target:
		var d: float = global_position.distance_to(_move_target)
		if d <= ARRIVE_THRESHOLD:
			_has_move_target = false
			_stop_horizontal_motion()
		else:
			_face_toward(_move_target)
			_move_toward(_move_target, delta)
		return

	# 6) 完全无输入:停下,朝向光标(便于右键技能朝光标释放)
	_face_mouse()
	_stop_horizontal_motion()

# 把鼠标光标投到地面平面,如果命中敌人(physics raycast)则设为攻击目标。
func _resolve_lmb_click() -> void:
	# 仅在"刚按下"那一帧 spawn 终点指引环(避免按住每帧 spam)
	var just_clicked: bool = Input.is_action_just_pressed("attack_primary")
	var enemy: Node3D = _pick_enemy_under_cursor()
	if enemy != null:
		_attack_target = enemy
		_has_move_target = false
		if just_clicked:
			_spawn_click_indicator(enemy.global_position, true)
		return
	var p: Vector3 = _get_mouse_ground_point()
	_move_target = p
	_has_move_target = true
	_attack_target = null
	if just_clicked:
		_spawn_click_indicator(p, false)

# D3 经典点地反馈:在落点 spawn 一个 0.4s 圆环,扩散 + 淡出。
# is_enemy=true → 红圈(锁敌);false → 白圈(走点)
func _spawn_click_indicator(world_pos: Vector3, is_enemy: bool) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	if is_enemy:
		mat.albedo_color = Color(1.0, 0.35, 0.30, 0.9)
		mat.emission = Color(1.0, 0.30, 0.20, 1.0)
	else:
		mat.albedo_color = Color(0.95, 0.95, 1.0, 0.85)
		mat.emission = Color(0.85, 0.90, 1.0, 1.0)
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 3.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = 0.55
	torus.outer_radius = 0.70
	torus.ring_segments = 32
	torus.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = torus
	scene_root.add_child(mi)
	mi.global_position = world_pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3.ONE * 0.5
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.4, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.4)
	tw.chain().tween_callback(Callable(mi, "queue_free"))

# 物理 raycast(layer mask = 敌人层 2)从相机射,命中的就是该敌人 collider 的根。
func _pick_enemy_under_cursor() -> Node3D:
	if _camera == null or not is_instance_valid(_camera):
		return null
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var origin: Vector3 = _camera.project_ray_origin(mouse_pos)
	var dir: Vector3 = _camera.project_ray_normal(mouse_pos)
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 200.0, 2)  # 2 = 敌人层
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return null
	var col: Object = hit.get("collider")
	if col == null:
		return null
	# 优先返回 enemies group 的成员(可能本身就是 collider 或其祖先)
	var n: Node = col as Node
	while n != null:
		if n.is_in_group("enemies") and n is Node3D:
			return n
		n = n.get_parent()
	return null

func _move_toward(target: Vector3, _delta: float) -> void:
	if is_frozen:
		_stop_horizontal_motion()
		return
	var to: Vector3 = target - global_position
	to.y = 0.0
	if to.length() < 0.001:
		_stop_horizontal_motion()
		return
	var dir: Vector3 = to.normalized()
	# 引导期(箭雨风暴):移速降到 channel_movement_mult(默认 50%)
	var spd: float = SPEED * speed_buff_mult * (_channel_movement_mult if _is_channeling else 1.0)
	velocity.x = dir.x * spd
	velocity.z = dir.z * spd
	is_moving = true
	move_and_slide()

func _stop_horizontal_motion() -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	is_moving = false
	move_and_slide()

func _clear_targets() -> void:
	_has_move_target = false
	_attack_target = null

# ── 朝向 ────────────────────────────────────────────
func _face_toward(world_point: Vector3) -> void:
	var to: Vector3 = world_point - global_position
	to.y = 0.0
	if to.length() < 0.01:
		return
	var fwd: Vector3 = to.normalized()
	_last_forward = fwd
	look_at(global_position + fwd, Vector3.UP)

func _face_mouse() -> void:
	var aim: Vector3 = _get_mouse_ground_point()
	_face_toward(aim)

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

# ── LMB 攻击门控 ────────────────────────────────────
# SkillSlotManager 槽 0(LMB 利箭)只在 armed=true 时才响应。避免点地走时也开火。
func _update_lmb_attack_armed() -> void:
	var shift_held: bool = Input.is_action_pressed("force_stand")
	# Shift 站桩 = 总是开火(原地朝光标射)
	if shift_held:
		_set_lmb_armed(true)
		return
	# 攻击目标存在 + 在射程内 = 开火
	if is_instance_valid(_attack_target):
		var ep: Vector3 = (_attack_target as Node3D).global_position
		ep.y = global_position.y
		var dist: float = global_position.distance_to(ep)
		_set_lmb_armed(dist <= ATTACK_RANGE)
		return
	_set_lmb_armed(false)

func _set_lmb_armed(b: bool) -> void:
	if _lmb_attack_armed == b:
		# 即使本地状态相同,也定期同步给 slot_manager(防止初始默认值不一致)。
		# 只在 false 时跳过同步;true 时也直接同步一次。
		if not b:
			return
	_lmb_attack_armed = b
	if _slot_manager != null and _slot_manager.has_method("set_lmb_attack_armed"):
		_slot_manager.set_lmb_attack_armed(b)

# ── 公共 API ────────────────────────────────────────
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

# 当前光标方向(投到地面平面 → 玩家 → 光标的水平单位向量)。
# RMB / Q / E 等"朝光标释放"的技能用这个,而不是玩家当前 basis(避免边走边射时方向歪)。
func get_aim_direction() -> Vector3:
	var aim: Vector3 = _get_mouse_ground_point()
	var to: Vector3 = aim - global_position
	to.y = 0.0
	if to.length() < 0.001:
		return get_forward()
	return to.normalized()

# SkillSlotManager.skill_activated 回调:非 LMB(slot != 0)触发"急停 + 朝光标施法"
func _on_skill_activated(slot_index: int, _sd: Resource) -> void:
	if slot_index == 0:
		return  # LMB 利箭不急停(连射手感)
	# 引导态(箭雨风暴 E)期间不急停
	if _is_channeling:
		return
	# 立即面向光标 — 给 SkillExecutor 同帧读取 basis 时拿到正确朝向
	_face_mouse()
	_cast_freeze_timer = CAST_FREEZE_DURATION
	# 急停瞬间清掉攻击目标,但保留 _move_target —— freeze 结束后会自动恢复朝点行走
	_attack_target = null

# 引导启停:由 SkillExecutor._on_channel_started/stopped 调
func set_channeling(active: bool, movement_mult: float) -> void:
	_is_channeling = active
	_channel_movement_mult = movement_mult if active else 1.0
	# 进入引导:取消任何挂着的施法急停,并清攻击目标(避免 LMB armed 干扰 E 的输入循环)
	if active:
		_cast_freeze_timer = 0.0

# 翻滚方向源:V3.0 改为"光标方向前滚",无 WASD。
# 也对外暴露当前面向供 fallback。
func get_movement_input_direction() -> Vector3:
	# 光标方向(玩家 → 光标 的水平单位向量)— 朝光标前滚
	var aim: Vector3 = _get_mouse_ground_point()
	var to: Vector3 = aim - global_position
	to.y = 0.0
	if to.length() < 0.001:
		return get_forward()
	return to.normalized()

# ── 翻滚 ────────────────────────────────────────────
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
	_dodge_velocity = d * (distance / duration)
	look_at(global_position + d, Vector3.UP)
	_last_forward = d
	# 翻滚开始 — 清掉移动/攻击目标,避免翻完又往原点走
	_clear_targets()
	dodge_started.emit(d, duration)
	# SFX 翻滚
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("dodge", global_position, -3.0, 0.08)
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
	_evade_buffer_timer = EVADE_BUFFER_TIME
	dodge_ended.emit()

# ── 受伤 / 死亡 ─────────────────────────────────────
# V3.0 锁死护甲减伤 70%(player_loadout.csv 爽快割草版)
const ARMOR_DAMAGE_REDUCTION: float = 0.70

func take_damage(amount: int, source = null) -> void:
	if is_dead or is_invulnerable or amount <= 0:
		return
	# 1) 固定护甲减伤 50%(取代旧的等级公式 减伤=护甲/(护甲+20×攻击者等级))
	var actual: float = float(amount) * (1.0 - ARMOR_DAMAGE_REDUCTION)
	# 2) 闪避本能:翻滚后 2s 内额外 -20%
	if _evade_buffer_timer > 0.0:
		actual *= (1.0 - EVADE_DAMAGE_REDUCTION)
	var dmg: int = max(1, int(round(actual)))
	current_health = clamp(current_health - dmg, 0, max_health)
	health_changed.emit(current_health, max_health)
	# SFX 受击
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("player_hurt", global_position, -2.0, 0.05)
	var cm = get_node_or_null("/root/CombatManager")
	if cm != null:
		cm.player_damaged.emit(dmg, source)
	if current_health <= 0:
		_die()

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	player_died.emit()
