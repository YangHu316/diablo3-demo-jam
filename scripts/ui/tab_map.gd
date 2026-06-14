extends CanvasLayer

# ── Tab 大地图（全屏覆盖层）─────────────────────────────────────────────
# 按 Tab (toggle_map) 切换显示/隐藏，游戏不暂停。
# 数据完全复用 minimap_panel 节点的运行时状态（fog_circles、walk_rects 等）。
# AUTO-FIT：每帧根据探索圆的 AABB 动态计算视野半径，确保所有已探索区域可见。

# ── 颜色（与 minimap_panel 一致）─────────────────────────────────────────
const COLOR_FLOOR       := Color(0.22, 0.17, 0.13, 0.95)
const COLOR_BORDER      := Color(0.55, 0.40, 0.18, 1.00)
const COLOR_PLAYER      := Color(1.00, 1.00, 1.00, 1.00)
const COLOR_PLAYER_OUT  := Color(0.90, 0.70, 0.10, 0.90)
const COLOR_PLAYER_GLOW := Color(0.30, 0.55, 1.00, 1.00)

const LANDMARK_STYLE := {
	"portal_in"  : [Color(0.20, 1.00, 0.40, 1.0), 5.0],
	"portal_out" : [Color(1.00, 0.85, 0.10, 1.0), 5.0],
	"waypoint"   : [Color(0.40, 0.80, 1.00, 1.0), 5.0],
	"beacon"     : [Color(0.60, 0.90, 1.00, 0.9), 4.0],
	"boss_pillar": [Color(1.00, 0.30, 0.30, 1.0), 7.0],
	"chest"      : [Color(1.00, 0.75, 0.20, 0.9), 4.0],
	"gear"       : [Color(0.90, 0.80, 0.30, 0.9), 4.0],
}

const VIEW_RADIUS: float  = 150.0  # 固定视野半径（世界单位）
const RECT_INFLATE: float = 1.5

# ── 内部绘图节点类 ────────────────────────────────────────────────────────
class TabMapCanvas extends Control:
	var owner_tm: Node = null

	func _draw() -> void:
		if owner_tm == null:
			return
		owner_tm._do_draw(self)

# ── 节点引用 ─────────────────────────────────────────────────────────────
var _overlay: ColorRect    = null
var _panel:   Control      = null
var _canvas:  TabMapCanvas = null

# minimap_panel 节点引用（共享数据）
var _mm: Node = null

# ── 运行时尺寸 ───────────────────────────────────────────────────────────
var _map_size: float = 600.0

# ── 拖拽偏移（世界单位）────────────────────────────────────────────────────
var _drag_offset: Vector2 = Vector2.ZERO   # 拖拽累积偏移（世界坐标）
var _is_dragging: bool    = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_offset: Vector2 = Vector2.ZERO


# ═════════════════════════════════════════════════════════════════════════
# 初始化
# ═════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	layer = 110
	visible = false
	_recalc_map_size()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_build_ui()
	call_deferred("_acquire_refs")


func _build_ui() -> void:
	# 半透明黑色全屏遮罩
	_overlay = ColorRect.new()
	_overlay.name = "TabMapOverlay"
	_overlay.color = Color(0.0, 0.0, 0.0, 0.75)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	# 居中方形地图面板（接收鼠标输入以支持拖拽）
	_panel = Control.new()
	_panel.name = "TabMapPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_gui_input)
	add_child(_panel)
	_resize_panel()

	# 绘制画布
	_canvas = TabMapCanvas.new()
	_canvas.name = "TabMapCanvas"
	_canvas.owner_tm = self
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.clip_contents = true
	_panel.add_child(_canvas)


func _recalc_map_size() -> void:
	var vp: Vector2 = Vector2(get_viewport().size)
	_map_size = minf(vp.x, vp.y) * 0.80


func _resize_panel() -> void:
	if _panel == null:
		return
	var vp: Vector2 = Vector2(get_viewport().size)
	var half := _map_size * 0.5
	_panel.custom_minimum_size = Vector2(_map_size, _map_size)
	_panel.set_size(Vector2(_map_size, _map_size))
	_panel.set_position(Vector2(vp.x * 0.5 - half, vp.y * 0.5 - half))


