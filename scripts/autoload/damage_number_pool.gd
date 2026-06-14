extends Node

# DamageNumberPool: D3 风格伤害飘字池(Autoload)
# V3.1 重做:
#   - 字号加大、加粗描边(双层 outline 视感),清晰可读
#   - 抛物线轨迹(随机左右偏 + 重力下落感),不再单纯垂直上飘
#   - 三档颜色:普通(白)/ 暴击(金)/ 重击 (红橙,暴击且伤害 ≥ 阈值)
#   - 暴击 SCALE 弹跳 + 轻微旋转抖动,飘字"砸出来"的力量感
#
# 用法: DamageNumberPool.show_damage(world_position, damage, is_crit)

const POOL_SIZE: int = 32                  # 提升池容量(E 技能 AOE 一次能出 10+ 数字)
const FLOAT_DURATION: float = 0.85         # 总时长
const FADE_START_RATIO: float = 0.55       # 飘到 55% 才开始淡出(读秒更久)

# 字号(V3.13b:24/32/42 → 32/48/64,普通+33% 暴击+50% 重击+52%,大幅强化"砸出来"的力量感)
const NORMAL_FONT_SIZE: int = 32
const CRIT_FONT_SIZE: int = 48
const HEAVY_FONT_SIZE: int = 64           # 重击(暴击 + 伤害 ≥ HEAVY_THRESHOLD)

# 重击阈值(单次伤害 >= 此值且暴击 → 升级到红橙重击样式)
const HEAVY_DAMAGE_THRESHOLD: int = 800

# 颜色
const NORMAL_COLOR: Color = Color(1.0, 1.0, 1.0, 1.0)
const CRIT_COLOR: Color = Color(1.0, 0.86, 0.20, 1.0)        # 金黄
const HEAVY_COLOR: Color = Color(1.0, 0.45, 0.15, 1.0)        # 橙红
const OUTLINE_COLOR: Color = Color(0.05, 0.02, 0.0, 1.0)     # 几乎纯黑棕,衬黄/红更通透

# 轨迹(V3.2:水平偏移加大、字小了 → 多目标飘字不再叠在一起)
const FLOAT_HEIGHT: float = 1.4            # 抛物线峰高(m)
const HORIZ_JITTER: float = 1.4            # 水平偏移随机范围(±1.4m)
const SPAWN_VERTICAL_OFFSET: float = 0.5

# 暴击 / 重击 弹跳
const CRIT_BOUNCE_SCALE: float = 1.45
const HEAVY_BOUNCE_SCALE: float = 1.7
const BOUNCE_UP_TIME: float = 0.09
const BOUNCE_DOWN_TIME: float = 0.14
const HEAVY_TILT_DEG: float = 6.0          # 重击轻微旋转角

var _pool: Array[Label3D] = []
var _next_index: int = 0
var _holder: Node3D = null
var _setup_done: bool = false

func _ready() -> void:
	call_deferred("_setup_pool")

func _setup_pool() -> void:
	if _setup_done:
		return
	var tree: SceneTree = get_tree()
	if tree == null:
		return
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
		# V3.5 根因修复:之前 fixed_size=true 让 label 固定屏幕大小,pixel_size 放大成半屏
		# 改成 fixed_size=false → 像普通 3D 物体那样随距离缩放,pixel_size 才是"世界单位/像素"。
		lbl.fixed_size = false
		lbl.pixel_size = 0.003
		lbl.font_size = NORMAL_FONT_SIZE
		lbl.outline_size = 6              # 描边收薄
		lbl.outline_modulate = OUTLINE_COLOR
		lbl.modulate = Color(1, 1, 1, 0)
		lbl.visible = false
		_holder.add_child(lbl)
		_pool.append(lbl)
	_setup_done = true

