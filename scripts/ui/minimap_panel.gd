extends CanvasLayer

# ── 常驻小地图（右上角 HUD）─────────────────────────────────────────────
# 架构：2D 程序化绘制（_draw()），不使用 SubViewport / Camera3D。
# 数据来源：level 组节点的 WALK / LANDMARKS / SCALE 常量（自动读取）。
# 显示范围：以玩家为中心，世界半径 VIEW_RADIUS 单位内的已探索区域。
# 尺寸：屏幕宽度 × MAP_SIZE_RATIO，正方形，右上角固定边距。

# ── 显示参数 ─────────────────────────────────────────────────────────────
const VIEW_RADIUS: float         = 55.0   # 小地图视口世界半径（已含 SCALE）
const EXPLORE_RADIUS: float      = 16.0   # 玩家每次探索的圆形半径（世界单位）
const FOG_UPDATE_INTERVAL: float = 0.15   # 迷雾采样间隔（秒）
const MAP_SIZE_RATIO: float      = 0.14   # 小地图边长 = 屏幕宽 × 此值（缩小一半）
const MARGIN: float              = 16.0   # 距屏幕右/上边缘的像素距离
const RECT_INFLATE: float        = 1.5    # 矩形扩展量（消除拼接缝隙）
# 迷雾格子大小（世界单位）：越小越精细，越大越快
const FOG_CELL_SIZE: float       = 3.0   # 格子越小边缘越平滑
const FOG_FADE_WIDTH: float      = 6.0   # 渐变过渡带宽度（世界单位）

# ── 颜色 ─────────────────────────────────────────────────────────────────
const COLOR_FLOOR_LARGE := Color(0.22, 0.17, 0.13, 0.95)  # 统一深灰棕（参考暗黑3）
const COLOR_FLOOR_SMALL := Color(0.22, 0.17, 0.13, 0.95)  # 同上，不再区分
const COLOR_FLOOR_EDGE  := Color(0.50, 0.36, 0.20, 0.35)  # 矩形描边（已停用）
const COLOR_BORDER      := Color(0.55, 0.40, 0.18, 1.00)  # 金色外边框
const COLOR_PLAYER      := Color(1.00, 1.00, 1.00, 1.00)  # 玩家三角（白）
const COLOR_PLAYER_OUT  := Color(0.90, 0.70, 0.10, 0.90)  # 玩家三角描边（黄）
const COLOR_PLAYER_GLOW := Color(0.30, 0.55, 1.00, 1.00)  # 玩家蓝色发光底座

# 地标样式：{kind: [Color, inner_radius]}，3 层发光绘制
const LANDMARK_STYLE := {
	"portal_in"  : [Color(0.20, 1.00, 0.40, 1.0), 5.0],
	"portal_out" : [Color(1.00, 0.85, 0.10, 1.0), 5.0],
	"waypoint"   : [Color(0.40, 0.80, 1.00, 1.0), 5.0],
	"beacon"     : [Color(0.60, 0.90, 1.00, 0.9), 4.0],
	"boss_pillar": [Color(1.00, 0.30, 0.30, 1.0), 7.0],
	"chest"      : [Color(1.00, 0.75, 0.20, 0.9), 4.0],
	"gear"       : [Color(0.90, 0.80, 0.30, 0.9), 4.0],
}

# ── 内部绘图节点类 ────────────────────────────────────────────────────────
class MinimapCanvas extends Control:
	var owner_mm: Node = null

	func _draw() -> void:
		if owner_mm == null:
			return
		owner_mm._do_draw(self)

# ── 节点引用 ─────────────────────────────────────────────────────────────
var _panel: PanelContainer = null
var _canvas: MinimapCanvas = null

# ── 运行时尺寸 ───────────────────────────────────────────────────────────
var _map_size: float = 200.0

# ── 状态 ─────────────────────────────────────────────────────────────────
var _player: Node = null
var _level:  Node = null

# 世界坐标矩形列表（已乘 SCALE）：[[xmin, xmax, zmin, zmax], ...]
var _walk_rects: Array = []
# 地标列表：[{wx, wz, kind}, ...]
var _landmarks: Array = []

