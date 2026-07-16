extends CharacterBody3D

# Butcher — 全 Demo 唯一 Boss(策划 03 §6;V4 攻击性重做)。
# V4 变更:
#   ① 技能库扩到 6 招:普攻 / 横扫 / 冲锋 / 血火三连弹(远程) / 震地冲击波 / 跃斩(P2)
#   ② 攻击欲望:收招大幅缩短 + 收招后按概率(P1 45% / P2 70%)直接连招,不再"一招一愣"
#   ③ 特效:接 BinbunVFX 粒子(施法阵/火弹/冲击波)+ 程序化扩散环,替代纯色块
#   ④ 单地图模式:由 RiftManager 在玩家附近降临(不再切 boss 房)
#
# 状态机:
#   IDLE → CHASE → ATTACK / SWEEP / CHARGE / BOLT / SLAM / LEAP(P2) → 连招或 CHASE
#                → ROAR(P2 切换演出,无敌)→ CHASE
#                → DEATH(终态)
#
# 控制免疫(策划 03 §7.2):不挂 Knockback;Stagger 只做视觉;冰冻降级为 30% 减速。

signal phase_changed(new_phase: int)
signal died(self_ref)
signal state_changed(old_state: int, new_state: int)

# ── 数值(策划 03 §6 锚点)─────────────────────────
const MAX_HEALTH: int = 30000  # V3.0 守门人 (rift_monsters.csv guardian·2026 调)
const ATTACK_DAMAGE: int = 150  # V3.0 守门人 (rift_monsters.csv guardian·2026 调)
const PHASE2_HEALTH_RATIO: float = 0.5

const MOVE_SPEED: float = 4.6            # V4:4.0→4.6,追击更有压迫感
const PHASE2_MOVE_MULT: float = 1.15     # P2 移速再 +15%
const CHARGE_SPEED: float = 14.0

# 普攻三阶段(V4:收招 0.5→0.22)
const BASIC_WINDUP: float = 0.7
const BASIC_STRIKE: float = 0.25
const BASIC_RECOVERY: float = 0.22
const BASIC_HIT_RANGE: float = 3.5
const BASIC_ENTER_RANGE: float = 3.0

# 冲锋(V4:蓄力 1.2→0.85,撞墙硬直 3.0→1.6)
const CHARGE_WINDUP: float = 0.85
const CHARGE_MAX_DISTANCE: float = 25.0
const CHARGE_TRIGGER_RANGE: float = 6.0
const CHARGE_HIT_RADIUS: float = 1.6
const WALL_STUN_DURATION: float = 1.6
const WALL_STUN_DAMAGE_MULT: float = 1.25

# 横扫(V4:收招 0.55→0.3)
const SWEEP_WINDUP: float = 0.55
const SWEEP_STRIKE: float = 0.35
const SWEEP_RECOVERY: float = 0.3
const SWEEP_RADIUS: float = 5.5
const SWEEP_DAMAGE_MULT: float = 1.2
const SWEEP_EVERY_P1: int = 3
const SWEEP_EVERY_P2: int = 2

# 血火三连弹(V4 新增:中远距离压制,风筝不再零风险)
const BOLT_WINDUP: float = 0.5
const BOLT_RECOVERY: float = 0.25
const BOLT_COOLDOWN_P1: float = 5.0
const BOLT_COOLDOWN_P2: float = 3.0
const BOLT_DAMAGE_MULT: float = 0.5
const BOLT_SPEED: float = 15.0
const BOLT_LIFE: float = 1.8
const BOLT_HIT_RADIUS: float = 1.2
const BOLT_SPREAD_RAD: float = 0.24      # 三连扇形左右偏角

# 震地冲击波(V4 新增:近身 AOE,惩罚贴身绕背)
const SLAM_WINDUP: float = 0.75
const SLAM_RECOVERY: float = 0.35
const SLAM_RADIUS: float = 8.0
const SLAM_DAMAGE_MULT: float = 1.1
const SLAM_COOLDOWN_P1: float = 7.0
const SLAM_COOLDOWN_P2: float = 5.0

# 跃斩(V4 新增:P2 专属,中距离强制贴脸)
const LEAP_CROUCH: float = 0.4
const LEAP_AIR: float = 0.65
const LEAP_RECOVERY: float = 0.3
const LEAP_RADIUS: float = 4.0
const LEAP_DAMAGE_MULT: float = 1.3
const LEAP_COOLDOWN: float = 8.0
const LEAP_PEAK_H: float = 3.0

# 连招概率(收招后直接接下一招,不回 CHASE 发呆)
const CHAIN_P1: float = 0.45
const CHAIN_P2: float = 0.7

# P2 切换
const ROAR_DURATION: float = 1.5
const PHASE2_SPEED_MULT: float = 1.3     # P2 攻速(计时器加速)

