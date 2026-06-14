extends Node

# TowerBuffManager (Autoload): 功能塔 buff 中心状态机.
#
# 规则(重切方案 §2.5 / §2.5.1):
# - 互动激活、全局生效:塔触发 → 一段限时全局 buff.
# - 互斥二选一:同一时刻只生效一座塔的 buff. 激活第二座 = 替换(刷新效果与时长), 不叠加.
# - 冷却:每座塔激活后进入 CD, CD 内不可再激活; CD 结束发 tower_ready.
#
# 注入方式(零侵入既有链路):
# - 伤害 +X% → 写 DamageCalculator.tower_dmg_mult (公式末端乘区).
# - 移速 +X% → 写 player.speed_buff_mult (group "player" 节点).
#
# 数值来自 DataTables.get_tower_buff(id) (数值表/tower_buffs.csv, 热调).

const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")

# 当前生效 buff (空 = 无). tower_id = CSV 行 id (damage_tower / speed_tower).
signal tower_buff_changed(tower_id: StringName, buff_type: StringName, remaining: float, duration: float)
# 一次性: 某塔刚被激活 (用于横幅/屏幕染色等"激活瞬间"反馈, 不每帧发).
signal tower_buff_activated(tower_id: StringName, buff_type: StringName, duration: float)
# 一次性: 当前 buff 自然到期清除 (用于"强化结束"反馈).
signal tower_buff_expired(tower_id: StringName, buff_type: StringName)
# 某塔 CD 进度变化 (cd_remaining=0 即就绪).
signal tower_cooldown_changed(tower_id: StringName, cd_remaining: float, cd_total: float)
# 某塔 CD 归零、重新可激活.
signal tower_ready(tower_id: StringName)

var _active_id: StringName = &""        # 当前生效塔 id (互斥单值, 空=无)
var _active_type: StringName = &""      # damage / speed
var _buff_timer: float = 0.0            # 当前 buff 剩余时长
var _buff_duration: float = 0.0         # 当前 buff 总时长 (供 HUD 算进度)
var _active_magnitude: float = 0.0      # 当前 buff 加成幅度 (清除时还原用)

# HUD 进度刷新节流: tower_buff_changed 原先每帧发 → 高刷下每帧 set_text 浪费.
# 累积 >= 阈值才发一次 (倒计时显示 0.1s 粒度足够), 激活/到期一次性信号不受影响.
const _BUFF_UI_REFRESH_INTERVAL: float = 0.1
var _buff_ui_accum: float = 0.0

var _cd_map: Dictionary = {}            # tower_id(StringName) -> 剩余 CD 秒

# DataTables 引用 (autoload 时自动取 /root/DataTables; 测试可注入).
var _data_tables: Node = null

func _ready() -> void:
	set_process(true)

func _dt() -> Node:
	if _data_tables != null:
		return _data_tables
	_data_tables = get_node_or_null("/root/DataTables")
	return _data_tables

# 测试注入 DataTables (headless verify 用).
func set_data_tables(dt: Node) -> void:
	_data_tables = dt

# 互动激活某塔. CD 未就绪返回 false; 否则互斥替换并应用. tower_id = CSV 行 id.
func activate(tower_id: StringName) -> bool:
	var sid: String = String(tower_id)
	if _cd_map.get(tower_id, 0.0) > 0.0:
		return false  # 冷却中
	var dt: Node = _dt()
	var def: Dictionary = dt.get_tower_buff(sid) if dt != null else {}
	if def.is_empty():
		push_warning("TowerBuffManager: 未知塔 id %s" % sid)
		return false
	# 互斥:先清掉当前 buff 的乘区(若有), 再应用新 buff.
	_clear_active_effect()
	_active_id = tower_id
	_active_type = StringName(String(def.get("buff_type", "")))
	_active_magnitude = float(def.get("magnitude", 0.0))
	_buff_duration = float(def.get("duration", 0.0))
	_buff_timer = _buff_duration
	_buff_ui_accum = 0.0
	_apply_active_effect()
	# 该塔进 CD.
	var cd: float = float(def.get("cooldown", 0.0))
	_cd_map[tower_id] = cd
	tower_buff_changed.emit(_active_id, _active_type, _buff_timer, _buff_duration)
	tower_buff_activated.emit(_active_id, _active_type, _buff_duration)
	tower_cooldown_changed.emit(tower_id, cd, cd)
	return true

func is_active() -> bool:
	return _active_id != &""

func active_tower_id() -> StringName:
	return _active_id

func buff_remaining() -> float:
	return _buff_timer

# 某塔当前 CD 剩余 (0 = 就绪).
func cooldown_remaining(tower_id: StringName) -> float:
	return float(_cd_map.get(tower_id, 0.0))

func is_tower_ready(tower_id: StringName) -> bool:
	return cooldown_remaining(tower_id) <= 0.0

func _process(delta: float) -> void:
	# 1) buff 持续倒计时.
	if _active_id != &"":
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_buff_timer = 0.0
			var cleared_id: StringName = _active_id
			var cleared_type: StringName = _active_type
			_clear_active_effect()
			_active_id = &""
			_active_type = &""
			_buff_duration = 0.0
			tower_buff_changed.emit(cleared_id, &"", 0.0, 0.0)
			tower_buff_expired.emit(cleared_id, cleared_type)
		else:
			# 节流: 累积到刷新间隔才发一次 (高刷下避免每帧 set_text).
			_buff_ui_accum += delta
			if _buff_ui_accum >= _BUFF_UI_REFRESH_INTERVAL:
				_buff_ui_accum = 0.0
				tower_buff_changed.emit(_active_id, _active_type, _buff_timer, _buff_duration)
	# 2) 各塔 CD 倒计时.
	for tid in _cd_map.keys():
		var cd: float = float(_cd_map[tid])
		if cd <= 0.0:
			continue
		cd -= delta
		if cd <= 0.0:
			cd = 0.0
			_cd_map[tid] = 0.0
			tower_cooldown_changed.emit(tid, 0.0, 0.0)
			tower_ready.emit(tid)
		else:
			_cd_map[tid] = cd
			tower_cooldown_changed.emit(tid, cd, cd)

# 应用当前 _active_type 的乘区.
func _apply_active_effect() -> void:
	match String(_active_type):
		"damage":
			DamageCalculator.tower_dmg_mult = 1.0 + _active_magnitude
		"speed":
			_set_player_speed_mult(1.0 + _active_magnitude)

# 还原当前 _active_type 的乘区到中性值.
func _clear_active_effect() -> void:
	match String(_active_type):
		"damage":
			DamageCalculator.tower_dmg_mult = 1.0
		"speed":
			_set_player_speed_mult(1.0)

func _set_player_speed_mult(v: float) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	var p: Node = tree.get_first_node_in_group("player")
	if p != null and (&"speed_buff_mult" in p):
		p.set(&"speed_buff_mult", v)

# 场景切换/重开时复位 (避免乘区残留到下一局).
func reset() -> void:
	_clear_active_effect()
	_active_id = &""
	_active_type = &""
	_buff_timer = 0.0
	_buff_duration = 0.0
	_active_magnitude = 0.0
	_buff_ui_accum = 0.0
	_cd_map.clear()
