extends Node

# SpawnManager (Autoload) — 全局刷怪服务 + 波次状态追踪。
#
# 用法:
#   var wave_id = SpawnManager.spawn_wave({
#       "enemy_scene": preload("res://scenes/enemies/enemy_zombie.tscn"),
#       "enemy_data": preload("res://scripts/entities/data/walking_corpse.tres"),
#       "count": 5,
#       "formation": "cluster",   # "cluster" / "line" / "surround"
#       "center": Vector3(10, 0, 5),
#       "radius": 3.0,
#       "target": player_node,    # surround 时把玩家围在中间
#   })
#   SpawnManager.wave_cleared.connect(func(id): print("Wave %d cleared" % id))

signal wave_started(wave_id: int, count: int)
signal wave_cleared(wave_id: int)
signal enemy_spawned(enemy: Node, wave_id: int)

const FORMATION_CLUSTER: String = "cluster"
const FORMATION_LINE: String = "line"
const FORMATION_SURROUND: String = "surround"

var _next_wave_id: int = 0
# wave_id -> Array[instance_id_int],存活计数
var _wave_remaining: Dictionary = {}

# ── 公共 API ─────────────────────────────────────────
func spawn_wave(config: Dictionary) -> int:
	var enemy_scene: PackedScene = config.get("enemy_scene", null) as PackedScene
	if enemy_scene == null:
		push_error("SpawnManager.spawn_wave: enemy_scene required")
		return -1

	var count: int = max(1, int(config.get("count", 5)))
	var formation: String = String(config.get("formation", FORMATION_CLUSTER))
	var center: Vector3 = config.get("center", Vector3.ZERO) as Vector3
	var radius: float = max(0.0, float(config.get("radius", 3.0)))
	var target: Node3D = config.get("target", null) as Node3D
	var enemy_data: Resource = config.get("enemy_data", null) as Resource

	var positions: Array = _compute_formation(formation, center, radius, count, target)

	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		push_warning("SpawnManager: no current_scene to spawn into")
		return -1

	var wave_id: int = _next_wave_id
	_next_wave_id += 1
	_wave_remaining[wave_id] = []

	for i in range(count):
		var enemy: Node = enemy_scene.instantiate()
		if enemy == null:
			continue
		# 注入 EnemyData 必须在 add_child 之前设置,以便 _ready 时已就绪
		if enemy_data != null and "data" in enemy:
			enemy.data = enemy_data
		scene_root.add_child(enemy)
		if enemy is Node3D:
			(enemy as Node3D).global_position = positions[i]
		# 监听死亡
		if enemy.has_signal("died"):
			enemy.died.connect(_on_enemy_died.bind(wave_id))
		_wave_remaining[wave_id].append(enemy.get_instance_id())
		enemy_spawned.emit(enemy, wave_id)

	wave_started.emit(wave_id, count)
	return wave_id

# 强制清空某波(例如玩家死亡时)
func clear_wave(wave_id: int) -> void:
	if not _wave_remaining.has(wave_id):
		return
	_wave_remaining.erase(wave_id)
	wave_cleared.emit(wave_id)

func get_wave_remaining(wave_id: int) -> int:
	if not _wave_remaining.has(wave_id):
		return 0
	return (_wave_remaining[wave_id] as Array).size()

# ── 阵型计算 ─────────────────────────────────────────
func _compute_formation(formation: String, center: Vector3, radius: float, count: int, target: Node3D) -> Array:
	var positions: Array = []
	match formation:
		FORMATION_CLUSTER:
			# 在 center 周围圆盘内均匀采样
			for i in range(count):
				var angle: float = randf() * TAU
				var r: float = sqrt(randf()) * radius  # sqrt → 面积均匀
				positions.append(center + Vector3(cos(angle) * r, 0.0, sin(angle) * r))
		FORMATION_LINE:
			# 一字排开,沿 X 轴
			for i in range(count):
				var t: float = 0.5 if count == 1 else float(i) / float(count - 1)
				var x: float = lerp(-radius, radius, t)
				positions.append(center + Vector3(x, 0.0, 0.0))
		FORMATION_SURROUND:
			# 围绕 target(没传就退化到 center)做一个圆
			var origin: Vector3 = center
			if target != null and is_instance_valid(target):
				origin = target.global_position
			var phase_off: float = randf() * TAU  # 随机起始相位,避免每次完全一样
			for i in range(count):
				var a: float = phase_off + float(i) / float(count) * TAU
				positions.append(origin + Vector3(cos(a) * radius, 0.0, sin(a) * radius))
		_:
			push_warning("SpawnManager: unknown formation '%s', falling back to cluster" % formation)
			for i in range(count):
				positions.append(center)
	return positions

# ── 信号回调 ─────────────────────────────────────────
func _on_enemy_died(enemy, wave_id: int) -> void:
	if not _wave_remaining.has(wave_id):
		return
	var arr: Array = _wave_remaining[wave_id]
	# 按正确的 instance_id 移除，而非盲目 pop_back（AoE 乱序死亡时 pop_back 会删错）
	var id: int = enemy.get_instance_id()
	var idx: int = arr.find(id)
	if idx >= 0:
		arr.remove_at(idx)
	elif arr.size() > 0:
		# 降级兜底：找不到 id（极少数情况）才 pop_back
		arr.pop_back()
	if arr.is_empty():
		_wave_remaining.erase(wave_id)
		wave_cleared.emit(wave_id)
