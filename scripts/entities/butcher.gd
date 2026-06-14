extends CharacterBody3D

# Butcher — 全 Demo 唯一 Boss(策划 03 §6)。
# MVP 范围:普攻 + 冲锋(撞墙硬直 +25% 承伤)+ 单象限烧地板 + P1/P2 切换 + 咆哮演出。
# 留 v2:肉钩、践踏、P2 全场轮燃、新场景、检查点。
#
# 状态机:
#   IDLE → CHASE → ATTACK (windup → strike → recovery) → CHASE
#                     → CHARGE (windup → dash → wall_stun) → CHASE
#                     → ROAR (1.5s,P2 切换演出,无敌)→ CHASE
#                     → DEATH (终态)
#
# 控制免疫(策划 03 §7.2):
#   - 不挂 KnockbackComponent → 击退完全无效
#   - 挂 StaggerComponent 但 stagger_started 信号不连接到本脚本 → 视觉 squeeze 但不打断 AI
#   - apply_status("frost") 改为 30% 减速 + 短 L2 视觉

signal phase_changed(new_phase: int)
signal died(self_ref)
signal state_changed(old_state: int, new_state: int)

# ── 数值(策划 03 §6 锚点)─────────────────────────
const MAX_HEALTH: int = 30000  # V3.0 守门人 (rift_monsters.csv guardian·2026 调)
const ATTACK_DAMAGE: int = 150  # V3.0 守门人 (rift_monsters.csv guardian·2026 调)
const PHASE2_HEALTH_RATIO: float = 0.5

const MOVE_SPEED: float = 4.0           # 慢悠悠走路
const CHARGE_SPEED: float = 14.0        # 冲锋高速

# 普攻三阶段
const BASIC_WINDUP: float = 0.7
const BASIC_STRIKE: float = 0.25
const BASIC_RECOVERY: float = 0.5
const BASIC_HIT_RANGE: float = 3.5
const BASIC_ENTER_RANGE: float = 3.0    # 进入此距离触发普攻

# 冲锋
const CHARGE_WINDUP: float = 1.2
const CHARGE_MAX_DISTANCE: float = 25.0
const CHARGE_TRIGGER_RANGE: float = 6.0  # 玩家在此距离外才考虑冲锋
const CHARGE_HIT_RADIUS: float = 1.6     # 冲锋途中撞到玩家就伤害

# 撞墙硬直
const WALL_STUN_DURATION: float = 3.0
const WALL_STUN_DAMAGE_MULT: float = 1.25

# 横扫(策划 03 §6 贴脸 AOE,每 N 次普攻后改为横扫)
const SWEEP_WINDUP: float = 0.55
const SWEEP_STRIKE: float = 0.35
const SWEEP_RECOVERY: float = 0.55
const SWEEP_RADIUS: float = 5.5
const SWEEP_DAMAGE_MULT: float = 1.2  # 75 × 1.2 = 90
const SWEEP_EVERY_P1: int = 3   # P1 每 3 次普攻换一次横扫
const SWEEP_EVERY_P2: int = 2   # P2 每 2 次

# P2 切换
const ROAR_DURATION: float = 1.5
const PHASE2_SPEED_MULT: float = 1.3    # P2 攻速 +30%(timer 缩短)

# 烧地板
const FLOOR_BURN_INTERVAL_P1: float = 18.0
const FLOOR_BURN_INTERVAL_P2: float = 12.0
const FLOOR_BURN_FIRST_DELAY: float = 40.0
const FLOOR_BURN_NEAR_PLAYER_MIN: float = 3.0
const FLOOR_BURN_NEAR_PLAYER_MAX: float = 6.0
const FLOOR_BURN_SCENE_PATH: String = "res://scenes/enemies/floor_burn_zone.tscn"

# AI / 寻路
const ENGAGE_RANGE: float = 30.0
const NAV_REPATH_INTERVAL: float = 0.3
const CHASE_DECISION_TIME: float = 1.5  # CHASE 期间走这么久还没贴脸 → 考虑冲锋

# 状态枚举
enum State { IDLE, CHASE, ATTACK, CHARGE, ROAR, DEATH, SWEEP }

# ── 运行时 ─────────────────────────────────────────
var current_health: int = MAX_HEALTH
var phase: int = 1
var damage_multiplier: float = 1.0       # 撞墙硬直时 = 1.25,其他 1.0
var state: int = State.IDLE

