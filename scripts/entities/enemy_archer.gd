extends "res://scripts/entities/enemy_base.gd"

# EnemyArcher — 骷髅弓手(远程驻射)
# 行为(rift_monsters.csv §骷髅弓手):
#   - 在 RETREAT_DISTANCE..attack_range 之间停下射箭(默认 8~18m)
#   - 玩家近于 RETREAT_DISTANCE → 后撤(120% 移速,简化为常态后撤,无 3s 冷却)
#   - 玩家远于 attack_range → 走近
#   - 射箭:CD=2.0s,攻击 = ATK×1.0,前摇 attack_windup,弹体走 enemy_arrow.tscn
# 完全 override _tick_chase / _tick_attack,不进基类的近战 ATTACK 子状态机

const DEFAULT_DATA_PATH: String = "res://scripts/entities/data/skeleton_archer.tres"
const ARROW_SCENE_PATH: String = "res://scenes/enemies/enemy_arrow.tscn"
const RETREAT_DISTANCE: float = 8.0
const SHOT_COOLDOWN: float = 2.0
const ARROW_SPEED: float = 18.0

var _shot_cd_timer: float = 0.0
var _windup_timer: float = 0.0
var _is_winding_up: bool = false

func _ready() -> void:
	if data == null and ResourceLoader.exists(DEFAULT_DATA_PATH):
		data = load(DEFAULT_DATA_PATH)
	super._ready()

# 让 chase 兼具"射击决策":在射程内停下蓄力 + 射出
func _tick_chase(delta: float) -> void:
	if _player == null:
		_set_state(State.IDLE)
		return
	var dist: float = global_position.distance_to(_player.global_position)
	if dist > lose_aggro_range:
		_set_state(State.IDLE)
		return

	_shot_cd_timer = max(0.0, _shot_cd_timer - delta)

	# 一直朝玩家
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.001:
		look_at(global_position + to_player.normalized(), Vector3.UP)

	# 蓄力中:不动,蓄完发射
	if _is_winding_up:
		velocity = Vector3.ZERO
		_windup_timer -= delta
		if _windup_timer <= 0.0:
			_is_winding_up = false
			_fire_arrow()
			_shot_cd_timer = SHOT_COOLDOWN
		move_and_slide()
		return

	# 决策位移
	var spd: float = move_speed * (1.0 - _slow_amount)
	if dist < RETREAT_DISTANCE:
		# 后撤(120%)
		var away: Vector3 = global_position - _player.global_position
		away.y = 0.0
		if away.length() > 0.001:
			velocity = away.normalized() * (spd * 1.2)
		else:
			velocity = Vector3.ZERO
	elif dist > attack_range:
		# 走近
		if to_player.length() > 0.001:
			velocity = to_player.normalized() * spd
		else:
			velocity = Vector3.ZERO
	else:
		# 在 [RETREAT, attack_range] 窗口内 → 停下,CD 好就开始蓄力
		velocity = Vector3.ZERO
		if _shot_cd_timer <= 0.0:
			_is_winding_up = true
			_windup_timer = attack_windup
	move_and_slide()

# 不进基类 ATTACK(那是近战);chase 自己处理射击
func _tick_attack(_delta: float) -> void:
	# 兜底:意外进入 ATTACK,直接退回 CHASE 让 chase tick 决策
	_set_state(State.CHASE)

func _fire_arrow() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if not ResourceLoader.exists(ARROW_SCENE_PATH):
		return
	var scn: PackedScene = load(ARROW_SCENE_PATH)
	if scn == null:
		return
	var arrow: Node = scn.instantiate()
	if arrow == null:
		return
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(arrow)
	if arrow is Node3D:
		var spawn: Vector3 = global_position + Vector3(0, 1.2, 0)
		(arrow as Node3D).global_position = spawn
		var to: Vector3 = _player.global_position + Vector3(0, 1.0, 0) - spawn
		to.y = 0.0
		if to.length() < 0.001:
			(arrow as Node3D).queue_free()
			return
		var dir: Vector3 = to.normalized()
		(arrow as Node3D).look_at(spawn + dir, Vector3.UP)
		if "direction" in arrow:
			arrow.direction = dir
		if "speed" in arrow:
			arrow.speed = ARROW_SPEED
		if "damage" in arrow:
			arrow.damage = attack_damage
		if "shooter" in arrow:
			arrow.shooter = self
