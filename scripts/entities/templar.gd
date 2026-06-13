extends CharacterBody3D

# Templar — 圣堂武士科尔玛随从。
# 策划案口径(V2.0 简化版):跟随 + 自动近战最近敌人 + 10s 一次小治疗。
# 落后梯子:治疗砍掉只留跟随+攻击。本实现保留治疗,可通过 heal_enabled 一键关。
#
# 与敌人碰撞:templar 自己 collision_mask=4 只走地,enemy_zombie.collision_mask
# 包含 ally bit(16),所以敌人会被 templar 物理挡住——这就是"远程职业身位墙"。
# templar 自己不被敌人撞动(mask 不含 enemy),站着也能挡。
#
# 状态机:
#   FOLLOW (默认): 跟随玩家,保持距离,无敌情况下站在玩家身边
#   ATTACK: 感知范围内有敌人 → 切过去近战;敌人死 / 跑远 → 回 FOLLOW
# 没有 IDLE/DEATH(策划案口径"永久存在",简化为无敌)。

signal heal_pulsed(amount: int)

const MOVE_SPEED: float = 6.5
const FOLLOW_DEADZONE: float = 1.6        # 玩家距离 < 此值不动(避免抖)
const ENGAGE_RANGE: float = 8.0           # 此范围内主动找敌人;外则保持跟随
const TARGET_LOST_RANGE: float = 12.0     # 当前目标超出此距离 → 切目标
const ATTACK_RANGE: float = 1.8
const ATTACK_INTERVAL: float = 1.2
const NAV_REPATH_INTERVAL: float = 0.3
const HEAL_INTERVAL: float = 10.0
const HEAL_PCT: float = 0.10              # 治疗 = 玩家 max_health × 10%

# 敌人 enemy_base.State.DEATH 的整数值(避免硬依赖)
const ENEMY_DEATH_STATE: int = 4

@export var attack_damage: int = 22       # 武器均伤 × ~1.5 占位;Day2 接系统数值
@export var heal_enabled: bool = true     # 砍量梯子开关

enum State { FOLLOW, ATTACK }
var state: int = State.FOLLOW

var _player: Node3D = null
var _target: Node3D = null
var _attack_timer: float = 0.0
var _nav_timer: float = 0.0
var _heal_timer: float = HEAL_INTERVAL    # 出生后 10s 才放第一次

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D if has_node("NavigationAgent3D") else null

func _ready() -> void:
	add_to_group("allies")
	add_to_group("templar")
	call_deferred("_acquire_player")

func _acquire_player() -> void:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		_player = arr[0] as Node3D

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_acquire_player()
		if _player == null:
			velocity = Vector3.ZERO
			move_and_slide()
			return

	# 治疗周期
	if heal_enabled:
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = HEAL_INTERVAL
			_do_heal()

	# 状态切换
	if not _target_valid():
		_target = _find_enemy_in_range()
	if _target != null:
		if state != State.ATTACK:
			_set_state(State.ATTACK)
	else:
		if state != State.FOLLOW:
			_set_state(State.FOLLOW)

	match state:
		State.FOLLOW:
			_tick_follow(delta)
		State.ATTACK:
			_tick_attack(delta)

func _set_state(new_state: int) -> void:
	state = new_state
	_nav_timer = 0.0
	_attack_timer = 0.0

# ── FOLLOW ────────────────────────────────────────────
func _tick_follow(delta: float) -> void:
	var dist: float = global_position.distance_to(_player.global_position)
	if dist < FOLLOW_DEADZONE:
		velocity = Vector3.ZERO
		# 朝向玩家面向(略微同步方向感)
		var pf: Vector3 = -_player.global_transform.basis.z
		pf.y = 0.0
		if pf.length() > 0.001:
			look_at(global_position + pf.normalized(), Vector3.UP)
		move_and_slide()
		return

	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = NAV_REPATH_INTERVAL
		if nav_agent != null:
			nav_agent.target_position = _player.global_position

	var dir: Vector3 = Vector3.ZERO
	if nav_agent != null and not nav_agent.is_navigation_finished():
		dir = nav_agent.get_next_path_position() - global_position
	if dir.length() < 0.2:
		dir = _player.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.001:
		dir = dir.normalized()
		velocity = dir * MOVE_SPEED
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity = Vector3.ZERO
	move_and_slide()