func _on_viewport_resized() -> void:
	_recalc_map_size()
	_resize_panel()
	if _canvas != null:
		_canvas.queue_redraw()


# ═════════════════════════════════════════════════════════════════════════
# 获取 minimap_panel 引用
# ═════════════════════════════════════════════════════════════════════════
func _acquire_refs() -> void:
	# 方法一：通过 group 查找
	var candidates := get_tree().get_nodes_in_group("minimap")
	if candidates.size() > 0:
		_mm = candidates[0]
		return

	# 方法二：遍历所有 CanvasLayer，按脚本路径匹配
	for node in get_tree().root.get_children():
		if _try_find_minimap(node):
			return
		for child in node.get_children():
			if _try_find_minimap(child):
				return


func _try_find_minimap(node: Node) -> bool:
	if node.get_script() != null:
		var path: String = str(node.get_script().resource_path)
		if "minimap_panel" in path:
			_mm = node
			return true
	return false


# ═════════════════════════════════════════════════════════════════════════
# 输入：Tab 切换
# ═════════════════════════════════════════════════════════════════════════
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		visible = !visible
		if not visible:
			_is_dragging = false
		get_viewport().set_input_as_handled()


# ═════════════════════════════════════════════════════════════════════════
# 每帧更新
# ═════════════════════════════════════════════════════════════════════════
func _process(_delta: float) -> void:
	if not visible:
		return
	if _canvas != null:
		_canvas.queue_redraw()


# ── 拖拽输入处理 ──────────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging = true
				_drag_start_mouse = mb.position
				_drag_start_offset = _drag_offset
			else:
				_is_dragging = false
	elif event is InputEventMouseMotion and _is_dragging:
		var mm_ev := event as InputEventMouseMotion
		var delta_px: Vector2 = mm_ev.position - _drag_start_mouse
		# 像素偏移转世界单位偏移（负号：拖右 → 地图向右 → 中心向左偏移）
		var px_per_world: float = (_map_size * 0.5) / VIEW_RADIUS
		_drag_offset = _drag_start_offset - delta_px / px_per_world


# ═════════════════════════════════════════════════════════════════════════
# 绘制（由 TabMapCanvas._draw() 回调）
# ═════════════════════════════════════════════════════════════════════════
func _do_draw(canvas: Control) -> void:
	if _mm == null:
		return

	var ms: float = _map_size
	var fog_circles: Array  = _mm._fog_circles
	var walk_rects:  Array  = _mm._walk_rects
	var landmarks:   Array  = _mm._landmarks
	var explore_r:   float  = _mm.EXPLORE_RADIUS
	var fade_w:      float  = _mm.FOG_FADE_WIDTH
	var cell_sz:     float  = _mm.FOG_CELL_SIZE

	# 1. WALK 矩形按格子绘制（带迷雾渐变 alpha）
	for r in walk_rects:
		var cx: float = r[0]
		while cx < r[1]:
			var cx_end: float = minf(cx + cell_sz, r[1])
			var cell_cx: float = (cx + cx_end) * 0.5

			var cz: float = r[2]
			while cz < r[3]:
				var cz_end: float = minf(cz + cell_sz, r[3])
				var cell_cz: float = (cz + cz_end) * 0.5

				var alpha: float = _fog_alpha_local(cell_cx, cell_cz, fog_circles, explore_r, fade_w)
				if alpha > 0.01:
					var c := Color(COLOR_FLOOR.r, COLOR_FLOOR.g, COLOR_FLOOR.b, COLOR_FLOOR.a * alpha)
					var tl := _world_to_ui(cx, cz, ms) - Vector2(RECT_INFLATE, RECT_INFLATE)
					var br := _world_to_ui(cx_end, cz_end, ms) + Vector2(RECT_INFLATE, RECT_INFLATE)
					canvas.draw_rect(Rect2(tl, br - tl), c)

				cz = cz_end
			cx = cx_end

	# 2. 地标（3 层发光，只在已探索区域）
	for lm in landmarks:
		var lx: float = lm["wx"]
		var lz: float = lm["wz"]
		if not _in_fog_local(lx, lz, fog_circles, explore_r):
			continue
		var uv := _world_to_ui(lx, lz, ms)
		if uv.x < -20.0 or uv.x > ms + 20.0 or uv.y < -20.0 or uv.y > ms + 20.0:
			continue
		_draw_landmark(canvas, uv, lm["kind"])

	# 3. 玩家三角形（居中）
	_draw_player_triangle(canvas, ms)

	# 无边框、无装饰（大地图风格简洁）


