extends Node

# LootManager (Autoload): 击杀 -> 掉落判定 -> 地面 spawn -> 入包链路总装 (任务3).
# 把纯逻辑 DropSystem 接到场景: 监听 CombatManager.enemy_killed, 在死亡位置生成 LootDrop.
#
# 怪物实例元数据约定 (战斗① 挂; 缺省兜底):
#   drop_source: int  (DropSystem.Source, 默认 TRASH)
#   monster_level: int (默认玩家当前等级)
# 精英组击杀: 战斗① 杀完一组精英调 LootManager.notify_elite_group_killed() 喂软保底.

const LOOT_SCENE_PATH: String = "res://scenes/loot/loot_drop.tscn"

var drop_system: DropSystem = null
var _loot_scene: PackedScene = null
var _gen: ItemGenerator = null

func _ready() -> void:
	_loot_scene = load(LOOT_SCENE_PATH)
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

	var origin: Vector3 = Vector3.ZERO
	if enemy != null and is_instance_valid(enemy) and enemy is Node3D:
		origin = (enemy as Node3D).global_position
	_spawn_loot(items, origin)

# 多件掉落在落点周围散开.
func _spawn_loot(items: Array[ItemInstance], origin: Vector3) -> void:
	var inv: Node = get_node_or_null("/root/Inventory")
	var n: int = items.size()
	for i in range(n):
		var item: ItemInstance = items[i]
		var drop := _loot_scene.instantiate()
		_attach_to_world(drop)
		var angle: float = TAU * float(i) / float(max(n, 1))
		var spread: float = 0.0 if n == 1 else 0.8
		var pos: Vector3 = origin + Vector3(cos(angle) * spread, 0.0, sin(angle) * spread)
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
