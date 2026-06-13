extends CharacterBody3D

# enemy_base.gd — 所有近战追击型敌人的基础脚本。
# 5 态状态机:IDLE → CHASE → ATTACK → STAGGER → DEATH
# 通过 EnemyData (.tres) 注入数值,scene 里挂这个脚本即可。
# 子类(如 enemy_zombie.gd)用 extends 扩展专属行为(如肿胀走尸的死亡爆炸)。

signal died(enemy)
signal state_changed(old_state: int, new_state: int)

# ── 状态枚举 ─────────────────────────────────────────
enum State {
	IDLE = 0,
	CHASE = 1,
	ATTACK = 2,    # 内含 windup → strike → recovery 三个子阶段
	STAGGER = 3,   # 由 StaggerComponent.stagger_started(L2) 触发
	DEATH = 4,
}

# ── 调参 ─────────────────────────────────────────────
const NAV_REPATH_INTERVAL: float = 0.3   # 寻路目标更新频率
const DEATH_DURATION: float = 0.35

# ── 数据来源 ─────────────────────────────────────────
# data 期望是 EnemyData 资源(scripts/entities/enemy_data.gd 实例),
# 用 Resource 弱类型避免跨文件 class_name 解析问题。
@export var data: Resource = null

# ── 精英词缀(策划 03 §5.1)─────────────────────────
# 关卡组在场景里勾上对应词缀;运行时 _die() 触发对应行为。
# 熔火 = 死亡 1.0s 后在尸体处生成"地面延爆"(molten_pool)。
@export var is_molten: bool = false
const MOLTEN_POOL_PATH: String = "res://scenes/enemies/molten_pool.tscn"
const MOLTEN_DELAY: float = 1.0

# ── 运行时数值(从 data 复制,允许运行时改) ──────────
var max_health: int = 80
var current_health: int = 80
var move_speed: float = 4.2
var attack_damage: int = 12
var attack_range: float = 2.0
var detection_range: float = 12.0
var lose_aggro_range: float = 18.0
var attack_windup: float = 0.8
var attack_recovery: float = 0.4
var attack_hit_window: float = 0.2

# ── 状态机内部 ────────────────────────────────────────
var state: int = State.IDLE
var _player: Node3D = null
var _nav_repath_timer: float = 0.0
var _attack_timer: float = 0.0
var _attack_did_strike: bool = false

# ── 状态效果(冰冻/灼烧等)──────────────────────────
var is_frozen: bool = false
var _freeze_timer: float = 0.0

# ── 节点引用 ─────────────────────────────────────────
@onready var body_mesh: MeshInstance3D = $BodyMesh if has_node("BodyMesh") else null
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D if has_node("NavigationAgent3D") else null
@onready var stagger_comp: Node = $StaggerComponent if has_node("StaggerComponent") else null
@onready var knockback_comp: Node = $KnockbackComponent if has_node("KnockbackComponent") else null

# ── 生命周期 ─────────────────────────────────────────
func _ready() -> void:
	add_to_group("enemies")
	_apply_data()
	# 接 stagger 信号(L2 才打断 AI;L1 是纯视觉抖)
	if stagger_comp != null:
		if stagger_comp.has_signal("stagger_started"):
			stagger_comp.stagger_started.connect(_on_stagger_started)
		if stagger_comp.has_signal("stagger_ended"):
			stagger_comp.stagger_ended.connect(_on_stagger_ended)
	# 延后一帧抓 player 引用(允许 Player 后于 Enemy _ready)
	call_deferred("_acquire_player")

func _acquire_player() -> void:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		_player = arr[0] as Node3D

func _apply_data() -> void:
	if data == null:
		current_health = max_health
		return
	max_health = int(data.max_health)
	attack_damage = int(data.attack_damage)
	move_speed = float(data.move_speed)
	detection_range = float(data.detection_range)
	lose_aggro_range = float(data.lose_aggro_range)
	attack_range = float(data.attack_range)
	attack_windup = float(data.attack_windup)
	attack_recovery = float(data.attack_recovery)
	attack_hit_window = float(data.attack_hit_window)
	current_health = max_health