# 迷雾：存储历史探索圆心列表（世界坐标 Vector2），圆形渐进解锁
# 每条记录 = 玩家某时刻的 (x, z) 位置，绘制时只画在任意历史圆内的格子
var _fog_circles: Array = []   # Array[Vector2]
# 去重用：记录已记录的格子中心（避免添加极近重复圆心）
var _last_fog_pos: Vector2 = Vector2(INF, INF)

# 玩家当前世界坐标（每帧缓存）
var _player_wx: float = 0.0
var _player_wz: float = 0.0
var _player_ry: float = 0.0

var _fog_timer: float = 0.0


# ═════════════════════════════════════════════════════════════════════════
# 初始化
# ═════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	layer = 105
	_map_size = get_viewport().size.x * MAP_SIZE_RATIO
	get_viewport().size_changed.connect(_on_viewport_resized)
	_build_ui()
	call_deferred("_acquire_refs")


func _build_ui() -> void:
	var root := Control.new()
	root.name = "MinimapRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.name = "MinimapFrame"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	root.add_child(_panel)
	_resize_panel()

	_canvas = MinimapCanvas.new()
	_canvas.name = "MinimapCanvas"
	_canvas.owner_mm = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 裁切：所有绘制内容超出边界自动裁掉
	_canvas.clip_contents = true
	_panel.add_child(_canvas)


func _resize_panel() -> void:
	if _panel == null:
		return
	_panel.custom_minimum_size = Vector2(_map_size, _map_size)
	_panel.anchor_left   = 1.0
	_panel.anchor_top    = 0.0
	_panel.anchor_right  = 1.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left   = -(_map_size + MARGIN)
	_panel.offset_top    = MARGIN
	_panel.offset_right  = -MARGIN
	_panel.offset_bottom = MARGIN + _map_size


func _on_viewport_resized() -> void:
	_map_size = get_viewport().size.x * MAP_SIZE_RATIO
	_resize_panel()
	if _canvas != null:
		_canvas.queue_redraw()


# ═════════════════════════════════════════════════════════════════════════
# 获取玩家和关卡节点
# ═════════════════════════════════════════════════════════════════════════
func _acquire_refs() -> void:
	var arr := get_tree().get_nodes_in_group("player")
	if arr.size() == 0:
		await get_tree().process_frame
		arr = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		_player = arr[0]

	var levels := get_tree().get_nodes_in_group("level")
	if levels.size() > 0:
		_level = levels[0]
	else:
		for n in get_tree().root.get_children():
			for c in n.get_children():
				if c.get_script() != null and "WALK" in c:
					_level = c
					break

	_load_level_data()


func _load_level_data() -> void:
	_walk_rects.clear()
	_landmarks.clear()

	if _level == null or not ("WALK" in _level):
		return

	var scale: float = 1.5
	if "SCALE" in _level:
		scale = float(_level.SCALE)

	for r in _level.WALK:
		_walk_rects.append([
			float(r[0]) * scale,
			float(r[1]) * scale,
			float(r[2]) * scale,
			float(r[3]) * scale,
		])

	if "LANDMARKS" in _level:
		for lm in _level.LANDMARKS:
			_landmarks.append({
				"wx":   float(lm[0]) * scale,
				"wz":   float(lm[1]) * scale,
				"kind": str(lm[2]),
			})


# ═════════════════════════════════════════════════════════════════════════
# 每帧更新
# ═════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	if _player == null:
		return

	var pos: Vector3 = _player.global_position
	_player_wx = pos.x
	_player_wz = pos.z
	_player_ry = _player.rotation.y

	_fog_timer += delta
	if _fog_timer >= FOG_UPDATE_INTERVAL:
		_fog_timer = 0.0
		_record_fog_circle(_player_wx, _player_wz)

	if _canvas != null:
		_canvas.queue_redraw()