# ── 迷雾：点是否在探索圆内 ───────────────────────────────────────────────
func _in_fog_local(wx: float, wz: float, fog: Array, explore_r: float) -> bool:
	var p := Vector2(wx, wz)
	for c in fog:
		if p.distance_squared_to(c) <= explore_r * explore_r:
			return true
	return false


# ── 迷雾：计算渐变 alpha ──────────────────────────────────────────────────
func _fog_alpha_local(wx: float, wz: float, fog: Array, explore_r: float, fade_w: float) -> float:
	var p := Vector2(wx, wz)
	var min_dist: float = INF
	var inner: float = explore_r - fade_w
	for c in fog:
		var d: float = p.distance_to(c)
		if d < min_dist:
			min_dist = d
		if min_dist <= inner:
			return 1.0
	if min_dist == INF:
		return 0.0
	if min_dist <= explore_r:
		return 1.0 - (min_dist - inner) / fade_w
	return 0.0


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
	# 玩家位置在大地图上的实际像素坐标（受拖拽偏移影响）
	var center: Vector2 = _world_to_ui(_mm._player_wx if _mm != null else 0.0,
										_mm._player_wz if _mm != null else 0.0, ms)
	var r := ms * 0.025
	var a: float = 0.0
	if _mm != null:
		a = _mm._player_ry

	canvas.draw_circle(center, r * 2.4, Color(COLOR_PLAYER_GLOW.r, COLOR_PLAYER_GLOW.g, COLOR_PLAYER_GLOW.b, 0.12))
	canvas.draw_circle(center, r * 1.5, Color(COLOR_PLAYER_GLOW.r, COLOR_PLAYER_GLOW.g, COLOR_PLAYER_GLOW.b, 0.25))
	canvas.draw_circle(center, r * 0.9, Color(COLOR_PLAYER_GLOW.r, COLOR_PLAYER_GLOW.g, COLOR_PLAYER_GLOW.b, 0.40))

	var tip   := center + Vector2( sin(a),        -cos(a))        * r * 1.8
	var left  := center + Vector2( sin(a + 2.35), -cos(a + 2.35)) * r
	var right := center + Vector2( sin(a - 2.35), -cos(a - 2.35)) * r

	var so := r * 0.30
	var tip_o   := center + Vector2( sin(a),        -cos(a))        * (r * 1.8 + so)
	var left_o  := center + Vector2( sin(a + 2.35), -cos(a + 2.35)) * (r + so)
	var right_o := center + Vector2( sin(a - 2.35), -cos(a - 2.35)) * (r + so)
	canvas.draw_polygon(PackedVector2Array([tip_o, left_o, right_o]), PackedColorArray([COLOR_PLAYER_OUT]))
	canvas.draw_polygon(PackedVector2Array([tip, left, right]),       PackedColorArray([COLOR_PLAYER]))


# ═════════════════════════════════════════════════════════════════════════
# 坐标转换：世界坐标 → 大地图 UI 像素（以玩家为中心，动态视野半径）
# ═════════════════════════════════════════════════════════════════════════
func _world_to_ui(wx: float, wz: float, ms: float) -> Vector2:
	var half := ms * 0.5
	var px: float = 0.0
	var pz: float = 0.0
	if _mm != null:
		px = _mm._player_wx
		pz = _mm._player_wz
	# 玩家居中 + 拖拽偏移
	return Vector2(
		(wx - px - _drag_offset.x) / VIEW_RADIUS * half + half,
		(wz - pz - _drag_offset.y) / VIEW_RADIUS * half + half
	)