# 烧地板(V4:首次 40→8s,间隔 18/12→14/9,战斗开场即有场地压力)
const FLOOR_BURN_INTERVAL_P1: float = 14.0
const FLOOR_BURN_INTERVAL_P2: float = 9.0
const FLOOR_BURN_FIRST_DELAY: float = 8.0
const FLOOR_BURN_NEAR_PLAYER_MIN: float = 3.0
const FLOOR_BURN_NEAR_PLAYER_MAX: float = 6.0
const FLOOR_BURN_SCENE_PATH: String = "res://scenes/enemies/floor_burn_zone.tscn"

# VFX 资产(BinbunVFX)
const VFX_FIRE_CAST: String = "res://assets/MagicVFX/assets/BinbunVFX_Vol2/ElementalMagicFX/effects/cast/vfx_fire_cast_01.tscn"
const VFX_FIRE_PROJ: String = "res://assets/MagicVFX/assets/BinbunVFX_Vol2/ElementalMagicFX/effects/projectile/vfx_fire_projectile_01.tscn"
const VFX_WAVE: String = "res://assets/MagicVFX/assets/BinbunVFX/magic_projectiles/effects/mprojectile_wave/mprojectile_wave_vfx_02.tscn"

# AI / 寻路(V4:决策 1.5→0.8,更快起冲锋)
const ENGAGE_RANGE: float = 30.0
const NAV_REPATH_INTERVAL: float = 0.3
const CHASE_DECISION_TIME: float = 0.8
const CHASE_THINK_INTERVAL: float = 0.4  # CHASE 中每隔此时长评估一次技能

# 状态枚举(前 7 项顺序不能动:enemy_anim_driver 依赖 CHASE=1/ATTACK=2/DEATH=5)
enum State { IDLE, CHASE, ATTACK, CHARGE, ROAR, DEATH, SWEEP, BOLT, SLAM, LEAP }

# ── 运行时 ─────────────────────────────────────────
var current_health: int = MAX_HEALTH
var phase: int = 1
var damage_multiplier: float = 1.0
var state: int = State.IDLE

var _player: Node3D = null
var _floor_burn_scene: PackedScene = null
var _vfx_cast: PackedScene = null
var _vfx_proj: PackedScene = null
var _vfx_wave: PackedScene = null

# CHASE 子状态
var _chase_decision_timer: float = 0.0
var _chase_think_timer: float = 0.0
var _nav_repath_timer: float = 0.0

# ATTACK / SWEEP 子状态
var _attack_phase_timer: float = 0.0
var _attack_did_strike: bool = false
var _basic_attack_count: int = 0
var _sweep_phase_timer: float = 0.0
var _sweep_did_strike: bool = false

# CHARGE 子状态
var _charge_substate: int = 0
var _charge_phase_timer: float = 0.0
var _charge_dir: Vector3 = Vector3.ZERO
var _charge_start_pos: Vector3 = Vector3.ZERO
var _charge_did_hit_player: bool = false
var _charge_trail: Node3D = null
var _charge_line_len: float = CHARGE_MAX_DISTANCE   # 预警线实际长度(撞墙点截断)

# BOLT / SLAM / LEAP 子状态
var _bolt_timer: float = 0.0
var _bolt_fired: bool = false
var _slam_timer: float = 0.0
var _slam_did_strike: bool = false
var _leap_substate: int = 0              # 0 crouch, 1 air, 2 recovery
var _leap_timer: float = 0.0
var _leap_from: Vector3 = Vector3.ZERO
var _leap_to: Vector3 = Vector3.ZERO

# 技能冷却(降临后很快开始施压)
var _bolt_cd: float = 2.0
var _slam_cd: float = 4.0
var _leap_cd: float = 3.0

# ROAR
var _roar_timer: float = 0.0
var _is_invulnerable: bool = false

# 烧地板
var _floor_burn_timer: float = FLOOR_BURN_FIRST_DELAY

# 减速
var _slow_amount: float = 0.0
var _slow_timer: float = 0.0

# 节点引用
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D if has_node("NavigationAgent3D") else null
@onready var body_mesh: MeshInstance3D = $BodyMesh if has_node("BodyMesh") else null
@onready var charge_warning: Node3D = $ChargeWarning if has_node("ChargeWarning") else null
@onready var basic_warning: Node3D = $BasicAttackWarning if has_node("BasicAttackWarning") else null
@onready var stagger_comp: Node = $StaggerComponent if has_node("StaggerComponent") else null