# ── 迷雾：记录探索圆心（圆形渐进解锁）──────────────────────────────────────
# 每次采样添加一个世界坐标圆心；移动距离超过 EXPLORE_RADIUS*0.5 才添加新圆，
# 避免原地站立产生大量重复圆心。
func _record_fog_circle(wx: float, wz: float) -> void:
	var cur := Vector2(wx, wz)
	if _last_fog_pos.distance_to(cur) < EXPLORE_RADIUS * 0.5:
		return
	_fog_circles.append(cur)
	_last_fog_pos = cur


# ── 判断世界坐标点是否在任意探索圆内 ────────────────────────────────────────
func _in_fog(wx: float, wz: float) -> bool:
	var p := Vector2(wx, wz)
	for c in _fog_circles:
		if p.distance_squared_to(c) <= EXPLORE_RADIUS * EXPLORE_RADIUS:
			return true
	return false


# ── 计算点到探索圆边缘的渐变 alpha（0=未探索，1=完全可见，中间=过渡带）─────
func _fog_alpha(wx: float, wz: float) -> float:
	var p := Vector2(wx, wz)
	var min_dist: float = INF
	var inner: float = EXPLORE_RADIUS - FOG_FADE_WIDTH
	for c in _fog_circles:
		var d: float = p.distance_to(c)
		if d < min_dist:
			min_dist = d
		if min_dist <= inner:
			return 1.0   # 早退：已完全可见
	if min_dist == INF:
		return 0.0
	# 在过渡带：线性衰减；圆外：不可见
	if min_dist <= EXPLORE_RADIUS:
		return 1.0 - (min_dist - inner) / FOG_FADE_WIDTH
	return 0.0


# ═════════════════════════════════════════════════════════════════════════
# 绘制（由 MinimapCanvas._draw() 回调）
# ═════════════════════════════════════════════════════════════════════════
func _do_draw(canvas: Control) -> void:
	var ms: float = _map_size

	# 1. 遍历所有 WALK 矩形，按格子绘制已探索区域
	for i in range(_walk_rects.size()):
		var r: Array = _walk_rects[i]
		# P1-3：按面积区分颜色
		var world_area: float = (r[1] - r[0]) * (r[3] - r[2])
		var floor_color: Color = COLOR_FLOOR_LARGE if world_area > 800.0 else COLOR_FLOOR_SMALL

		# 将矩形细分为 FOG_CELL_SIZE 大小的格子，按渐变 alpha 绘制（消除锯齿）
		var cx: float = r[0]
		while cx < r[1]:
			var cx_end: float = minf(cx + FOG_CELL_SIZE, r[1])
			var cell_cx: float = (cx + cx_end) * 0.5   # 格子中心 x

			var cz: float = r[2]
			while cz < r[3]:
				var cz_end: float = minf(cz + FOG_CELL_SIZE, r[3])
				var cell_cz: float = (cz + cz_end) * 0.5   # 格子中心 z

				var alpha: float = _fog_alpha(cell_cx, cell_cz)
				if alpha > 0.01:
					var c := Color(floor_color.r, floor_color.g, floor_color.b, floor_color.a * alpha)
					var tl := _world_to_ui(cx, cz, ms) - Vector2(RECT_INFLATE, RECT_INFLATE)
					var br := _world_to_ui(cx_end, cz_end, ms) + Vector2(RECT_INFLATE, RECT_INFLATE)
					canvas.draw_rect(Rect2(tl, br - tl), c)

				cz = cz_end
			cx = cx_end

		# 不画矩形描边——地板颜色本身形成自然轮廓，与暗黑3风格一致

	# 2. 地标（3 层发光，只在已探索区域显示）
	for lm in _landmarks:
		var lx: float = lm["wx"]
		var lz: float = lm["wz"]
		if not _in_fog(lx, lz):
			continue
		var uv := _world_to_ui(lx, lz, ms)
		# 超出地图范围跳过（clip_contents 也会裁，这里是快速跳过不必要绘制）
		if uv.x < -20.0 or uv.x > ms + 20.0 or uv.y < -20.0 or uv.y > ms + 20.0:
			continue
		_draw_landmark(canvas, uv, lm["kind"])

	# 3. 玩家三角形（始终居中）
	if _player != null:
		_draw_player_triangle(canvas, ms)

	# 4. 金色外边框（最后画，覆盖溢出内容）
	canvas.draw_rect(Rect2(0.0, 0.0, ms, ms), COLOR_BORDER, false, 3.0)

	# 5. 四角装饰块
	var s := maxf(ms * 0.038, 4.0)
	canvas.draw_rect(Rect2(0.0,    0.0,    s, s), COLOR_BORDER)
	canvas.draw_rect(Rect2(ms - s, 0.0,    s, s), COLOR_BORDER)
	canvas.draw_rect(Rect2(0.0,    ms - s, s, s), COLOR_BORDER)
	canvas.draw_rect(Rect2(ms - s, ms - s, s, s), COLOR_BORDER)


