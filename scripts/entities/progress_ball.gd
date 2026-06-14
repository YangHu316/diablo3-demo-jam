extends Area3D

# ProgressBall: 精英怪掉落的"进度球". 玩家走近自动吸取 -> 加大秘境进度条进度 + 飘字.
# 由 LootManager 在精英死亡位置 spawn, setup(pct) 注入「每球进度%」(小数, 5%->0.05).
#
# 碰撞: layer=16 (掉落物专用, 复用), mask=1 (检测玩家). 进 Area3D 范围即自动吸取.
# 拾取 (DUI 自动): 玩家进范围 -> RiftManager.add_progress_ball(pct) -> 飘字「+5% ▲进度」-> 销毁.
#   无需按键 (区别于装备 LootDrop 的手动 F 拾取).

signal absorbed(pct: float)

@export var bob_height: float = 0.18
@export var bob_speed: float = 2.4
@export var spin_speed: float = 1.8

# 拾取的"每球进度%"(小数). 由 setup() 注入; 兜底 0.05 (=5%).
var pct: float = 0.05
var _picked: bool = false        # 防重复吸取 (同帧多 body_entered / queue_free 前)
var _base_y: float = 0.0
var _t: float = 0.0

@onready var gem: MeshInstance3D = $GemMesh

func _ready() -> void:
	add_to_group("loot")
	collision_layer = 16
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	_base_y = global_position.y

# 由 LootManager 在 add_child 之后调用, 注入每球进度% (小数).
func setup(per_ball_pct: float) -> void:
	pct = per_ball_pct

func _process(delta: float) -> void:
	_t += delta
	# 漂浮 + 自转, "可拾取"活感.
	global_position.y = _base_y + sin(_t * bob_speed) * bob_height
	rotate_y(spin_speed * delta)

func _on_body_entered(body: Node) -> void:
	if _picked or not body.is_in_group("player"):
		return
	_absorb(body)

# 自动吸取: 加进度 + 飘字, 然后销毁球.
func _absorb(player: Node) -> void:
	_picked = true
	var rm: Node = get_node_or_null("/root/RiftManager")
	if rm != null and rm.has_method("add_progress_ball"):
		rm.add_progress_ball(pct)
	_spawn_float_text(player)
	absorbed.emit(pct)
	# 飘字是独立节点 (挂世界, 不随球销毁), 球本身立即销毁.
	queue_free()

# 飘字「+5% ▲进度」: 独立 Label3D 挂到世界, 自飘自销 (不污染 DamageNumberPool).
func _spawn_float_text(_player: Node) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	if scene_root == null:
		return
	var label := Label3D.new()
	label.text = "+%d%% ▲进度" % int(round(pct * 100.0))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0035
	# 字体/描边与暴击伤害飘字对齐 (damage_number_pool: outline_size=8 /
	# OUTLINE_COLOR=(0.05,0.02,0,1) / 默认 Label3D 字体). 字号 12, 颜色改紫 (与 HUD 进度条紫一致).
	label.modulate = Color(0.55, 0.32, 0.95)        # 进度紫
	label.outline_modulate = Color(0.05, 0.02, 0.0, 1.0)
	label.outline_size = 6
	label.font_size = 12
	scene_root.add_child(label)
	label.global_position = global_position + Vector3(0.0, 1.3, 0.0)
	# 上飘 + 淡出 tween (~0.9s) 后自销.
	var tw: Tween = label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "global_position:y", label.global_position.y + 1.1, 0.9)
	tw.tween_property(label, "modulate:a", 0.0, 0.9).set_delay(0.25)
	tw.chain().tween_callback(label.queue_free)