var _player: Node3D = null
var _floor_burn_scene: PackedScene = null

# CHASE 子状态
var _chase_decision_timer: float = 0.0
var _nav_repath_timer: float = 0.0

# ATTACK 子状态
var _attack_phase_timer: float = 0.0
var _attack_did_strike: bool = false
var _basic_attack_count: int = 0  # 累积普攻次数,达到阈值改横扫

# SWEEP 子状态
var _sweep_phase_timer: float = 0.0
var _sweep_did_strike: bool = false

# CHARGE 子状态
var _charge_substate: int = 0            # 0 windup, 1 dash, 2 wall_stun
var _charge_phase_timer: float = 0.0
var _charge_dir: Vector3 = Vector3.ZERO
var _charge_start_pos: Vector3 = Vector3.ZERO
var _charge_did_hit_player: bool = false  # dash 期间最多伤害一次

# ROAR
var _roar_timer: float = 0.0
var _is_invulnerable: bool = false       # ROAR 期间 true

# 烧地板
var _floor_burn_timer: float = FLOOR_BURN_FIRST_DELAY

# 减速
var _slow_amount: float = 0.0            # 0 ~ 0.3
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
	# V3.13:E(arrow_storm)/ 多重箭等通过 EntityRegistry.enemies 拿目标,
	# 之前 boss 没注册 → AOE/引导永远跳过 boss → "E 技能打 boss 没伤害"。
	var reg: Node = get_node_or_null("/root/EntityRegistry")
	if reg != null and reg.has_method("register_enemy"):
		reg.register_enemy(self)
	# 系统组的 ProgressionManager 用此 meta 给玩家 XP
	set_meta("monster_id", &"butcher")
	set_meta("monster_level", 7)
	set_meta("drop_source", 3)  # DropSystem.Source.BUTCHER = 3(SpawnTrigger 会覆盖,这是直接实例化的 fallback)
	current_health = MAX_HEALTH
	if charge_warning != null:
		charge_warning.visible = false
	if basic_warning != null:
		basic_warning.visible = false
	if ResourceLoader.exists(FLOOR_BURN_SCENE_PATH):
		_floor_burn_scene = load(FLOOR_BURN_SCENE_PATH)
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

	# 减速衰减
	if _slow_timer > 0.0:
		_slow_timer -= delta
		if _slow_timer <= 0.0:
			_slow_amount = 0.0

	if _player == null or not is_instance_valid(_player):
		_acquire_player()

	# 烧地板独立 timer(IDLE/ROAR/DEATH 不计时)
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
		State.ROAR:
			_tick_roar(delta)

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
		# 每 N 次普攻改为横扫(P2 频率更高)
		var threshold: int = SWEEP_EVERY_P2 if phase == 2 else SWEEP_EVERY_P1
		if _basic_attack_count >= threshold:
			_basic_attack_count = 0
			_set_state(State.SWEEP)
		else:
			_basic_attack_count += 1
			_set_state(State.ATTACK)
		return

	# CHASE 决策计时:走一会儿还没贴上,如果玩家拉得很远就冲锋
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
		velocity = dir * (MOVE_SPEED * (1.0 - _slow_amount))
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity = Vector3.ZERO
	move_and_slide()

# ── ATTACK(普攻三阶段)──────────────────────────────
func _tick_attack(delta: float) -> void:
	# 朝玩家锁定
	if _player != null:
		var to_p: Vector3 = _player.global_position - global_position
		to_p.y = 0.0
		if to_p.length() > 0.001:
			look_at(global_position + to_p.normalized(), Vector3.UP)
	velocity = Vector3.ZERO
	move_and_slide()

	_attack_phase_timer += delta
	# P2 攻速 +30%(timer 走得更快)
	var speedup: float = PHASE2_SPEED_MULT if phase == 2 else 1.0
	var windup_t: float = BASIC_WINDUP / speedup
	var total_t: float = (BASIC_WINDUP + BASIC_STRIKE + BASIC_RECOVERY) / speedup

	# Windup 期间显示地面圆环预警
	if basic_warning != null:
		var in_windup: bool = _attack_phase_timer < windup_t
		basic_warning.visible = in_windup

	if not _attack_did_strike and _attack_phase_timer >= windup_t:
		_do_basic_strike()
		_attack_did_strike = true

	if _attack_phase_timer >= total_t:
		if basic_warning != null:
			basic_warning.visible = false
		_set_state(State.CHASE)

