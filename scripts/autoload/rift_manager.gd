extends Node

# RiftManager (Autoload) — V3.0 单局大秘境进度系统.
#
# 玩法: 击杀小怪/精英累计"进度权重", 满 GOAL 触发守门人 (切 boss_room_play.tscn).
#   权重 (沿用 §6.2 / 大秘境配置 §3.1): 白怪 +1.0 / 蓝名 +5.0 / 黄名 +8.0 / 时间球 +3.0.
#   守门人 (guardian/butcher) 不计权重 —— 其死亡 = 单局通关, 不喂进度.
#
# 监听: CombatManager.enemy_killed(enemy, killer, overkill, dir)
#   据 enemy.get_meta("monster_id") 查权重. 每个 enemy 实例只计一次 (防重复).
# 对外: signal progress_changed(value, goal) / signal guardian_ready()
#   add_time_ball() — 供时间球拾取 (关卡C/美术后续放置) 调用.

signal progress_changed(value: float, goal: float)
signal guardian_ready()

const GOAL: float = 106.0                       # 总权重目标 (~6min 填满)
const BOSS_SCENE: String = "res://scenes/levels/boss_room_play.tscn"

# monster_id -> 进度权重. 守门人/屠夫 = 0 (不计).
const WEIGHTS: Dictionary = {
	&"trash": 1.0,
	&"dog": 1.0,
	&"archer": 1.0,
	&"bloated": 1.0,
	&"summoner": 1.0,
	&"skeleton_guard": 1.0,
	&"elite_blue": 5.0,
	&"champion_yellow": 8.0,
	&"guardian": 0.0,
	&"butcher": 0.0,
}
const TIME_BALL_WEIGHT: float = 3.0

var progress: float = 0.0
var guardian_triggered: bool = false

# 已计数的 enemy 实例 id (防同一只怪重复加权).
var _counted: Dictionary = {}

func _ready() -> void:
	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null and cm.has_signal("enemy_killed"):
		cm.enemy_killed.connect(_on_enemy_killed)

# 重置 (重开一局时调用).
func reset_rift() -> void:
	progress = 0.0
	guardian_triggered = false
	_counted.clear()
	progress_changed.emit(progress, GOAL)

func _on_enemy_killed(enemy, _killer, _overkill: int, _dir) -> void:
	if enemy == null:
		return
	# 防重复: 同一实例只计一次.
	var key: int = enemy.get_instance_id()
	if _counted.has(key):
		return
	_counted[key] = true

	var mid: StringName = &"trash"
	if enemy.has_meta("monster_id"):
		mid = StringName(enemy.get_meta("monster_id"))
	var w: float = float(WEIGHTS.get(mid, 1.0))   # 未知 id 当白怪 (兜底, 不漏喂进度)
	if w <= 0.0:
		return   # 守门人不计
	_add_progress(w)

# 时间球拾取 +3.0 (供拾取实体调用).
func add_time_ball() -> void:
	_add_progress(TIME_BALL_WEIGHT)

func _add_progress(amount: float) -> void:
	if guardian_triggered:
		return
	progress = minf(progress + amount, GOAL)
	progress_changed.emit(progress, GOAL)
	if progress >= GOAL:
		_trigger_guardian()

func _trigger_guardian() -> void:
	if guardian_triggered:
		return
	guardian_triggered = true
	guardian_ready.emit()
	# 满进度 → 切守门人房 (八边形房复用). 延一帧避免在信号回调中切场.
	call_deferred("_go_boss")

func _go_boss() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if not ResourceLoader.exists(BOSS_SCENE):
		push_warning("RiftManager: missing %s" % BOSS_SCENE)
		return
	tree.change_scene_to_file(BOSS_SCENE)