# ── 生命周期 ───────────────────────────────────────
func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	var reg: Node = get_node_or_null("/root/EntityRegistry")
	if reg != null and reg.has_method("register_enemy"):
		reg.register_enemy(self)
	set_meta("monster_id", &"butcher")
	set_meta("monster_level", 7)
	set_meta("drop_source", 3)
	current_health = MAX_HEALTH
	if charge_warning != null:
		charge_warning.visible = false
	if basic_warning != null:
		basic_warning.visible = false
	if ResourceLoader.exists(FLOOR_BURN_SCENE_PATH):
		_floor_burn_scene = load(FLOOR_BURN_SCENE_PATH)
	if ResourceLoader.exists(VFX_FIRE_CAST):
		_vfx_cast = load(VFX_FIRE_CAST)
	if ResourceLoader.exists(VFX_FIRE_PROJ):
		_vfx_proj = load(VFX_FIRE_PROJ)
	if ResourceLoader.exists(VFX_WAVE):
		_vfx_wave = load(VFX_WAVE)
	# 注:不连接 stagger_comp.stagger_started — 视觉做但不打断 AI
	call_deferred("_acquire_player")

func _exit_tree() -> void:
	var reg: Node = get_node_or_null("/root/EntityRegistry")
	if reg != null and reg.has_method("unregister_enemy"):
		reg.unregister_enemy(self)

func _acquire_player() -> void:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		_player = arr[0] as Node3D