func _do_basic_strike() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if global_position.distance_to(_player.global_position) > BASIC_HIT_RANGE:
		return
	if _player.has_method("take_damage"):
		_player.take_damage(ATTACK_DAMAGE, self)

# ── SWEEP(横扫,贴脸 AOE)───────────────────────────────
func _tick_sweep(delta: float) -> void:
	# 锁朝向玩家,完全不动
	if _player != null:
		var to_p: Vector3 = _player.global_position - global_position
		to_p.y = 0.0
		if to_p.length() > 0.001:
			look_at(global_position + to_p.normalized(), Vector3.UP)
	velocity = Vector3.ZERO
	move_and_slide()

	_sweep_phase_timer += delta
	var speedup: float = PHASE2_SPEED_MULT if phase == 2 else 1.0
	var windup_t: float = SWEEP_WINDUP / speedup
	var strike_end: float = (SWEEP_WINDUP + SWEEP_STRIKE) / speedup
	var total_t: float = (SWEEP_WINDUP + SWEEP_STRIKE + SWEEP_RECOVERY) / speedup

	# Windup 期间显示放大版圆环预警(复用 BasicAttackWarning)
	if basic_warning != null:
		var in_windup: bool = _sweep_phase_timer < windup_t
		basic_warning.visible = in_windup
		# 横扫范围更大,把预警圆环 scale 放大
		if in_windup:
			var ratio: float = SWEEP_RADIUS / 3.5  # BasicAttackWarning 默认外径 3.5
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
		_set_state(State.CHASE)

func _do_sweep_strike() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 半径内(SWEEP_RADIUS,无朝向限制 = 360°,贴脸全覆盖)
	if global_position.distance_to(_player.global_position) > SWEEP_RADIUS:
		return
	if _player.has_method("take_damage"):
		var dmg: int = int(round(float(ATTACK_DAMAGE) * SWEEP_DAMAGE_MULT))
		_player.take_damage(dmg, self)
	# 屏震点缀
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("_trigger_screen_shake"):
		cjm._trigger_screen_shake()

# ── CHARGE(冲锋三阶段)──────────────────────────────
func _tick_charge(delta: float) -> void:
	_charge_phase_timer += delta

	match _charge_substate:
		0:  # WINDUP — 锁朝向,蓄力,显示预警
			velocity = Vector3.ZERO
			if _charge_dir.length() > 0.001:
				look_at(global_position + _charge_dir, Vector3.UP)
			move_and_slide()
			# 预警线随蓄力变长 / 变红
			if charge_warning != null:
				var t: float = clamp(_charge_phase_timer / CHARGE_WINDUP, 0.0, 1.0)
				charge_warning.visible = true
				charge_warning.scale = Vector3(1.0, 1.0, t)
			if _charge_phase_timer >= CHARGE_WINDUP:
				_charge_substate = 1
				_charge_phase_timer = 0.0
				_charge_did_hit_player = false
				if charge_warning != null:
					charge_warning.visible = false

		1:  # DASH — 直线冲撞
			velocity = _charge_dir * CHARGE_SPEED
			move_and_slide()
			# 撞玩家(dash 中只判一次)
			if not _charge_did_hit_player and _player != null and is_instance_valid(_player):
				if global_position.distance_to(_player.global_position) < CHARGE_HIT_RADIUS:
					if _player.has_method("take_damage"):
						_player.take_damage(ATTACK_DAMAGE, self)
					_charge_did_hit_player = true
			# 撞墙判定:slide collision 法线接近水平
			var hit_wall: bool = false
			for i in range(get_slide_collision_count()):
				var col: KinematicCollision3D = get_slide_collision(i)
				if col == null:
					continue
				var n: Vector3 = col.get_normal()
				if abs(n.y) < 0.5:
					hit_wall = true
					break
			var dashed: float = global_position.distance_to(_charge_start_pos)
			if hit_wall:
				_enter_wall_stun()
			elif dashed >= CHARGE_MAX_DISTANCE:
				# 冲到极限没撞墙 → 直接结束回 CHASE
				_set_state(State.CHASE)

		2:  # WALL_STUN — 撞墙硬直,承伤 +25%
			velocity = Vector3.ZERO
			move_and_slide()
			if _charge_phase_timer >= WALL_STUN_DURATION:
				damage_multiplier = 1.0
				_set_state(State.CHASE)

