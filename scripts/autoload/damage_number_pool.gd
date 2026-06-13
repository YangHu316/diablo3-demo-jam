extends Node

# DamageNumberPool: 20 个 Label3D 飘字对象池(Autoload)。
# 普通伤害:白字 / 暴击:黄字 + 1.6×字号 + 弹跳缩放。
# 飘 0.8s 同时淡出。命中处生成。
#
# 用法: DamageNumberPool.show_damage(world_position, damage, is_crit)

const POOL_SIZE: int = 20
const FLOAT_DISTANCE: float = 1.5         # 上飘距离 (m)
const FLOAT_DURATION: float = 0.8         # 飘+淡出时长
const FADE_START_RATIO: float = 0.4       # 飘到 40% 时开始淡出

const NORMAL_FONT_SIZE: int = 32
const CRIT_FONT_SIZE_MULT: float = 1.6
const CRIT_BOUNCE_SCALE: float = 1.35
const CRIT_BOUNCE_UP_TIME: float = 0.08
const CRIT_BOUNCE_DOWN_TIME: float = 0.12

const NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const CRIT_COLOR: Color = Color(1.0, 0.85, 0.20, 1.0)

const SPAWN_VERTICAL_OFFSET: float = 0.5  # 在命中点上方 0.5m 起算

var _pool: Array[Label3D] = []
var _next_index: int = 0
var _holder: Node3D = null
var _setup_done: bool = false

func _ready() -> void:
	# 等到当前场景就绪后再建池(autoload 自身没法直接 add Label3D 到 3D 场景)
	call_deferred("_setup_pool")

func _setup_pool() -> void:
	if _setup_done:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	# 等场景树进入第一帧
	if tree.current_scene == null:
		await tree.process_frame
	var scene_root: Node = tree.current_scene
	if scene_root == null:
		push_warning("DamageNumberPool: no current_scene to attach to")
		return

	_holder = Node3D.new()
	_holder.name = "DamageNumberHolder"
	scene_root.add_child(_holder)

	for i in range(POOL_SIZE):
		var lbl: Label3D = Label3D.new()
		lbl.text = ""
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = true
		lbl.pixel_size = 0.005
		lbl.font_size = NORMAL_FONT_SIZE
		lbl.outline_size = 8
		lbl.outline_modulate = Color(0, 0, 0, 1)
		lbl.modulate = Color(1, 1, 1, 0)
		lbl.visible = false
		_holder.add_child(lbl)
		_pool.append(lbl)
	_setup_done = true

func show_damage(world_position: Vector3, damage: int, is_crit: bool = false) -> void:
	if not _setup_done:
		# 池还没建好(可能 hit_landed 早于 deferred setup),延一帧重试
		call_deferred("show_damage", world_position, damage, is_crit)
		return
	if _pool.is_empty():
		return
	# 取下一个槽(round-robin),如果还在播也强行覆盖,反正只有 20 个
	var lbl: Label3D = _pool[_next_index]
	_next_index = (_next_index + 1) % _pool.size()
	if not is_instance_valid(lbl):
		return

	# 重置状态
	var spawn_pos: Vector3 = world_position + Vector3(0, SPAWN_VERTICAL_OFFSET, 0)
	lbl.global_position = spawn_pos
	lbl.text = str(int(damage))
	lbl.scale = Vector3.ONE
	lbl.visible = true

	if is_crit:
		lbl.font_size = int(round(NORMAL_FONT_SIZE * CRIT_FONT_SIZE_MULT))
		lbl.modulate = CRIT_COLOR
	else:
		lbl.font_size = NORMAL_FONT_SIZE
		lbl.modulate = NORMAL_COLOR

	# 主动画(并行):上飘 + 淡出
	var tw: Tween = lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position", spawn_pos + Vector3(0, FLOAT_DISTANCE, 0), FLOAT_DURATION)
	tw.tween_property(lbl, "modulate:a", 0.0, FLOAT_DURATION * (1.0 - FADE_START_RATIO)).set_delay(FLOAT_DURATION * FADE_START_RATIO)
	# 暴击附加弹跳缩放
	if is_crit:
		tw.tween_property(lbl, "scale", Vector3.ONE * CRIT_BOUNCE_SCALE, CRIT_BOUNCE_UP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(lbl, "scale", Vector3.ONE, CRIT_BOUNCE_DOWN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	# 整体动画结束后隐藏
	tw.chain().tween_callback(Callable(self, "_hide_label").bind(lbl))

func _hide_label(lbl: Label3D) -> void:
	if not is_instance_valid(lbl):
		return
	lbl.visible = false
	lbl.modulate.a = 0.0