# ── ATTACK ────────────────────────────────────────────
func _tick_attack(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	var dist: float = global_position.distance_to(_target.global_position)

	if dist > ATTACK_RANGE:
		# 追
		_nav_timer -= delta
		if _nav_timer <= 0.0:
			_nav_timer = NAV_REPATH_INTERVAL
			if nav_agent != null:
				nav_agent.target_position = _target.global_position

		var dir: Vector3 = Vector3.ZERO
		if nav_agent != null and not nav_agent.is_navigation_finished():
			dir = nav_agent.get_next_path_position() - global_position
		if dir.length() < 0.2:
			dir = _target.global_position - global_position
		dir.y = 0.0
		if dir.length() > 0.001:
			dir = dir.normalized()
			velocity = dir * MOVE_SPEED
			look_at(global_position + dir, Vector3.UP)
		else:
			velocity = Vector3.ZERO
		move_and_slide()
	else:
		# 贴脸打
		velocity = Vector3.ZERO
		var fwd: Vector3 = _target.global_position - global_position
		fwd.y = 0.0
		if fwd.length() > 0.001:
			look_at(global_position + fwd.normalized(), Vector3.UP)
		move_and_slide()

		_attack_timer -= delta
		if _attack_timer <= 0.0:
			_attack_timer = ATTACK_INTERVAL
			_do_strike()

func _do_strike() -> void:
	if _target == null or not is_instance_valid(_target):
		return
	if global_position.distance_to(_target.global_position) > ATTACK_RANGE * 1.25:
		return
	if _target.has_method("take_damage"):
		_target.take_damage(attack_damage, self)
	# 通过 CombatManager 让 juice 系统接管闪白/飘字/僵直
	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null:
		var hit_pos: Vector3 = (_target as Node3D).global_position + Vector3(0, 0.9, 0)
		var hit_dir: Vector3 = ((_target as Node3D).global_position - global_position)
		hit_dir.y = 0.0
		if hit_dir.length() > 0.001:
			hit_dir = hit_dir.normalized()
		else:
			hit_dir = -global_transform.basis.z
		cm.hit_landed.emit(self, _target, attack_damage, false, "physical", hit_pos, hit_dir)

# ── 目标选择 ─────────────────────────────────────────
func _target_valid() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	if "state" in _target and int(_target.state) == ENEMY_DEATH_STATE:
		return false
	if global_position.distance_to(_target.global_position) > TARGET_LOST_RANGE:
		return false
	return true

func _find_enemy_in_range() -> Node3D:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var best: Node3D = null
	var best_dist: float = INF
	for e in enemies:
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		if "state" in e and int(e.state) == ENEMY_DEATH_STATE:
			continue
		var d: float = global_position.distance_to((e as Node3D).global_position)
		if d > ENGAGE_RANGE:
			continue
		if d < best_dist:
			best_dist = d
			best = e
	return best

# ── 治疗 ─────────────────────────────────────────────
func _do_heal() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not ("current_health" in _player) or not ("max_health" in _player):
		return
	var max_hp: int = int(_player.max_health)
	var cur: int = int(_player.current_health)
	if cur >= max_hp:
		return
	var amount: int = int(round(float(max_hp) * HEAL_PCT))
	if amount <= 0:
		return
	var new_hp: int = clamp(cur + amount, 0, max_hp)
	var actual: int = new_hp - cur
	if actual <= 0:
		return
	_player.current_health = new_hp
	if _player.has_signal("health_changed"):
		_player.health_changed.emit(new_hp, max_hp)
	heal_pulsed.emit(actual)
	_spawn_heal_visual()

# 占位 VFX:绿光球在玩家身上扩散 + 淡出
func _spawn_heal_visual() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var ind: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.7
	sphere.height = 1.4
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 1.0, 0.5, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.4, 1.0)
	mat.emission_energy_multiplier = 0.8
	sphere.material = mat
	ind.mesh = sphere
	ind.scale = Vector3.ZERO
	scene_root.add_child(ind)
	ind.global_position = _player.global_position + Vector3(0, 0.5, 0)
	var tw: Tween = ind.create_tween()
	tw.tween_property(ind, "scale", Vector3.ONE * 1.5, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tw.tween_callback(Callable(ind, "queue_free"))

# ── 受伤接口(简化为无敌)──────────────────────────
# 策划案口径"科尔玛永远在",Day1 灰盒不做掉血逻辑。需要时改这里。
func take_damage(_amount: int, _source = null) -> void:
	pass
