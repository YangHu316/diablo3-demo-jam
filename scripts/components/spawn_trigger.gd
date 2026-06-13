extends Area3D

# spawn_trigger.gd — 挂在 Area3D 上的区域触发器。
# 玩家进入触发圈 → 调 SpawnManager.spawn_wave() 一次性生成一波怪。
# 默认 one_shot=true,触发一次后自动失效(可选保留节点供调试)。
#
# 节点结构:
#   Area3D (script = spawn_trigger.gd, monitoring=true, collision_mask=1=player)
#   └ CollisionShape3D (定义触发圈形状)
#
# 配置(Inspector):
#   enemy_scene:  PackedScene  → res://scenes/enemies/enemy_zombie.tscn
#   enemy_data:   Resource     → res://scripts/entities/data/walking_corpse.tres (可选)
#   count:        int          → 5
#   formation:    String       → "cluster" / "line" / "surround"
#   spawn_radius: float        → 3.0
#   spawn_at_self: bool        → true(在自己的位置生成),false 则用 spawn_center_path
#   spawn_center_path: NodePath → 自定义生成中心节点(例如远处的一个 Marker3D)
#   one_shot:     bool         → true
#   target_player: bool        → true(surround 阵型时围住玩家)

signal wave_triggered(wave_id: int)

@export var enemy_scene: PackedScene = null
@export var enemy_data: Resource = null
@export_range(1, 50, 1) var count: int = 5
@export_enum("cluster", "line", "surround") var formation: String = "cluster"
@export_range(0.5, 30.0, 0.5) var spawn_radius: float = 3.0
@export var spawn_at_self: bool = true
@export var spawn_center_path: NodePath = NodePath("")
@export var one_shot: bool = true
@export var target_player: bool = true

# 精英词缀(策划 03 §5.1):本波怪刷出来后自动打上对应标签。
@export var spawn_as_molten: bool = false

# 系统组对接 — 元数据归属(ProgressionManager 给 XP / LootManager 掉物按源分级)
# 在 Inspector 配置后,本波每只怪都会被打上这三条 meta:
#   monster_id    → ProgressionManager 据此查 monsters.tres 的 base_xp(策划 V2.1 怪物 id)
#   monster_level → 0 表示运行时取玩家等级;>0 用于固定级别(屠夫=7)
#   drop_source   → DropSystem.Source 枚举:0=TRASH 1=ELITE_BLUE 2=CHAMPION_YELLOW 3=BUTCHER
@export_enum("trash", "elite_blue", "champion_yellow", "skeleton_guard", "butcher") var monster_id: String = "trash"
@export_range(0, 8, 1) var monster_level: int = 0
@export_enum("trash", "elite_blue", "champion_yellow", "butcher") var drop_source: String = "trash"
# 精英组:全员清光时调 LootManager.notify_elite_group_killed() 喂软保底
@export var elite_group: bool = false

const _DROP_SOURCE_MAP := {
	"trash": 0, "elite_blue": 1, "champion_yellow": 2, "butcher": 3,
}

var _triggered: bool = false
var _my_wave_id: int = -1

func _ready() -> void:
	# Area3D 默认 monitoring=true,这里再保险设置;collision_mask 应在 .tscn 里设为 1(player layer)
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _triggered and one_shot:
		return
	if body == null or not body.is_in_group("player"):
		return
	_trigger_spawn(body)

func _trigger_spawn(player_body: Node) -> void:
	if enemy_scene == null:
		push_warning("SpawnTrigger '%s': enemy_scene not set" % name)
		return
	var sm: Node = get_node_or_null("/root/SpawnManager")
	if sm == null:
		push_warning("SpawnTrigger: SpawnManager autoload not found")
		return

	var center: Vector3 = global_position
	if not spawn_at_self and spawn_center_path != NodePath(""):
		var n: Node = get_node_or_null(spawn_center_path)
		if n is Node3D:
			center = (n as Node3D).global_position

	var target: Node3D = null
	if target_player and player_body is Node3D:
		target = player_body as Node3D

	var wid: int = sm.spawn_wave({
		"enemy_scene": enemy_scene,
		"enemy_data": enemy_data,
		"count": count,
		"formation": formation,
		"center": center,
		"radius": spawn_radius,
		"target": target,
	})
	if wid >= 0:
		_triggered = true
		_my_wave_id = wid
		wave_triggered.emit(wid)
		# 系统组对接:始终连 enemy_spawned 来挂 monster_id / monster_level / drop_source 元数据
		if sm.has_signal("enemy_spawned"):
			sm.enemy_spawned.connect(_on_enemy_spawned)
		# 精英组保底通知:全员清光时调 LootManager.notify_elite_group_killed()
		if elite_group and sm.has_signal("wave_cleared"):
			sm.wave_cleared.connect(_on_wave_cleared)

func _on_enemy_spawned(enemy: Node, wave_id: int) -> void:
	if wave_id != _my_wave_id or enemy == null:
		return
	# 元数据(策划 V2.1 锁定 id 池;ProgressionManager / LootManager 据此结算)
	# Key 用普通 String 字面量,与系统组接收端 has_meta("monster_id") 完全对齐
	enemy.set_meta("monster_id", StringName(monster_id))
	var lv: int = monster_level
	if lv <= 0:
		lv = _get_player_level()
	enemy.set_meta("monster_level", lv)
	enemy.set_meta("drop_source", int(_DROP_SOURCE_MAP.get(drop_source, 0)))
	# 精英词缀
	if spawn_as_molten and "is_molten" in enemy:
		enemy.is_molten = true

func _on_wave_cleared(wave_id: int) -> void:
	if wave_id != _my_wave_id:
		return
	var lm: Node = get_node_or_null("/root/LootManager")
	if lm != null and lm.has_method("notify_elite_group_killed"):
		lm.notify_elite_group_killed()

func _get_player_level() -> int:
	var pm: Node = get_node_or_null("/root/ProgressionManager")
	if pm != null and "level" in pm:
		return int(pm.level)
	return 1

# 公共 API:重置触发器(允许再次触发)
func reset() -> void:
	_triggered = false

# 公共 API:手动触发(调试 / 由关卡脚本调)
func force_trigger() -> void:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.is_empty():
		_trigger_spawn(null)
	else:
		_trigger_spawn(arr[0])