# ── 地标 3 层发光绘制 ─────────────────────────────────────────────────────
func _draw_landmark(canvas: Control, uv: Vector2, kind: String) -> void:
	var style: Array = LANDMARK_STYLE.get(kind, [Color(1, 1, 1, 0.8), 4.0])
	var col: Color = style[0]
	var rad: float = style[1]

	canvas.draw_circle(uv, rad * 2.8, Color(col.r, col.g, col.b, 0.15))
	canvas.draw_circle(uv, rad * 1.8, Color(col.r, col.g, col.b, 0.35))
	canvas.draw_circle(uv, rad + 1.0, Color(1.0, 1.0, 1.0, 0.55))
	canvas.draw_circle(uv, rad, col)


# ── 玩家朝向三角形 + 蓝色发光底座 ────────────────────────────────────────
func _draw_player_triangle(canvas: Control, ms: float) -> void:
	var center := Vector2(ms * 0.5, ms * 0.5)
	var r := ms * 0.040
	var a := _player_ry

	# 蓝色发光底座（三层，由大到小）
	canvas.draw_circle(center, r * 2.4, Color(COLOR_PLAYER_GLOW.r, COLOR_PLAYER_GLOW.g, COLOR_PLAYER_GLOW.b, 0.12))
	canvas.draw_circle(center, r * 1.5, Color(COLOR_PLAYER_GLOW.r, COLOR_PLAYER_GLOW.g, COLOR_PLAYER_GLOW.b, 0.25))
	canvas.draw_circle(center, r * 0.9, Color(COLOR_PLAYER_GLOW.r, COLOR_PLAYER_GLOW.g, COLOR_PLAYER_GLOW.b, 0.40))

	# 三角形顶点
	var tip   := center + Vector2( sin(a),        -cos(a))        * r * 1.8
	var left  := center + Vector2( sin(a + 2.35), -cos(a + 2.35)) * r
	var right := center + Vector2( sin(a - 2.35), -cos(a - 2.35)) * r

	# 黄色描边
	var so := r * 0.30
	var tip_o   := center + Vector2( sin(a),        -cos(a))        * (r * 1.8 + so)
	var left_o  := center + Vector2( sin(a + 2.35), -cos(a + 2.35)) * (r + so)
	var right_o := center + Vector2( sin(a - 2.35), -cos(a - 2.35)) * (r + so)
	canvas.draw_polygon(PackedVector2Array([tip_o, left_o, right_o]), PackedColorArray([COLOR_PLAYER_OUT]))
	# 白色填充
	canvas.draw_polygon(PackedVector2Array([tip, left, right]), PackedColorArray([COLOR_PLAYER]))


# ═════════════════════════════════════════════════════════════════════════
# 坐标转换：世界坐标 → 小地图 UI 像素（以玩家为中心）
# ═════════════════════════════════════════════════════════════════════════
func _world_to_ui(wx: float, wz: float, ms: float) -> Vector2:
	var half := ms * 0.5
	return Vector2(
		(wx - _player_wx) / VIEW_RADIUS * half + half,
		(wz - _player_wz) / VIEW_RADIUS * half + half
	)
