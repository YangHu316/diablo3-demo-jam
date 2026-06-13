extends Node

# stagger_component.gd — 受击僵直组件。挂在敌人子节点,命名 "StaggerComponent"。
#
# 等级判定:
#   L1 — 1% ~ 10% 最大生命的伤害   -> 轻抖 0.1s (mesh 横向小幅抖动,纯视觉)
#   L2 — 伤害 > 10% 最大生命 或暴击 -> 全身僵硬 0.3s (mesh 挤压姿势 + is_staggered=true)
#
# 限制:2 秒滑动窗口内 L2 最多 2 次,超过的降级为 L1,防止被无限锁。
#
# AI 联动:
#   - 暴露属性 is_staggered: bool — AI 在 _physics_process 里检查它,true 时跳过自身行为。
#   - 信号 stagger_started(level, duration) / stagger_ended() — 状态机可订阅做切换。
#
# 用法: $StaggerComponent.trigger(damage, max_health, is_crit)

signal stagger_started(level: int, duration: float)
signal stagger_ended()

const L1_DURATION: float = 0.1
const L2_DURATION: float = 0.3
const L2_WINDOW: float = 2.0          # 2 秒窗口
const L2_MAX_PER_WINDOW: int = 2      # 窗口内 L2 上限
const L1_DAMAGE_PCT_THRESHOLD: float = 0.10  # >10% -> L2
const L1_AMP: float = 0.06            # L1 轻抖横向幅度
const L2_SQUEEZE_X: float = 1.18      # L2 mesh 挤压姿势
const L2_SQUEEZE_Y: float = 0.82
const L2_BUILD_TIME: float = 0.04     # 进入挤压的时间
# 余下时间保持挤压,在 _end_l2 里恢复

@export var mesh_path: NodePath = NodePath("../BodyMesh")

var is_staggered: bool = false           # 仅 L2 期间为 true
var current_level: int = 0               # 0=空闲, 1=L1, 2=L2
var _l2_history: Array[float] = []       # L2 触发时间戳
var _mesh: Node3D = null
var _mesh_base_pos: Vector3 = Vector3.ZERO
var _mesh_base_scale: Vector3 = Vector3.ONE
var _tween: Tween = null

func _ready() -> void:
	if mesh_path != NodePath(""):
		_mesh = get_node_or_null(mesh_path) as Node3D
	if _mesh == null:
		push_warning("StaggerComponent: mesh not found at %s" % mesh_path)
		return
	_mesh_base_pos = _mesh.position
	_mesh_base_scale = _mesh.scale

func trigger(damage: int, max_health: int, is_crit: bool) -> void:
	if _mesh == null:
		return
	if max_health <= 0:
		return
	# L2 已经在播,不打断,避免无限刷新锁定时间(节奏感)
	if is_staggered:
		return

	var pct: float = float(damage) / float(max_health)
	var want_l2: bool = is_crit or pct > L1_DAMAGE_PCT_THRESHOLD
	if want_l2:
		_prune_old_l2()
		if _l2_history.size() >= L2_MAX_PER_WINDOW:
			# 窗口内 L2 已用完 -> 降级为 L1
			_do_l1()
		else:
			_l2_history.append(_now())
			_do_l2()
	else:
		_do_l1()

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _prune_old_l2() -> void:
	var cutoff: float = _now() - L2_WINDOW
	var i: int = 0
	while i < _l2_history.size():
		if _l2_history[i] < cutoff:
			_l2_history.remove_at(i)
		else:
			i += 1

# ── L1 轻抖 ────────────────────────────────────────────
func _do_l1() -> void:
	if _mesh == null:
		return
	current_level = 1
	stagger_started.emit(1, L1_DURATION)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	var phase: float = L1_DURATION * 0.25
	_tween.tween_property(_mesh, "position", _mesh_base_pos + Vector3(L1_AMP, 0, 0), phase)
	_tween.tween_property(_mesh, "position", _mesh_base_pos + Vector3(-L1_AMP, 0, 0), phase * 2.0)
	_tween.tween_property(_mesh, "position", _mesh_base_pos, phase)
	_tween.tween_callback(Callable(self, "_end_l1"))

func _end_l1() -> void:
	current_level = 0
	stagger_ended.emit()

# ── L2 全身僵硬 ─────────────────────────────────────────
func _do_l2() -> void:
	if _mesh == null:
		return
	is_staggered = true
	current_level = 2
	stagger_started.emit(2, L2_DURATION)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	# 进入姿势:压扁 + 拉宽
	var squeeze: Vector3 = Vector3(_mesh_base_scale.x * L2_SQUEEZE_X, _mesh_base_scale.y * L2_SQUEEZE_Y, _mesh_base_scale.z * L2_SQUEEZE_X)
	_tween.tween_property(_mesh, "scale", squeeze, L2_BUILD_TIME)
	# 保持 + 恢复
	_tween.tween_property(_mesh, "scale", _mesh_base_scale, L2_DURATION - L2_BUILD_TIME)
	_tween.tween_callback(Callable(self, "_end_l2"))

func _end_l2() -> void:
	is_staggered = false
	current_level = 0
	if _mesh != null:
		_mesh.scale = _mesh_base_scale
		_mesh.position = _mesh_base_pos
	stagger_ended.emit()
