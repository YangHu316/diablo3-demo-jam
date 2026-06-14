extends Node

# LootManager (Autoload): 击杀 -> 掉落判定 -> 地面 spawn -> 入包链路总装 (任务3).
# 把纯逻辑 DropSystem 接到场景: 监听 CombatManager.enemy_killed, 在死亡位置生成 LootDrop.
#
# 怪物实例元数据约定 (战斗① 挂; 缺省兜底):
#   drop_source: int  (DropSystem.Source, 默认 TRASH)
#   monster_level: int (默认玩家当前等级)
# 精英组击杀: 战斗① 杀完一组精英调 LootManager.notify_elite_group_killed() 喂软保底.

const LOOT_SCENE_PATH: String = "res://scenes/loot/loot_drop.tscn"
const PROGRESS_BALL_SCENE_PATH: String = "res://scenes/loot/progress_ball.tscn"

var drop_system: DropSystem = null
var _loot_scene: PackedScene = null
var _ball_scene: PackedScene = null
var _gen: ItemGenerator = null

func _ready() -> void:
	_loot_scene = load(LOOT_SCENE_PATH)
	if ResourceLoader.exists(PROGRESS_BALL_SCENE_PATH):
		_ball_scene = load(PROGRESS_BALL_SCENE_PATH)
	_setup_drop_system()
	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null and cm.has_signal("enemy_killed"):
		cm.enemy_killed.connect(_on_enemy_killed)

func _setup_drop_system() -> void:
	var dt: Node = get_node_or_null("/root/DataTables")
	if dt == null:
		return
	_gen = ItemGenerator.new(dt)
	drop_system = DropSystem.new(dt, _gen)

func _process(delta: float) -> void:
	# 推进保底计时 (暂停时由 GameManager 决定是否调; 此处简单累计).
	if drop_system != null:
		drop_system.tick(delta)

func _on_enemy_killed(enemy, _killer, _overkill: int, _dir: Vector3) -> void:
	var origin: Vector3 = Vector3.ZERO
	if enemy != null and is_instance_valid(enemy) and enemy is Node3D:
		origin = (enemy as Node3D).global_position

	# 精英: 据 elites.csv「进度球数」在死亡位置掉进度球 (与装备掉落并行).
	_maybe_spawn_progress_balls(enemy, origin)

	if drop_system == null:
		return
	var source: int = DropSystem.Source.TRASH
	var mlevel: int = _player_level()
	if enemy != null and is_instance_valid(enemy):
		if enemy.has_meta("drop_source"):
			source = int(enemy.get_meta("drop_source"))
		if enemy.has_meta("monster_level"):
			mlevel = int(enemy.get_meta("monster_level"))

	var items: Array[ItemInstance] = drop_system.roll_drop(source, mlevel)
	if items.is_empty():
		return

	_spawn_loot(items, origin)

# 精英进度球: 查怪物 monster_id -> DataTables.get_elite_ball_count. >0 则散开生成 N 个球.
# 每球 setup(每球进度%); 球进范围自动吸取调 RiftManager.add_progress_ball.
func _maybe_spawn_progress_balls(enemy, origin: Vector3) -> void:
	if _ball_scene == null or enemy == null or not is_instance_valid(enemy):
		return
	if not enemy.has_meta("monster_id"):
		return
	var dt: Node = get_node_or_null("/root/DataTables")
	if dt == null or not dt.has_method("get_elite_ball_count"):
		return
	var mid: String = String(enemy.get_meta("monster_id"))
	var count: int = dt.get_elite_ball_count(mid)
	if count <= 0:
		return
	var pct: float = dt.get_elite_per_ball_pct(mid)
	# 多球散开, 半径随数量微调.
	var radius: float = 0.0 if count == 1 else clampf(0.6 + float(count) * 0.2, 0.6, 2.0)
	for i in range(count):
		var ball := _ball_scene.instantiate()
		_attach_to_world(ball)
		var angle: float = TAU * float(i) / float(max(count, 1))
		var pos: Vector3 = origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if ball is Node3D:
			(ball as Node3D).global_position = pos
		ball.setup(pct)

# 多件掉落在落点周围散开. 守门人爆装(14件)用更大半径, 满地光柱观感.
func _spawn_loot(items: Array[ItemInstance], origin: Vector3) -> void:
	var inv: Node = get_node_or_null("/root/Inventory")
	var n: int = items.size()
	# 件数多(守门人爆装)时半径随之放大, 避免光柱重叠.
	var radius: float = 0.0 if n == 1 else clampf(0.8 + float(n) * 0.18, 0.8, 3.5)
	for i in range(n):
		var item: ItemInstance = items[i]
		var drop := _loot_scene.instantiate()
		_attach_to_world(drop)
		var angle: float = TAU * float(i) / float(max(n, 1))
		var pos: Vector3 = origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if drop is Node3D:
			(drop as Node3D).global_position = pos
		drop.setup(item)
		# 通知角色D 挂光柱/音效 (品质分级表现, DUI-01).
		if inv != null:
			inv.loot_dropped.emit(item.quality, pos)

func _attach_to_world(node: Node) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		scene_root.add_child(node)
	else:
		get_tree().root.add_child(node)

# 战斗① 杀完一组精英时调用 -> 软保底 pity_stack +1.
func notify_elite_group_killed() -> void:
	if drop_system != null:
		drop_system.register_elite_kill()

# 进入梦魇层时调用 (0=主线 1/2=梦魇层) -> 橙权重系数.
func set_nightmare_tier(tier: int) -> void:
	if drop_system != null:
		drop_system.nightmare_tier = tier

func _player_level() -> int:
	var pm: Node = get_node_or_null("/root/ProgressionManager")
	return pm.level if pm != null else 1
