extends Area3D

# level_exit.gd — 关卡出口触发器(挂 Area3D, collision_mask=1 检测玩家)。
# 玩家进入 → emit level_completed + 打印(白盒阶段先做占位,后续接关卡流转/结算)。

signal level_completed(level_id: String)

@export var level_id: String = "L2_depths"
@export var next_hint: String = "守门人房"

var _done: bool = false

func _ready() -> void:
	monitoring = true
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if _done:
		return
	if body == null or not body.is_in_group("player"):
		return
	_done = true
	print("[Level] %s 通关 → 下一区:%s" % [level_id, next_hint])
	level_completed.emit(level_id)