# ── 主循环 ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	# DEATH 不处理任何逻辑
	if state == State.DEATH:
		return
	# 击退期间组件接管 move_and_slide,本脚本完全让位
	if knockback_comp != null and knockback_comp.has_method("is_active") and knockback_comp.is_active():
		return
	# 冻结状态:定身,扣计时,不做任何 AI / move_and_slide 自身
	if is_frozen:
		_freeze_timer -= delta
		if _freeze_timer <= 0.0:
			_unfreeze()
		else:
			velocity = Vector3.ZERO
			move_and_slide()
			return
	# 没找到玩家就持续重试(避免顺序问题)
	if _player == null or not is_instance_valid(_player):
		_acquire_player()

	match state:
		State.IDLE:
			_tick_idle(delta)
		State.CHASE:
			_tick_chase(delta)
		State.ATTACK:
			_tick_attack(delta)
		State.STAGGER:
			_tick_stagger(delta)

# ── IDLE ─────────────────────────────────────────────
func _tick_idle(_delta: float) -> void:
	velocity = Vector3.ZERO
	move_and_slide()
	if _player == null:
		return
	if global_position.distance_to(_player.global_position) < detection_range:
		_set_state(State.CHASE)

# ── CHASE ─────────────────────────────────────────────
func _tick_chase(delta: float) -> void:
	if _player == null:
		_set_state(State.IDLE)
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist > lose_aggro_range:
		_set_state(State.IDLE)
		return
	if dist < attack_range:
		_set_state(State.ATTACK)
		return

	# 0.3s 节流:更新 NavAgent 目标
	_nav_repath_timer -= delta
	if _nav_repath_timer <= 0.0:
		_nav_repath_timer = NAV_REPATH_INTERVAL
		if nav_agent != null:
			nav_agent.target_position = _player.global_position

	# 朝下一个寻路点移动
	var dir: Vector3 = Vector3.ZERO
	if nav_agent != null and not nav_agent.is_navigation_finished():
		var next_pos: Vector3 = nav_agent.get_next_path_position()
		dir = next_pos - global_position
	# NavAgent 算不出像样方向(刚 spawn / 已"到达") → 直接朝玩家(简单追击的兜底,
	# 防止多怪在 NavAgent avoidance 死锁时全部站住)
	if dir.length() < 0.2:
		dir = _player.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.001:
		dir = dir.normalized()
		velocity = dir * move_speed
		# 朝向移动方向
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity = Vector3.ZERO
	move_and_slide()

# ── ATTACK(三阶段:windup → strike → recovery)─────────
func _tick_attack(delta: float) -> void:
	_attack_timer += delta
	var in_windup: bool = _attack_timer < attack_windup

	# 攻击期间始终朝向玩家,让 strike 落点更准
	if _player != null and is_instance_valid(_player):
		var to_player: Vector3 = _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.001:
			look_at(global_position + to_player.normalized(), Vector3.UP)

	# Windup 期间允许 50% 移速漂移,维持身位
	# (策划案 0.8s 前摇,但玩家 7m/s 比敌人 4.2m/s 快——前摇期间不动,玩家必逃出 strike 范围。
	#  漂移让 windup 不至于变成"敌人定身玩家自由跑"的空挥)
	# strike + recovery 阶段则完全停下,呈现"挥击-收招"的姿态
	if in_windup and _player != null and is_instance_valid(_player):
		var dist_now: float = global_position.distance_to(_player.global_position)
		if dist_now > attack_range * 0.7:
			# 离玩家不算贴脸,继续推进
			var step_dir: Vector3 = _player.global_position - global_position
			step_dir.y = 0.0
			if step_dir.length() > 0.001:
				velocity = step_dir.normalized() * (move_speed * 0.5)
			else:
				velocity = Vector3.ZERO
		else:
			# 已经贴脸,定身蓄力
			velocity = Vector3.ZERO
	else:
		velocity = Vector3.ZERO
	move_and_slide()

	# 进入命中阶段:windup 结束后只触发一次伤害
	if not _attack_did_strike and _attack_timer >= attack_windup:
		_do_strike()
		_attack_did_strike = true

	# 攻击循环结束:用 1.5× 容差判断是否还在范围内
	if _attack_timer >= attack_windup + attack_recovery:
		if _player != null and global_position.distance_to(_player.global_position) <= attack_range * 1.5:
			_enter_attack_cycle()
		else:
			_set_state(State.CHASE)