func show_damage(world_position: Vector3, damage: int, is_crit: bool = false) -> void:
	# V3.13:场景切换(level_02 → boss_room)会 free 掉老 current_scene 下的 _holder + 32 labels,
	# 但 _setup_done 一直 true,后续 show_damage 取到 freed label 静默返回 → boss 房看不到飘字。
	# 修法:每次检查 holder 是否还有效;无效就重置 _setup_done 让池重建。
	if _setup_done and (_holder == null or not is_instance_valid(_holder) or not _holder.is_inside_tree()):
		_setup_done = false
		_pool.clear()
		_holder = null
		_next_index = 0
	if not _setup_done:
		call_deferred("show_damage", world_position, damage, is_crit)
		call_deferred("_setup_pool")
		return
	if _pool.is_empty():
		return
	var lbl: Label3D = _pool[_next_index]
	_next_index = (_next_index + 1) % _pool.size()
	if not is_instance_valid(lbl):
		# label 被场景切换连坐 free 但 holder 没事(罕见)→ 兜底重建
		_setup_done = false
		_pool.clear()
		_holder = null
		_next_index = 0
		call_deferred("show_damage", world_position, damage, is_crit)
		call_deferred("_setup_pool")
		return

	# 档位判定
	var is_heavy: bool = is_crit and damage >= HEAVY_DAMAGE_THRESHOLD
	var color: Color
	var size: int
	if is_heavy:
		color = HEAVY_COLOR
		size = HEAVY_FONT_SIZE
	elif is_crit:
		color = CRIT_COLOR
		size = CRIT_FONT_SIZE
	else:
		color = NORMAL_COLOR
		size = NORMAL_FONT_SIZE

	# 起点 + 终点(抛物线靠 tween_method 模拟,简化为左右偏 + 上飘)
	var jitter_x: float = randf_range(-HORIZ_JITTER, HORIZ_JITTER)
	var jitter_z: float = randf_range(-HORIZ_JITTER * 0.5, HORIZ_JITTER * 0.5)
	var spawn_pos: Vector3 = world_position + Vector3(0, SPAWN_VERTICAL_OFFSET, 0)
	var end_pos: Vector3 = spawn_pos + Vector3(jitter_x, FLOAT_HEIGHT, jitter_z)

	lbl.global_position = spawn_pos
	# 重击文字加 "!" 后缀,数值更显眼
	if is_heavy:
		lbl.text = "%d!" % damage
	else:
		lbl.text = str(int(damage))
	lbl.scale = Vector3.ONE
	lbl.font_size = size
	lbl.modulate = color
	lbl.outline_modulate = OUTLINE_COLOR
	lbl.rotation = Vector3.ZERO
	lbl.visible = true

	# 主轨迹:抛物线 = 起点→峰值→落点 用三段
	var peak_pos: Vector3 = spawn_pos.lerp(end_pos, 0.5) + Vector3(0, FLOAT_HEIGHT * 0.35, 0)
	var tw: Tween = lbl.create_tween()
	tw.set_parallel(true)
	# 位移:用 method 插值在 spawn → peak → end 之间走二次贝塞尔(简化:两段线性)
	var seg_a: float = FLOAT_DURATION * 0.5
	var seg_b: float = FLOAT_DURATION * 0.5
	tw.tween_property(lbl, "global_position", peak_pos, seg_a).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 第二段(下落)放到串行子链,使用相同的并行容器
	var tw2: Tween = lbl.create_tween()
	tw2.tween_interval(seg_a)
	tw2.tween_property(lbl, "global_position", end_pos, seg_b).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	# 淡出
	var fade_delay: float = FLOAT_DURATION * FADE_START_RATIO
	var fade_dur: float = FLOAT_DURATION - fade_delay
	tw.tween_property(lbl, "modulate:a", 0.0, fade_dur).set_delay(fade_delay)

	# 弹跳 + 重击旋转
	if is_heavy:
		lbl.rotation_degrees = Vector3(0, 0, randf_range(-HEAVY_TILT_DEG, HEAVY_TILT_DEG))
		tw.tween_property(lbl, "scale", Vector3.ONE * HEAVY_BOUNCE_SCALE, BOUNCE_UP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(lbl, "scale", Vector3.ONE, BOUNCE_DOWN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	elif is_crit:
		tw.tween_property(lbl, "scale", Vector3.ONE * CRIT_BOUNCE_SCALE, BOUNCE_UP_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(lbl, "scale", Vector3.ONE, BOUNCE_DOWN_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	else:
		# 普通字也来一次轻弹(0→1.1→1),让"出现"瞬间有质量
		lbl.scale = Vector3.ONE * 0.6
		tw.tween_property(lbl, "scale", Vector3.ONE * 1.1, 0.07).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.chain().tween_property(lbl, "scale", Vector3.ONE, 0.08)

	# 整体动画结束后隐藏
	tw.chain().tween_callback(Callable(self, "_hide_label").bind(lbl))

func _hide_label(lbl: Label3D) -> void:
	if not is_instance_valid(lbl):
		return
	lbl.visible = false
	lbl.modulate.a = 0.0