# ── 主循环 ─────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if state == State.DEATH:
		return

	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_amount = 0.0

	_bolt_cd = maxf(0.0, _bolt_cd - delta)
	_slam_cd = maxf(0.0, _slam_cd - delta)
	_leap_cd = maxf(0.0, _leap_cd - delta)

	if _player == null or not is_instance_valid(_player):
		_acquire_player()

	if state != State.IDLE and state != State.ROAR and state != State.DEATH:
		_floor_burn_timer -= delta
		if _floor_burn_timer <= 0.0:
			_floor_burn_timer = FLOOR_BURN_INTERVAL_P2 if phase == 2 else FLOOR_BURN_INTERVAL_P1
			_trigger_floor_burn()

	match state:
		State.IDLE:
			_tick_idle(delta)
		State.CHASE:
			_tick_chase(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.SWEEP:
			_tick_sweep(delta)
		State.CHARGE:
			_tick_charge(delta)
		State.BOLT:
			_tick_bolt(delta)
		State.SLAM:
			_tick_slam(delta)
		State.LEAP:
			_tick_leap(delta)
		State.ROAR:
			_tick_roar(delta)

# ── 决策核心(V4)────────────────────────────────────
# 从 CHASE / 收招连招处调用:按距离与冷却选下一手。
func _decide_action() -> void:
	if _player == null or not is_instance_valid(_player):
		if state != State.IDLE:
			_set_state(State.IDLE)
		return
	var dist: float = global_position.distance_to(_player.global_position)
	# 贴身:震地(概率,近身 AOE)或 普攻/横扫轮转
	if dist < BASIC_ENTER_RANGE + 0.5:
		if _slam_cd <= 0.0 and randf() < (0.5 if phase == 2 else 0.35):
			_set_state(State.SLAM)
			return
		var threshold: int = SWEEP_EVERY_P2 if phase == 2 else SWEEP_EVERY_P1
		if _basic_attack_count >= threshold:
			_basic_attack_count = 0
			_set_state(State.SWEEP)
		else:
			_basic_attack_count += 1
			_set_state(State.ATTACK)
		return
	# 中距离:P2 跃斩强制贴脸 > 三连弹压制 > 近中距震地
	if phase == 2 and _leap_cd <= 0.0 and dist >= 5.0 and dist <= 14.0:
		_set_state(State.LEAP)
		return
	if _bolt_cd <= 0.0 and dist >= 6.0 and dist <= 18.0:
		_set_state(State.BOLT)
		return
	if _slam_cd <= 0.0 and dist < 6.5:
		_set_state(State.SLAM)
		return
	if state != State.CHASE:
		_set_state(State.CHASE)

# 收招:按概率直接连招(攻击欲望核心),否则回 CHASE 追一步
func _after_skill() -> void:
	var chain_p: float = CHAIN_P2 if phase == 2 else CHAIN_P1
	if _player != null and is_instance_valid(_player) and randf() < chain_p:
		_decide_action()
	else:
		_set_state(State.CHASE)

# ── IDLE ─────────────────────────────────────────────
func _tick_idle(_delta: float) -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	if _player != null and global_position.distance_to(_player.global_position) < ENGAGE_RANGE:
		_set_state(State.CHASE)

# ── CHASE ─────────────────────────────────────────────
func _tick_chase(delta: float) -> void:
	if _player == null:
		_set_state(State.IDLE)
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist < BASIC_ENTER_RANGE:
		_decide_action()
		return

	# 周期性评估技能(三连弹/跃斩/震地在追击途中也能起手)
	_chase_think_timer -= delta
	if _chase_think_timer <= 0.0:
		_chase_think_timer = CHASE_THINK_INTERVAL
		_decide_action()
		if state != State.CHASE:
			return

	# 追不上且拉开距离 → 冲锋
	_chase_decision_timer -= delta
	if _chase_decision_timer <= 0.0:
		_chase_decision_timer = CHASE_DECISION_TIME
		if dist > CHARGE_TRIGGER_RANGE:
			_set_state(State.CHARGE)
			return

	_nav_repath_timer -= delta
	if _nav_repath_timer <= 0.0:
		_nav_repath_timer = NAV_REPATH_INTERVAL
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
		var spd: float = MOVE_SPEED * (PHASE2_MOVE_MULT if phase == 2 else 1.0) * (1.0 - _slow_amount)
		velocity = dir * spd
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity = Vector3.ZERO
	move_and_slide()

# ── ATTACK(普攻三阶段)──────────────────────────────
func _tick_attack(delta: float) -> void:
	_face_player()
	velocity = Vector3.ZERO
	move_and_slide()

	_attack_phase_timer += delta
	var speedup: float = PHASE2_SPEED_MULT if phase == 2 else 1.0
	var windup_t: float = BASIC_WINDUP / speedup
	var total_t: float = (BASIC_WINDUP + BASIC_STRIKE + BASIC_RECOVERY) / speedup

	if basic_warning != null:
		basic_warning.visible = _attack_phase_timer < windup_t

	if not _attack_did_strike and _attack_phase_timer >= windup_t:
		_do_basic_strike()
		_attack_did_strike = true

	if _attack_phase_timer >= total_t:
		if basic_warning != null:
			basic_warning.visible = false
		_after_skill()

func _do_basic_strike() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 挥击落点冲击(不论中没中都有劈砍反馈)
	var front: Vector3 = global_position - global_transform.basis.z * 2.0
	front.y = global_position.y + 0.1
	_spawn_ring(front, 0.4, 2.4, 0.28, Color(1.0, 0.32, 0.12))
	if global_position.distance_to(_player.global_position) > BASIC_HIT_RANGE:
		return
	if _player.has_method("take_damage"):
		_player.take_damage(ATTACK_DAMAGE, self)

# ── SWEEP(横扫,贴脸 AOE)───────────────────────────────
func _tick_sweep(delta: float) -> void:
	_face_player()
	velocity = Vector3.ZERO
	move_and_slide()

	_sweep_phase_timer += delta
	var speedup: float = PHASE2_SPEED_MULT if phase == 2 else 1.0
	var windup_t: float = SWEEP_WINDUP / speedup
	var total_t: float = (SWEEP_WINDUP + SWEEP_STRIKE + SWEEP_RECOVERY) / speedup

	if basic_warning != null:
		var in_windup: bool = _sweep_phase_timer < windup_t
		basic_warning.visible = in_windup
		if in_windup:
			var ratio: float = SWEEP_RADIUS / 3.5
			basic_warning.scale = Vector3(ratio, 1.0, ratio)
		else:
			basic_warning.scale = Vector3.ONE

	if not _sweep_did_strike and _sweep_phase_timer >= windup_t:
		_do_sweep_strike()
		_sweep_did_strike = true

	if _sweep_phase_timer >= total_t:
		if basic_warning != null:
			basic_warning.visible = false
			basic_warning.scale = Vector3.ONE
		_after_skill()

func _do_sweep_strike() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 360° 火环扩散(两圈错峰)+ 施法阵
	var at: Vector3 = global_position
	at.y += 0.1
	_spawn_ring(at, 0.6, SWEEP_RADIUS, 0.32, Color(1.0, 0.45, 0.1))
	_spawn_ring(at, 0.3, SWEEP_RADIUS * 0.7, 0.4, Color(1.0, 0.2, 0.1))
	_spawn_vfx(_vfx_wave, at, 1.6, 1.4)
	if global_position.distance_to(_player.global_position) <= SWEEP_RADIUS:
		if _player.has_method("take_damage"):
			var dmg: int = int(round(float(ATTACK_DAMAGE) * SWEEP_DAMAGE_MULT))
			_player.take_damage(dmg, self)
	_shake()

# ── CHARGE(冲锋三阶段)──────────────────────────────
func _tick_charge(delta: float) -> void:
	_charge_phase_timer += delta

	match _charge_substate:
		0:  # WINDUP
			velocity = Vector3.ZERO
			if _charge_dir.length() > 0.001:
				look_at(global_position + _charge_dir, Vector3.UP)
			move_and_slide()
			if charge_warning != null:
				var t: float = clamp(_charge_phase_timer / CHARGE_WINDUP, 0.0, 1.0)
				charge_warning.visible = true
				# 按撞墙距离截断,预警线不再穿墙/飘出关卡
				charge_warning.scale = Vector3(1.0, 1.0, t * _charge_line_len / CHARGE_MAX_DISTANCE)
			if _charge_phase_timer >= CHARGE_WINDUP:
				_charge_substate = 1
				_charge_phase_timer = 0.0
				_charge_did_hit_player = false
				if charge_warning != null:
					charge_warning.visible = false
				# 冲锋火焰尾迹(随身粒子,结束时熄灭)
				_charge_trail = _attach_vfx(_vfx_proj, Vector3(0, 1.2, 0.6))

		1:  # DASH
			velocity = _charge_dir * CHARGE_SPEED
			move_and_slide()
			if not _charge_did_hit_player and _player != null and is_instance_valid(_player):
				if global_position.distance_to(_player.global_position) < CHARGE_HIT_RADIUS:
					if _player.has_method("take_damage"):
						_player.take_damage(ATTACK_DAMAGE, self)
					_charge_did_hit_player = true
			var hit_wall: bool = false
			for i in range(get_slide_collision_count()):
				var col: KinematicCollision3D = get_slide_collision(i)
				if col == null:
					continue
				if abs(col.get_normal().y) < 0.5:
					hit_wall = true
					break
			var dashed: float = global_position.distance_to(_charge_start_pos)
			if hit_wall:
				_free_charge_trail()
				_enter_wall_stun()
			elif dashed >= CHARGE_MAX_DISTANCE:
				_free_charge_trail()
				_after_skill()

		2:  # WALL_STUN
			velocity = Vector3.ZERO
			move_and_slide()
			if _charge_phase_timer >= WALL_STUN_DURATION:
				damage_multiplier = 1.0
				_set_state(State.CHASE)

func _free_charge_trail() -> void:
	if _charge_trail != null and is_instance_valid(_charge_trail):
		_charge_trail.queue_free()
	_charge_trail = null

func _enter_wall_stun() -> void:
	_charge_substate = 2
	_charge_phase_timer = 0.0
	damage_multiplier = WALL_STUN_DAMAGE_MULT
	_shake()

# ── BOLT(血火三连弹)─────────────────────────────────
func _tick_bolt(delta: float) -> void:
	_face_player()
	velocity = Vector3.ZERO
	move_and_slide()
	_bolt_timer += delta
	if not _bolt_fired and _bolt_timer >= BOLT_WINDUP:
		_bolt_fired = true
		_fire_bolts()
	if _bolt_timer >= BOLT_WINDUP + BOLT_RECOVERY:
		_bolt_cd = BOLT_COOLDOWN_P2 if phase == 2 else BOLT_COOLDOWN_P1
		_after_skill()

func _fire_bolts() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var base: Vector3 = _player.global_position - global_position
	base.y = 0.0
	if base.length() < 0.01:
		return
	base = base.normalized()
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	for off in [-BOLT_SPREAD_RAD, 0.0, BOLT_SPREAD_RAD]:
		var d: Vector3 = base.rotated(Vector3.UP, off)
		var bolt := BloodBolt.new()
		bolt.dir = d
		bolt.speed = BOLT_SPEED
		bolt.life = BOLT_LIFE
		bolt.hit_radius = BOLT_HIT_RADIUS
		bolt.damage = int(round(float(ATTACK_DAMAGE) * BOLT_DAMAGE_MULT))
		bolt.target = _player
		scene_root.add_child(bolt)
		bolt.global_position = global_position + d * 1.2 + Vector3.UP * 1.5
		bolt.setup_visual(_vfx_proj)

# ── SLAM(震地冲击波)─────────────────────────────────
func _tick_slam(delta: float) -> void:
	_face_player()
	velocity = Vector3.ZERO
	move_and_slide()
	_slam_timer += delta
	var speedup: float = PHASE2_SPEED_MULT if phase == 2 else 1.0
	var windup_t: float = SLAM_WINDUP / speedup

	# 预警:复用圆环,脉冲放大到 SLAM 半径
	if basic_warning != null:
		var in_windup: bool = _slam_timer < windup_t
		basic_warning.visible = in_windup
		if in_windup:
			var pulse: float = 0.85 + 0.15 * sin(_slam_timer * 18.0)
			var ratio: float = SLAM_RADIUS / 3.5 * pulse
			basic_warning.scale = Vector3(ratio, 1.0, ratio)
		else:
			basic_warning.scale = Vector3.ONE

	if not _slam_did_strike and _slam_timer >= windup_t:
		_slam_did_strike = true
		_do_slam_strike()

	if _slam_timer >= windup_t + SLAM_RECOVERY:
		if basic_warning != null:
			basic_warning.visible = false
			basic_warning.scale = Vector3.ONE
		_slam_cd = SLAM_COOLDOWN_P2 if phase == 2 else SLAM_COOLDOWN_P1
		_after_skill()

func _do_slam_strike() -> void:
	var at: Vector3 = global_position
	at.y += 0.1
	# 三圈错峰扩散 + 冲击波粒子 + 屏震
	_spawn_ring(at, 0.5, SLAM_RADIUS, 0.35, Color(1.0, 0.5, 0.15))
	_spawn_ring(at, 0.4, SLAM_RADIUS * 0.75, 0.45, Color(1.0, 0.3, 0.1))
	_spawn_ring(at, 0.3, SLAM_RADIUS * 0.5, 0.55, Color(0.9, 0.15, 0.08))
	_spawn_vfx(_vfx_wave, at, 1.8, 2.2)
	_shake()
	if _player == null or not is_instance_valid(_player):
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist <= SLAM_RADIUS:
		# 距离衰减:圆心 100% → 边缘 60%
		var fall: float = lerpf(1.0, 0.6, clampf(dist / SLAM_RADIUS, 0.0, 1.0))
		var dmg: int = int(round(float(ATTACK_DAMAGE) * SLAM_DAMAGE_MULT * fall))
		if _player.has_method("take_damage"):
			_player.take_damage(dmg, self)

# ── LEAP(跃斩,P2)────────────────────────────────────
func _tick_leap(delta: float) -> void:
	_leap_timer += delta
	match _leap_substate:
		0:  # CROUCH 蓄力下压
			_face_player()
			velocity = Vector3.ZERO
			move_and_slide()
			scale = Vector3.ONE.lerp(Vector3(1.15, 0.75, 1.15), clampf(_leap_timer / LEAP_CROUCH, 0.0, 1.0))
			if _leap_timer >= LEAP_CROUCH:
				_leap_substate = 1
				_leap_timer = 0.0
				_leap_from = global_position
				_leap_to = _capture_leap_target()
				scale = Vector3.ONE
				_spawn_telegraph(_leap_to, LEAP_RADIUS, LEAP_AIR)
		1:  # AIR 抛物线腾空(直接位移,无视地形碰撞)
			var t: float = clampf(_leap_timer / LEAP_AIR, 0.0, 1.0)
			var pos: Vector3 = _leap_from.lerp(_leap_to, t)
			pos.y += 4.0 * LEAP_PEAK_H * t * (1.0 - t)
			global_position = pos
			if _leap_timer >= LEAP_AIR:
				_leap_substate = 2
				_leap_timer = 0.0
				_do_leap_land()
		2:  # RECOVERY
			velocity = Vector3.ZERO
			move_and_slide()
			if _leap_timer >= LEAP_RECOVERY:
				_leap_cd = LEAP_COOLDOWN
				_after_skill()

# 落点 = 玩家当前位置,吸附到导航网格(防跳进墙里/坑里)
func _capture_leap_target() -> Vector3:
	var tgt: Vector3 = _player.global_position if (_player != null and is_instance_valid(_player)) else global_position
	var map: RID = get_world_3d().navigation_map
	var cp: Vector3 = NavigationServer3D.map_get_closest_point(map, tgt)
	if Vector2(cp.x - tgt.x, cp.z - tgt.z).length() < 2.0:
		return Vector3(tgt.x, global_position.y, tgt.z)
	return Vector3(cp.x, global_position.y, cp.z)

func _do_leap_land() -> void:
	var at: Vector3 = global_position
	at.y += 0.1
	_spawn_ring(at, 0.4, LEAP_RADIUS, 0.3, Color(1.0, 0.4, 0.1))
	_spawn_vfx(_vfx_cast, at, 1.5, 1.2)
	_shake()
	if _player != null and is_instance_valid(_player):
		if global_position.distance_to(_player.global_position) <= LEAP_RADIUS:
			if _player.has_method("take_damage"):
				_player.take_damage(int(round(float(ATTACK_DAMAGE) * LEAP_DAMAGE_MULT)), self)

# ── ROAR(P2 切换演出)─────────────────────────────────
func _tick_roar(delta: float) -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	_roar_timer -= delta
	if _roar_timer <= 0.0:
		_is_invulnerable = false
		_set_state(State.CHASE)

# ── 状态切换 ───────────────────────────────────────
func _set_state(new_state: int) -> void:
	var old_state := state
	state = new_state
	match new_state:
		State.CHASE:
			_chase_decision_timer = CHASE_DECISION_TIME
			_chase_think_timer = CHASE_THINK_INTERVAL
			_nav_repath_timer = 0.0
		State.ATTACK:
			_attack_phase_timer = 0.0
			_attack_did_strike = false
		State.SWEEP:
			_sweep_phase_timer = 0.0
			_sweep_did_strike = false
			_spawn_vfx(_vfx_cast, global_position, SWEEP_WINDUP + 0.4, 1.0)
		State.BOLT:
			_bolt_timer = 0.0
			_bolt_fired = false
			_spawn_vfx(_vfx_cast, global_position, BOLT_WINDUP + 0.3, 0.8)
		State.SLAM:
			_slam_timer = 0.0
			_slam_did_strike = false
			_spawn_vfx(_vfx_cast, global_position, SLAM_WINDUP + 0.4, 1.3)
		State.LEAP:
			_leap_substate = 0
			_leap_timer = 0.0
		State.CHARGE:
			_charge_substate = 0
			_charge_phase_timer = 0.0
			_charge_did_hit_player = false
			_spawn_vfx(_vfx_cast, global_position, CHARGE_WINDUP + 0.2, 1.1)
			if _player != null and is_instance_valid(_player):
				var d: Vector3 = _player.global_position - global_position
				d.y = 0.0
				_charge_dir = d.normalized() if d.length() > 0.001 else -global_transform.basis.z
			else:
				_charge_dir = -global_transform.basis.z
			_charge_dir.y = 0.0
			_charge_start_pos = global_position
			# 预警线长度 = 到第一堵墙的距离(层4),没墙则全长
			_charge_line_len = CHARGE_MAX_DISTANCE
			var space := get_world_3d().direct_space_state
			var q := PhysicsRayQueryParameters3D.create(
					global_position + Vector3.UP * 1.0,
					global_position + Vector3.UP * 1.0 + _charge_dir * CHARGE_MAX_DISTANCE)
			q.collision_mask = 4
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				_charge_line_len = maxf(2.0, (hit["position"] as Vector3).distance_to(global_position))
		State.ROAR:
			_roar_timer = ROAR_DURATION
			_is_invulnerable = true
			_spawn_vfx(_vfx_cast, global_position, ROAR_DURATION, 1.6)
			_spawn_ring(global_position + Vector3.UP * 0.1, 0.5, 7.0, 0.6, Color(1.0, 0.25, 0.1))
			_shake()
	state_changed.emit(old_state, new_state)

# ── 通用辅助 ─────────────────────────────────────────
func _face_player() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to_p: Vector3 = _player.global_position - global_position
	to_p.y = 0.0
	if to_p.length() > 0.001:
		look_at(global_position + to_p.normalized(), Vector3.UP)

func _shake() -> void:
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("_trigger_screen_shake"):
		cjm._trigger_screen_shake()

# 场景粒子:实例化 → 点燃 → life 秒后清场
func _spawn_vfx(ps: PackedScene, pos: Vector3, life: float, scale_f: float = 1.0) -> void:
	if ps == null:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var holder := Node3D.new()
	scene_root.add_child(holder)
	holder.global_position = pos
	holder.scale = Vector3.ONE * scale_f
	var vfx: Node = ps.instantiate()
	holder.add_child(vfx)
	_ignite(vfx)
	var tw: Tween = holder.create_tween()
	tw.tween_interval(life)
	tw.tween_callback(Callable(holder, "queue_free"))

# 随身粒子(冲锋尾迹):挂在自己身上
func _attach_vfx(ps: PackedScene, local_pos: Vector3) -> Node3D:
	if ps == null:
		return null
	var holder := Node3D.new()
	add_child(holder)
	holder.position = local_pos
	var vfx: Node = ps.instantiate()
	holder.add_child(vfx)
	_ignite(vfx)
	return holder

func _ignite(n: Node) -> void:
	if n is GPUParticles3D:
		(n as GPUParticles3D).emitting = true
	elif n is CPUParticles3D:
		(n as CPUParticles3D).emitting = true
	for c in n.get_children():
		_ignite(c)

# 程序化扩散冲击环:发光圆环从 from_r 扩到 to_r 并淡出
func _spawn_ring(pos: Vector3, from_r: float, to_r: float, dur: float, col: Color) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.82
	torus.outer_radius = 1.0
	torus.ring_segments = 40
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col.r, col.g, col.b, 0.85)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 4.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	torus.material = m
	mi.mesh = torus
	scene_root.add_child(mi)
	mi.global_position = pos
	mi.scale = Vector3.ONE * from_r
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(to_r, 1.0, to_r), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, dur)
	tw.chain().tween_callback(Callable(mi, "queue_free"))