func _enter_attack_cycle() -> void:
	_attack_timer = 0.0
	_attack_did_strike = false
	# 锁定朝向玩家
	if _player != null:
		var to_player: Vector3 = _player.global_position - global_position
		to_player.y = 0.0
		if to_player.length() > 0.001:
			look_at(global_position + to_player.normalized(), Vector3.UP)

func _do_strike() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	# 容差 1.5×(=3m at attack_range 2m):允许玩家在 strike 一刹那小幅走开仍被打中。
	# 原 1.25× 在玩家 7m/s × windup 0.8s 下几乎必空挥。
	if global_position.distance_to(_player.global_position) > attack_range * 1.5:
		return
	if _player.has_method("take_damage"):
		_player.take_damage(attack_damage, self)

# ── STAGGER ───────────────────────────────────────────
func _tick_stagger(_delta: float) -> void:
	# 等 stagger_ended 信号回 CHASE,期间什么都不做(组件自己做视觉)
	velocity = Vector3.ZERO
	move_and_slide()

func _on_stagger_started(level: int, _duration: float) -> void:
	# 只有 L2 全身僵硬才打断 AI;L1 是 mesh 抖动,不影响行为
	if level >= 2 and state != State.DEATH:
		_attack_timer = 0.0
		_attack_did_strike = false
		_set_state(State.STAGGER)

func _on_stagger_ended() -> void:
	if state == State.STAGGER:
		# 退出僵直回追击
		if _player != null:
			_set_state(State.CHASE)
		else:
			_set_state(State.IDLE)

# ── 受伤 / 死亡 ───────────────────────────────────────
func take_damage(amount: int, source = null) -> void:
	if state == State.DEATH or amount <= 0:
		return
	current_health = clamp(current_health - amount, 0, max_health)
	# 被打到先点燃 CHASE(允许从 IDLE 直接进战斗,不必等检测距);冻结期间不切状态
	if state == State.IDLE and not is_frozen:
		_set_state(State.CHASE)
	if current_health <= 0:
		_die(source, amount)

# ── 状态效果(供 arrow / 技能调用)────────────────────
# effect: "frost" / "burn" / ...  duration: 秒
func apply_status(effect: String, duration: float) -> void:
	if state == State.DEATH or duration <= 0.0:
		return
	match effect:
		"frost", "freeze":
			apply_freeze(duration)
		_:
			# 其他状态后续扩展(灼烧/麻痹/中毒...)
			push_warning("EnemyBase: unhandled status '%s'" % effect)

func apply_freeze(duration: float) -> void:
	if state == State.DEATH:
		return
	is_frozen = true
	_freeze_timer = max(_freeze_timer, duration)  # 续帧:取较长时间
	# 中断当前攻击循环
	if state == State.ATTACK:
		_attack_timer = 0.0
		_attack_did_strike = false
	# 取消任何进行中的击退(冻结=定身)
	if knockback_comp != null and knockback_comp.has_method("cancel"):
		knockback_comp.cancel()
	velocity = Vector3.ZERO
	# 视觉:让 CombatJuiceManager 在 mesh 的 ShaderMaterial 上设 freeze_intensity=1
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("set_freeze"):
		cjm.set_freeze(self, true)

func _unfreeze() -> void:
	if not is_frozen:
		return
	is_frozen = false
	_freeze_timer = 0.0
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("set_freeze"):
		cjm.set_freeze(self, false)
	# 解冻后回 CHASE(玩家若还在范围内)
	if _player != null and is_instance_valid(_player) and global_position.distance_to(_player.global_position) < lose_aggro_range:
		_set_state(State.CHASE)
	else:
		_set_state(State.IDLE)

