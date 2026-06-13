extends CharacterBody3D

# Valkyrie — 女武神召唤物。
# AI: 找最近敌人 → NavMesh 追击 → 进入近战范围打,1.5s 间隔 → 单次伤害 = 武器均伤×2
# 生命周期 lifetime 秒到期自动消失。
# 同时上限由 SkillExecutor 管理(group "summon_valkyrie_summon")。

signal expired(self_ref)

const MOVE_SPEED: float = 6.0
const ATTACK_RANGE: float = 1.8
const ATTACK_INTERVAL: float = 1.5
const NAV_REPATH_INTERVAL: float = 0.3
const ENEMY_DEATH_STATE: int = 4  # enemy_base.State.DEATH

@export var lifetime: float = 20.0
# 武器均伤×2 = 15×2 = 30(占位,后续接装备表后从 player 属性算)
@export var attack_damage: int = 30

var _target: Node3D = null
var _attack_timer: float = 0.0
var _nav_timer: float = 0.0
var _life_timer: float = 0.0
var _alive: bool = true

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D if has_node("NavigationAgent3D") else null
@onready var body_mesh: MeshInstance3D = $BodyMesh if has_node("BodyMesh") else null

func _ready() -> void:
	add_to_group("allies")
	_life_timer = lifetime

func _physics_process(delta: float) -> void:
	if not _alive:
		return
	# 生命周期递减
	_life_timer -= delta
	if _life_timer <= 0.0:
		_expire()
		return

	# 目标失效就重新选最近的(死亡/释放都失效)
	if not _target_valid():
		_target = _find_nearest_enemy()

	if _target == null:
		velocity = Vector3.ZERO
		move_and_slide()
		return

	var dist: float = global_position.distance_to(_target.global_position)
	if dist > ATTACK_RANGE:
		_chase(delta)
	else:
		_attack(delta)

func _target_valid() -> bool:
	if _target == null or not is_instance_valid(_target):
		return false
	# 敌人死亡(state == DEATH)就失效
	if "state" in _target and int(_target.state) == ENEMY_DEATH_STATE:
		return false
	return true

func _chase(delta: float) -> void:
	_nav_timer -= delta
	if _nav_timer <= 0.0:
		_nav_timer = NAV_REPATH_INTERVAL
		if nav_agent != null:
			nav_agent.target_position = _target.global_position

	var dir: Vector3 = Vector3.ZERO
	if nav_agent != null:
		dir = nav_agent.get_next_path_position() - global_position
	else:
		dir = _target.global_position - global_position
	dir.y = 0.0
	if dir.length() > 0.001:
		dir = dir.normalized()
		velocity = dir * MOVE_SPEED
		look_at(global_position + dir, Vector3.UP)
	else:
		velocity = Vector3.ZERO
	move_and_slide()

func _attack(delta: float) -> void:
	# 朝向目标
	var fwd: Vector3 = _target.global_position - global_position
	fwd.y = 0.0
	if fwd.length() > 0.001:
		look_at(global_position + fwd.normalized(), Vector3.UP)
	velocity = Vector3.ZERO
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

func _find_nearest_enemy() -> Node3D:
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var best: Node3D = null
	var best_dist: float = INF
	for e in enemies:
		if not is_instance_valid(e) or not (e is Node3D):
			continue
		# 跳过已死/将死目标
		if "state" in e and int(e.state) == ENEMY_DEATH_STATE:
			continue
		var d: float = global_position.distance_to((e as Node3D).global_position)
		if d < best_dist:
			best_dist = d
			best = e
	return best

# 超时自然消失
func _expire() -> void:
	if not _alive:
		return
	_alive = false
	expired.emit(self)
	var tw: Tween = create_tween()
	tw.tween_property(self, "scale", Vector3.ZERO, 0.4)
	tw.tween_callback(Callable(self, "queue_free"))

# 公共 API:被 SkillExecutor 提前移除(召唤上限超出时)
func dismiss() -> void:
	_expire()