# 落点预警圈(跃斩):红环脉冲 dur 秒后消失
func _spawn_telegraph(pos: Vector3, radius: float, dur: float) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.35
	torus.outer_radius = radius
	torus.ring_segments = 40
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.15, 0.1, 0.8)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.2, 0.05)
	m.emission_energy_multiplier = 4.5
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	torus.material = m
	mi.mesh = torus
	scene_root.add_child(mi)
	mi.global_position = pos + Vector3.UP * 0.1
	var tw: Tween = mi.create_tween()
	tw.tween_property(mi, "scale", Vector3(1.12, 1.0, 1.12), dur * 0.5)
	tw.tween_property(mi, "scale", Vector3.ONE, dur * 0.5)
	tw.tween_callback(Callable(mi, "queue_free"))

# ── 受伤 / 死亡 ───────────────────────────────────────
func take_damage(amount: int, source = null) -> void:
	if state == State.DEATH or amount <= 0 or _is_invulnerable:
		return
	var actual: int = int(round(float(amount) * damage_multiplier))
	current_health = clamp(current_health - actual, 0, MAX_HEALTH)
	if phase == 1 and current_health <= int(float(MAX_HEALTH) * PHASE2_HEALTH_RATIO):
		_enter_phase2()
	if current_health <= 0:
		_die(source, actual)