func _die(source, overkill: int) -> void:
	if state == State.DEATH:
		return
	var was_frozen: bool = is_frozen
	_set_state(State.DEATH)
	velocity = Vector3.ZERO
	# 立即停止击退:否则 KnockbackComponent._physics_process 会在死亡缩放动画
	# (scale -> Vector3.ZERO) 期间继续对本体 move_and_slide,基底退化导致
	# 每帧刷屏 "det == 0"(Transform 不可逆)。
	if knockback_comp != null and knockback_comp.has_method("cancel"):
		knockback_comp.cancel()
	# 广播击杀事件给 CombatManager(juice/掉落系统监听)
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
	# 熔火词缀:延迟 1s 后在尸体处生成地面延爆
	if is_molten:
		_spawn_molten_pool_deferred()
	if was_frozen:
		_spawn_freeze_shatter()
		# 立刻消失,不走缩放动画(碎裂代替)
		queue_free()
	else:
		# 普通死亡:缩放消失(简易死亡演出,后续接动画)
		var tw: Tween = create_tween()
		tw.tween_property(self, "scale", Vector3.ZERO, DEATH_DURATION)
		tw.tween_callback(Callable(self, "queue_free"))

# 熔火词缀:延迟 MOLTEN_DELAY 秒后在尸体位置生成 molten_pool。
# 用一个 Timer + 当前场景树驻留(死亡后 self 会 queue_free,所以位置要先抓快照)
func _spawn_molten_pool_deferred() -> void:
	if not ResourceLoader.exists(MOLTEN_POOL_PATH):
		return
	var scn: PackedScene = load(MOLTEN_POOL_PATH)
	if scn == null:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var pos_snapshot: Vector3 = global_position
	var t: Timer = Timer.new()
	t.one_shot = true
	t.wait_time = MOLTEN_DELAY
	scene_root.add_child(t)
	t.timeout.connect(func() -> void:
		var inst: Node = scn.instantiate()
		if inst is Node3D:
			scene_root.add_child(inst)
			(inst as Node3D).global_position = pos_snapshot
		t.queue_free()
	)
	t.start()

# 冰冻碎裂:在死亡位置生成几个蓝色碎块向外飞散并淡出
func _spawn_freeze_shatter() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var shard_count: int = 7
	var origin: Vector3 = global_position + Vector3(0, 0.9, 0)
	for i in range(shard_count):
		var shard: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.16, 0.16, 0.16)
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.78, 1.0, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.55, 0.95, 1.0)
		mat.emission_energy_multiplier = 0.6
		mat.metallic = 0.5
		mat.roughness = 0.15
		box.material = mat
		shard.mesh = box
		scene_root.add_child(shard)
		shard.global_position = origin
		# 随机半球向外 + 上方分量
		var dir: Vector3 = Vector3(randf() * 2.0 - 1.0, randf() * 0.8 + 0.4, randf() * 2.0 - 1.0).normalized()
		var fly: float = randf_range(1.4, 2.2)
		var tw: Tween = shard.create_tween().set_parallel(true)
		tw.tween_property(shard, "global_position", origin + dir * fly, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(shard, "scale", Vector3.ZERO, 0.5).set_delay(0.15)
		tw.tween_property(shard, "rotation", Vector3(randf_range(-PI, PI), randf_range(-PI, PI), randf_range(-PI, PI)), 0.5)
		tw.chain().tween_callback(Callable(shard, "queue_free"))

# ── 工具 ─────────────────────────────────────────────
func _set_state(new_state: int) -> void:
	if new_state == state:
		return
	var old: int = state
	state = new_state
	# 进入态钩子
	match new_state:
		State.ATTACK:
			_enter_attack_cycle()
		State.CHASE:
			_nav_repath_timer = 0.0  # 立刻 repath
	state_changed.emit(old, new_state)
