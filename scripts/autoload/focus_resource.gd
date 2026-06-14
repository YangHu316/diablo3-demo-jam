extends Node

# 全局 Focus(专注)资源。Autoload。
# 与 mana 类似的资源池,被动回复 + 命中回蓝。

signal focus_changed(current: float, max_focus: float)

const PASSIVE_REGEN: float = 60.0  # V3.0 爽快版:每秒被动恢复 60(原 8)

@export var max_focus: float = 1500.0  # V3.0 爽快版:上限 1500(原 100)

var current: float = 1500.0

func _ready() -> void:
	current = max_focus
	focus_changed.emit(current, max_focus)

func _process(delta: float) -> void:
	if current >= max_focus:
		return
	var prev: float = current
	current = min(max_focus, current + PASSIVE_REGEN * delta)
	if not is_equal_approx(prev, current):
		focus_changed.emit(current, max_focus)

# 检查是否够用,但不扣除。SkillSlotManager 在执行前用它做"按不动"判断。
func can_consume(amount: float) -> bool:
	if amount <= 0.0:
		return true
	return current >= amount

# 尝试扣除资源:够则扣除返回 true,不够则不动并返回 false。
func consume(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if current < amount:
		return false
	current -= amount
	focus_changed.emit(current, max_focus)
	return true

# 命中回蓝 / 主动回复。
func gain(amount: float) -> void:
	if amount <= 0.0:
		return
	var prev: float = current
	current = min(max_focus, current + amount)
	if not is_equal_approx(prev, current):
		focus_changed.emit(current, max_focus)

func get_ratio() -> float:
	if max_focus <= 0.0:
		return 0.0
	return current / max_focus