func _enter_phase2() -> void:
	phase = 2
	_set_state(State.ROAR)
	phase_changed.emit(2)
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("channel_charge", global_position, 3.0, 0.05)

# ── 状态效果(免控,只接受减速)─────────────────────
func apply_status(effect: String, duration: float) -> void:
	if state == State.DEATH or duration <= 0.0:
		return
	match effect:
		"frost", "freeze":
			apply_slow(0.3, duration)
		_:
			pass

func apply_slow(amount: float, duration: float) -> void:
	_slow_amount = max(_slow_amount, amount)
	_slow_timer = max(_slow_timer, duration)

# ── 烧地板触发 ─────────────────────────────────────
func _trigger_floor_burn() -> void:
	if _floor_burn_scene == null or _player == null:
		return
	var burn: Node = _floor_burn_scene.instantiate()
	if burn == null:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(burn)
	if burn is Node3D:
		var angle: float = randf() * TAU
		var dist: float = randf_range(FLOOR_BURN_NEAR_PLAYER_MIN, FLOOR_BURN_NEAR_PLAYER_MAX)
		var offset: Vector3 = Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		(burn as Node3D).global_position = _player.global_position + offset

# ── 死亡 ─────────────────────────────────────────────
func _die(source, overkill: int) -> void:
	if state == State.DEATH:
		return
	state = State.DEATH
	velocity = Vector3.ZERO
	_free_charge_trail()
	if charge_warning != null:
		charge_warning.visible = false
	if basic_warning != null:
		basic_warning.visible = false
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("explode", global_position, 4.0, 0.05)
		sfx.play("enemy_death", global_position, 3.0, 0.0)
	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null:
		var kill_dir: Vector3 = Vector3.FORWARD
		if source != null and source is Node3D and is_instance_valid(source):
			var d: Vector3 = global_position - (source as Node3D).global_position
			d.y = 0.0
			if d.length() > 0.001:
				kill_dir = d.normalized()
		cm.enemy_killed.emit(self, source, overkill, kill_dir)
	died.emit(self)
	var hud: Node = get_tree().get_first_node_in_group("hud") if get_tree() != null else null
	if hud == null:
		hud = get_node_or_null("/root/Main/HUD")
	if hud != null and hud.has_method("boss_killed_flash"):
		hud.boss_killed_flash()
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("_trigger_screen_shake"):
		cjm._trigger_screen_shake()
		await get_tree().create_timer(0.15).timeout
		if cjm != null and is_instance_valid(cjm) and cjm.has_method("_trigger_screen_shake"):
			cjm._trigger_screen_shake()
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.15, 0.2)
	tw.tween_property(self, "scale", Vector3.ONE * 0.001, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(Callable(self, "queue_free"))

# ── 血火弹(内部类:直线飞行,撞墙/命中玩家即爆)────────
class BloodBolt extends Node3D:
	var dir: Vector3 = Vector3.FORWARD
	var speed: float = 15.0
	var life: float = 1.8
	var hit_radius: float = 1.2
	var damage: int = 75
	var target: Node3D = null

	func setup_visual(proj_vfx: PackedScene) -> void:
		# 发光弹芯 + 点光 + 火焰粒子
		var core := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.22
		sph.height = 0.44
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(1.0, 0.4, 0.15)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.35, 0.1)
		m.emission_energy_multiplier = 5.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sph.material = m
		core.mesh = sph
		add_child(core)
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.4, 0.15)
		l.light_energy = 1.6
		l.omni_range = 4.0
		l.shadow_enabled = false
		add_child(l)
		if proj_vfx != null:
			var vfx: Node = proj_vfx.instantiate()
			add_child(vfx)
			_ignite_rec(vfx)

	func _ignite_rec(n: Node) -> void:
		if n is GPUParticles3D:
			(n as GPUParticles3D).emitting = true
		elif n is CPUParticles3D:
			(n as CPUParticles3D).emitting = true
		for c in n.get_children():
			_ignite_rec(c)

	func _physics_process(delta: float) -> void:
		var from: Vector3 = global_position
		var to: Vector3 = from + dir * speed * delta
		# 撞墙检测(层 4 = 场景碰撞)
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 4
		if not space.intersect_ray(q).is_empty():
			queue_free()
			return
		global_position = to
		life -= delta
		if life <= 0.0:
			queue_free()
			return
		if target != null and is_instance_valid(target):
			var d: Vector3 = target.global_position - global_position
			d.y = 0.0
			if d.length() <= hit_radius:
				if target.has_method("take_damage"):
					target.take_damage(damage, self)
				queue_free()