func _enter_wall_stun() -> void:
	_charge_substate = 2
	_charge_phase_timer = 0.0
	damage_multiplier = WALL_STUN_DAMAGE_MULT
	# 撞墙屏震(策划 §3 P0 三大震动触发之一)
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("_trigger_screen_shake"):
		cjm._trigger_screen_shake()

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
			_nav_repath_timer = 0.0
		State.ATTACK:
			_attack_phase_timer = 0.0
			_attack_did_strike = false
		State.SWEEP:
			_sweep_phase_timer = 0.0
			_sweep_did_strike = false
		State.CHARGE:
			_charge_substate = 0
			_charge_phase_timer = 0.0
			_charge_did_hit_player = false
			# 锁定冲锋方向(玩家方向)
			if _player != null and is_instance_valid(_player):
				var d: Vector3 = _player.global_position - global_position
				d.y = 0.0
				if d.length() > 0.001:
					_charge_dir = d.normalized()
				else:
					_charge_dir = -global_transform.basis.z
			else:
				_charge_dir = -global_transform.basis.z
			_charge_dir.y = 0.0
			_charge_start_pos = global_position
		State.ROAR:
			_roar_timer = ROAR_DURATION
			_is_invulnerable = true
			# 短屏震烘托咆哮
			var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
			if cjm != null and cjm.has_method("_trigger_screen_shake"):
				cjm._trigger_screen_shake()
	state_changed.emit(old_state, new_state)

# ── 受伤 / 死亡 ───────────────────────────────────────
func take_damage(amount: int, source = null) -> void:
	if state == State.DEATH or amount <= 0 or _is_invulnerable:
		return
	# 撞墙硬直窗口承伤 +25%
	var actual: int = int(round(float(amount) * damage_multiplier))
	current_health = clamp(current_health - actual, 0, MAX_HEALTH)
	# P1 → P2 切换
	if phase == 1 and current_health <= int(float(MAX_HEALTH) * PHASE2_HEALTH_RATIO):
		_enter_phase2()
	if current_health <= 0:
		_die(source, actual)

func _enter_phase2() -> void:
	phase = 2
	_set_state(State.ROAR)
	phase_changed.emit(2)
	# Boss P2 咆哮 SFX(charge 充能音效复用作咆哮)
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("channel_charge", global_position, 3.0, 0.05)

# ── 状态效果(免控,只接受减速)─────────────────────
func apply_status(effect: String, duration: float) -> void:
	if state == State.DEATH or duration <= 0.0:
		return
	match effect:
		"frost", "freeze":
			# 屠夫免冻,只表现为 30% 减速 + 视觉
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
		# 在玩家附近 [3, 6] 米的随机方向铺一片
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
	if charge_warning != null:
		charge_warning.visible = false
	if basic_warning != null:
		basic_warning.visible = false
	# Boss 死亡 SFX(火焰爆炸 + enemy_death 复合)
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("explode", global_position, 4.0, 0.05)
		sfx.play("enemy_death", global_position, 3.0, 0.0)
	# 广播击杀(系统组 ProgressionManager 据此给 XP;Inventory 据此掉传奇)
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
	# 死亡演出:全屏白闪 + 大屏震 + 慢放缩放(策划 §3 P0 + §6 屠夫死亡走脚本演出)
	var hud: Node = get_tree().get_first_node_in_group("hud") if get_tree() != null else null
	if hud == null:
		# 兜底:按节点名找
		hud = get_node_or_null("/root/Main/HUD")
	if hud != null and hud.has_method("boss_killed_flash"):
		hud.boss_killed_flash()
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("_trigger_screen_shake"):
		cjm._trigger_screen_shake()
		# 加强:0.15s 后再震一次,凑成"撞击 + 余震"
		await get_tree().create_timer(0.15).timeout
		if cjm != null and is_instance_valid(cjm) and cjm.has_method("_trigger_screen_shake"):
			cjm._trigger_screen_shake()
	# 慢动作 0.3s + 缩放消失(原本 0.7s,加长到 1.2s 给"句号感")
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ONE * 1.15, 0.2)  # 短暂膨胀
	tw.tween_property(self, "scale", Vector3.ONE * 0.001, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(Callable(self, "queue_free"))
