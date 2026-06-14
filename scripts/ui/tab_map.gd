extends CanvasLayer

# ── Tab 大地图（全屏覆盖层）─────────────────────────────────────────────
# 按 Tab (toggle_map) 切换显示/隐藏，游戏不暂停。
# 绘制逻辑完全照搬 minimap_panel，数据直接从 _mm 读取，VIEW_RADIUS 用大地图的。

# ── 颜色（与 minimap_panel 一致）─────────────────────────────────────────
const COLOR_BORDER      := Color(0.55, 0.40, 0.18, 1.00)
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

const VIEW_RADIUS: float = 150.0   # 固定视野半径（世界单位，比小地图的 55 大）
const RECT_INFLATE: float = 1.5
const DRAW_FPS: float     = 20.0   # 20fps 节流

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

var _arrow_tex: Texture2D = null
var _draw_timer: float = 0.0


# ═════════════════════════════════════════════════════════════════════════
# 初始化
# ═════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	layer = 110
	visible = false
	if ResourceLoader.exists("res://assets/ui/player_arrow.png"):
		_arrow_tex = load("res://assets/ui/player_arrow.png")
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

	# 居中方形地图面板（不接收鼠标，不支持拖拽）
	_panel = Control.new()
	_panel.name = "TabMapPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	var candidates := get_tree().get_nodes_in_group("minimap")
	if candidates.size() > 0:
		_mm = candidates[0]
		return
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
		get_viewport().set_input_as_handled()


# ═════════════════════════════════════════════════════════════════════════
# 每帧更新（节流重绘）
# ═════════════════════════════════════════════════════════════════════════
func _process(delta: float) -> void:
	if not visible:
		return
	_draw_timer += delta
	if _draw_timer >= 1.0 / DRAW_FPS:
		_draw_timer = 0.0
		if _canvas != null:
			_canvas.queue_redraw()


# ═════════════════════════════════════════════════════════════════════════
# 绘制（逻辑完全照搬 minimap_panel._do_draw，数据从 _mm 取）
# ═════════════════════════════════════════════════════════════════════════
func _do_draw(canvas: Control) -> void:
	if _mm == null:
		return

	var ms: float = _map_size

	# 1. 遍历所有 WALK 矩形，按格子绘制已探索区域
	for r in _mm._walk_rects:
		var world_area: float = (r[1] - r[0]) * (r[3] - r[2])
		var floor_color: Color = _mm.COLOR_FLOOR_LARGE if world_area > 800.0 else _mm.COLOR_FLOOR_SMALL

		var cx: float = r[0]
		while cx < r[1]:
			var cx_end: float = minf(cx + _mm.FOG_CELL_SIZE, r[1])
			var cell_cx: float = (cx + cx_end) * 0.5

			var cz: float = r[2]
			while cz < r[3]:
				var cz_end: float = minf(cz + _mm.FOG_CELL_SIZE, r[3])
				var cell_cz: float = (cz + cz_end) * 0.5

				var alpha: float = _mm._fog_alpha(cell_cx, cell_cz)
				if alpha > 0.01:
					var c := Color(floor_color.r, floor_color.g, floor_color.b, floor_color.a * alpha)
					var tl := _world_to_ui(cx, cz, ms) - Vector2(RECT_INFLATE, RECT_INFLATE)
					var br := _world_to_ui(cx_end, cz_end, ms) + Vector2(RECT_INFLATE, RECT_INFLATE)
					canvas.draw_rect(Rect2(tl, br - tl), c)

				cz = cz_end
			cx = cx_end

	# 2. 地标（3 层发光，只在已探索区域）
	for lm in _mm._landmarks:
		var lx: float = lm["wx"]
		var lz: float = lm["wz"]
		if not _mm._in_fog(lx, lz):
			continue
		var uv := _world_to_ui(lx, lz, ms)
		if uv.x < -20.0 or uv.x > ms + 20.0 or uv.y < -20.0 or uv.y > ms + 20.0:
			continue
		_draw_landmark(canvas, uv, lm["kind"])

	# 3. 玩家标记（居中）
	_draw_player_triangle(canvas, ms)

	# 4. 金色外边框
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


# ── 玩家箭头（同 minimap，底座稍大）─────────────────────────────────────
func _draw_player_triangle(canvas: Control, ms: float) -> void:
	var center := Vector2(ms * 0.5, ms * 0.5)
	var r := ms * 0.030
	var a: float = -(_mm._player_ry if _mm != null else 0.0)

	canvas.draw_circle(center, r * 2.4, Color(COLOR_PLAYER_GLOW.r, COLOR_PLAYER_GLOW.g, COLOR_PLAYER_GLOW.b, 0.12))
	canvas.draw_circle(center, r * 1.5, Color(COLOR_PLAYER_GLOW.r, COLOR_PLAYER_GLOW.g, COLOR_PLAYER_GLOW.b, 0.25))
	canvas.draw_circle(center, r * 0.9, Color(COLOR_PLAYER_GLOW.r, COLOR_PLAYER_GLOW.g, COLOR_PLAYER_GLOW.b, 0.40))

	if _arrow_tex != null:
		var icon_size: float = r * 5.0
		var half_icon := Vector2(icon_size * 0.5, icon_size * 0.5)
		canvas.draw_set_transform(center, a, Vector2.ONE)
		canvas.draw_texture_rect(_arrow_tex, Rect2(-half_icon, Vector2(icon_size, icon_size)), false)
		canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		var tip   := center + Vector2(sin(a),        -cos(a))        * r * 1.8
		var left  := center + Vector2(sin(a + 2.35), -cos(a + 2.35)) * r
		var right := center + Vector2(sin(a - 2.35), -cos(a - 2.35)) * r
		canvas.draw_polygon(PackedVector2Array([tip, left, right]), PackedColorArray([Color.WHITE]))


# ═════════════════════════════════════════════════════════════════════════
# 坐标转换：世界坐标 → 大地图 UI 像素（以玩家为中心）
# ═════════════════════════════════════════════════════════════════════════
func _world_to_ui(wx: float, wz: float, ms: float) -> Vector2:
	var half := ms * 0.5
	var px: float = _mm._player_wx if _mm != null else 0.0
	var pz: float = _mm._player_wz if _mm != null else 0.0
	return Vector2(
		(wx - px) / VIEW_RADIUS * half + half,
		(wz - pz) / VIEW_RADIUS * half + half
	)
