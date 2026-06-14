extends CanvasLayer

# ── 常驻小地图（右上角 HUD）─────────────────────────────────────────────
# 架构：2D 程序化绘制（_draw()），不使用 SubViewport / Camera3D。
# 数据来源：level 组节点的 WALK / LANDMARKS / SCALE 常量（自动读取）。
# 显示范围：以玩家为中心，世界半径 VIEW_RADIUS 单位内的已探索区域。
# 尺寸：屏幕宽度 × MAP_SIZE_RATIO，正方形，右上角固定边距。

# ── 显示参数 ─────────────────────────────────────────────────────────────
const VIEW_RADIUS: float         = 55.0   # 小地图视口世界半径（已含 SCALE）
const EXPLORE_RADIUS: float      = 28.0   # 玩家每次探索的圆形半径（世界单位）
const FOG_UPDATE_INTERVAL: float = 0.15   # 迷雾采样间隔（秒）
const MAP_SIZE_RATIO: float      = 0.14   # 小地图边长 = 屏幕宽 × 此值（缩小一半）
const MARGIN: float              = 16.0   # 距屏幕右/上边缘的像素距离
const RECT_INFLATE: float        = 1.5    # 矩形扩展量（消除拼接缝隙）
# 格子目标像素大小：自适应分辨率，越小越平滑但绘制调用越多（性能敏感）
# 4K屏(3840px)下 FOG_CELL_PX=6 → FOG_CELL_SIZE≈1.2，draw_rect调用数约2.5万次/帧（可接受）
# FOG_CELL_PX=2 时约22万次/帧 → 卡顿根本原因
const FOG_CELL_PX: float         = 6.0   # 每格目标屏幕像素数（提高9倍减少绘制调用）
const FOG_FADE_WIDTH: float      = 10.0  # 渐变过渡带宽度（世界单位，加大柔化）
# FOG_CELL_SIZE 在运行时由 _map_size 动态计算，见 _update_fog_cell_size()
var FOG_CELL_SIZE: float         = 3.0   # 运行时动态值，不要直接用
# 迷雾圆心上限：防止长时间游玩导致O(n)爆炸
# EXPLORE_RADIUS*0.5 步距，关卡约200×200世界单位 → 理论最大不超过此值
const MAX_FOG_CIRCLES: int       = 800
# 空间哈希格子尺寸（世界单位）：用于O(1)附近圆心查找
const SPATIAL_CELL: float        = 12.0  # 略小于 EXPLORE_RADIUS，保证不漏检

# ── 颜色 ─────────────────────────────────────────────────────────────────
const COLOR_FLOOR_LARGE := Color(0.22, 0.16, 0.11, 0.90)  # 已探索底色
const COLOR_FLOOR_SMALL := Color(0.22, 0.16, 0.11, 0.90)  # 同上
const COLOR_FLOOR_EDGE  := Color(0.50, 0.36, 0.20, 0.35)  # 矩形描边（已停用）
const COLOR_BORDER      := Color(0.55, 0.40, 0.18, 1.00)  # 金色外边框
const COLOR_PLAYER_GLOW := Color(0.30, 0.55, 1.00, 1.00)  # 玩家发光底座
const PLAYER_ARROW_TEX: String = "res://assets/ui/player_arrow.png"

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

# 迷雾：存储历史探索圆心列表（世界坐标 Vector2），上限 MAX_FOG_CIRCLES
var _fog_circles: Array = []   # Array[Vector2]
# 去重用：记录上次添加的圆心位置
var _last_fog_pos: Vector2 = Vector2(INF, INF)
# 空间哈希：key = Vector2i(floor(wx/CELL), floor(wz/CELL))，value = Array[Vector2]
# 用于 _fog_alpha 的 O(1) 邻域查找，替代 O(n) 全遍历
var _fog_spatial: Dictionary = {}

# 玩家当前世界坐标（每帧缓存）
var _player_wx: float = 0.0
var _player_wz: float = 0.0
var _player_ry: float = 0.0

const DRAW_FPS: float = 20.0  # 小地图绘制帧率上限，防止每帧都触发 draw_rect

var _fog_timer: float = 0.0
var _draw_timer: float = 0.0  # 限速计时器
var _arrow_tex: Texture2D = null
# 脏标志：仅当玩家移动或迷雾更新时触发重绘，避免每帧无效重绘
var _needs_redraw: bool = true
var _last_draw_wx: float = INF
var _last_draw_wz: float = INF


# ═════════════════════════════════════════════════════════════════════════
# 初始化
# ═════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	layer = 105
	add_to_group("minimap")
	_map_size = get_viewport().size.x * MAP_SIZE_RATIO
	_update_fog_cell_size()
	get_viewport().size_changed.connect(_on_viewport_resized)
	if ResourceLoader.exists(PLAYER_ARROW_TEX):
		_arrow_tex = load(PLAYER_ARROW_TEX)
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
	_update_fog_cell_size()
	_resize_panel()
	if _canvas != null:
		_canvas.queue_redraw()


# 动态格子尺寸：FOG_CELL_PX 像素 → 对应世界单位
func _update_fog_cell_size() -> void:
	# 每像素对应的世界单位 = VIEW_RADIUS / (_map_size * 0.5)
	var world_per_px: float = VIEW_RADIUS / (_map_size * 0.5)
	# 最小值 1.5：防止 4K 高分辨率下格子过小导致 draw_rect 调用数爆炸
	FOG_CELL_SIZE = maxf(FOG_CELL_PX * world_per_px, 1.5)


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
	if _player == null or not is_instance_valid(_player) or not _player.is_inside_tree():
		return

	var pos: Vector3 = _player.global_position
	_player_wx = pos.x
	_player_wz = pos.z
	_player_ry = _player.rotation.y

	_fog_timer += delta
	if _fog_timer >= FOG_UPDATE_INTERVAL:
		_fog_timer = 0.0
		_record_fog_circle(_player_wx, _player_wz)

	# 脏标志 + 帧率限速：玩家移动超过半格且距上次绘制超过 1/DRAW_FPS 秒才重绘
	_draw_timer += delta
	var move_sq: float = (_player_wx - _last_draw_wx) * (_player_wx - _last_draw_wx) \
		+ (_player_wz - _last_draw_wz) * (_player_wz - _last_draw_wz)
	if (_needs_redraw or move_sq > 0.25) and _draw_timer >= 1.0 / DRAW_FPS:
		_draw_timer = 0.0
		_needs_redraw = false
		_last_draw_wx = _player_wx
		_last_draw_wz = _player_wz
		if _canvas != null:
			_canvas.queue_redraw()


# ── 迷雾：记录探索圆心 ───────────────────────────────────────────────────
func _record_fog_circle(wx: float, wz: float) -> void:
	var cur := Vector2(wx, wz)
	if _last_fog_pos.distance_to(cur) < EXPLORE_RADIUS * 0.5:
		return
	# 超上限时移除最旧的圆心（FIFO）并从空间哈希完全清除
	if _fog_circles.size() >= MAX_FOG_CIRCLES:
		var old: Vector2 = _fog_circles[0]
		_fog_circles.remove_at(0)
		# 必须清除所有写入时覆盖的格子，否则引用泄漏导致越玩越卡
		var r_del: int = int(ceil(EXPLORE_RADIUS / SPATIAL_CELL)) + 1
		var ocx: int = int(old.x / SPATIAL_CELL)
		var ocz: int = int(old.y / SPATIAL_CELL)
		for dx in range(-r_del, r_del + 1):
			for dz in range(-r_del, r_del + 1):
				var key := Vector2i(ocx + dx, ocz + dz)
				if _fog_spatial.has(key):
					(_fog_spatial[key] as Array).erase(old)
	_fog_circles.append(cur)
	_last_fog_pos = cur
	_needs_redraw = true
	# 写入空间哈希：覆盖圆能影响到的格子范围（ceil(R/CELL)+1），去重写入
	# EXPLORE_RADIUS=16, SPATIAL_CELL=12 → r=2（5×5=25格），比原来81格减少67%
	var r: int = int(ceil(EXPLORE_RADIUS / SPATIAL_CELL)) + 1
	var cx: int = int(cur.x / SPATIAL_CELL)
	var cz: int = int(cur.y / SPATIAL_CELL)
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var key := Vector2i(cx + dx, cz + dz)
			if not _fog_spatial.has(key):
				_fog_spatial[key] = []
			var arr: Array = _fog_spatial[key] as Array
			# 去重：同一圆心不重复写入同一格子（之前未去重导致 distance_to 重复计算）
			if not arr.has(cur):
				arr.append(cur)


# ── 空间哈希辅助：取点所在格子的候选圆心列表（无重复）─────────────────────
func _spatial_candidates(wx: float, wz: float) -> Array:
	var key := Vector2i(int(wx / SPATIAL_CELL), int(wz / SPATIAL_CELL))
	if _fog_spatial.has(key):
		return _fog_spatial[key] as Array
	return []


# ── 判断世界坐标点是否在任意探索圆内（全程 distance_squared，无平方根）────────
func _in_fog(wx: float, wz: float) -> bool:
	var px: float = wx
	var pz: float = wz
	var r2: float = EXPLORE_RADIUS * EXPLORE_RADIUS
	for c in _spatial_candidates(wx, wz):
		var dx: float = px - c.x
		var dz: float = pz - c.y
		if dx * dx + dz * dz <= r2:
			return true
	return false


# ── 计算点到探索圆边缘的渐变 alpha（全程 distance_squared，仅最终开一次平方根）
func _fog_alpha(wx: float, wz: float) -> float:
	var px: float = wx
	var pz: float = wz
	var inner: float = EXPLORE_RADIUS - FOG_FADE_WIDTH
	var inner2: float = inner * inner
	var explore2: float = EXPLORE_RADIUS * EXPLORE_RADIUS
	var min_dist2: float = INF
	for c in _spatial_candidates(wx, wz):
		var dx: float = px - c.x
		var dz: float = pz - c.y
		var d2: float = dx * dx + dz * dz
		if d2 < min_dist2:
			min_dist2 = d2
		if min_dist2 <= inner2:
			return 1.0   # 早退：完全在圆内，无需平方根
	if min_dist2 == INF or min_dist2 > explore2:
		return 0.0
	# 仅到这里才开一次平方根（渐变区域）
	var min_dist: float = sqrt(min_dist2)
	return 1.0 - (min_dist - inner) / FOG_FADE_WIDTH


# ═════════════════════════════════════════════════════════════════════════
# 绘制（由 MinimapCanvas._draw() 回调）
# 边缘细格子策略：
#   粗格子(FOG_CELL_SIZE) 扫描全区域 → alpha 完全在内部(≥EDGE_HI)直接绘制；
#   边缘渐变区(EDGE_LO < alpha < EDGE_HI) 细分为 FOG_CELL_SIZE/EDGE_SUBDIV 的小格子重绘；
#   完全在迷雾外(≤EDGE_LO) 跳过。
#   效果：内部填充无锯齿，边缘平滑，总计算量约增加 20~30%。
# ═════════════════════════════════════════════════════════════════════════
const EDGE_LO: float      = 0.05  # alpha 低于此值视为完全遮蔽，跳过
const EDGE_HI: float      = 0.95  # alpha 高于此值视为完全探索，粗格子直接绘制
const EDGE_SUBDIV: int    = 3     # 边缘区细分倍数（3 → 细格子 = 粗格子/3）

func _do_draw(canvas: Control) -> void:
	var ms: float = _map_size
	var fine_cell: float = FOG_CELL_SIZE / float(EDGE_SUBDIV)

	# 1. 遍历所有 WALK 矩形，按格子绘制已探索区域
	for i in range(_walk_rects.size()):
		var r: Array = _walk_rects[i]
		var world_area: float = (r[1] - r[0]) * (r[3] - r[2])
		var floor_color: Color = COLOR_FLOOR_LARGE if world_area > 800.0 else COLOR_FLOOR_SMALL

		# 粗格子扫描
		var cx: float = r[0]
		while cx < r[1]:
			var cx_end: float = minf(cx + FOG_CELL_SIZE, r[1])
			var cell_cx: float = (cx + cx_end) * 0.5

			var cz: float = r[2]
			while cz < r[3]:
				var cz_end: float = minf(cz + FOG_CELL_SIZE, r[3])
				var cell_cz: float = (cz + cz_end) * 0.5

				var alpha: float = _fog_alpha(cell_cx, cell_cz)

				if alpha <= EDGE_LO:
					# 完全遮蔽，跳过
					pass
				elif alpha >= EDGE_HI:
					# 完全探索：绘制底色
					var tl := _world_to_ui(cx, cz, ms) - Vector2(RECT_INFLATE, RECT_INFLATE)
					var br := _world_to_ui(cx_end, cz_end, ms) + Vector2(RECT_INFLATE, RECT_INFLATE)
					var rect := Rect2(tl, br - tl)
					var c := Color(floor_color.r, floor_color.g, floor_color.b, floor_color.a * alpha)
					canvas.draw_rect(rect, c)
				else:
					# 边缘渐变区（迷雾边缘）：细分消除锯齿，无轮廓线
					var fx: float = cx
					while fx < cx_end:
						var fx_end: float = minf(fx + fine_cell, cx_end)
						var fcx: float = (fx + fx_end) * 0.5
						var fz: float = cz
						while fz < cz_end:
							var fz_end: float = minf(fz + fine_cell, cz_end)
							var fcz: float = (fz + fz_end) * 0.5
							var fa: float = _fog_alpha(fcx, fcz)
							if fa > EDGE_LO:
								var c := Color(floor_color.r, floor_color.g, floor_color.b, floor_color.a * fa)
								var tl := _world_to_ui(fx, fz, ms) - Vector2(RECT_INFLATE, RECT_INFLATE)
								var br := _world_to_ui(fx_end, fz_end, ms) + Vector2(RECT_INFLATE, RECT_INFLATE)
								canvas.draw_rect(Rect2(tl, br - tl), c)
							fz = fz_end
						fx = fx_end

				cz = cz_end
			cx = cx_end

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



# ── 地标 3 层发光绘制 ─────────────────────────────────────────────────────
func _draw_landmark(canvas: Control, uv: Vector2, kind: String) -> void:
	var style: Array = LANDMARK_STYLE.get(kind, [Color(1, 1, 1, 0.8), 4.0])
	var col: Color = style[0]
	var rad: float = style[1]

	canvas.draw_circle(uv, rad * 2.8, Color(col.r, col.g, col.b, 0.15))
	canvas.draw_circle(uv, rad * 1.8, Color(col.r, col.g, col.b, 0.35))
	canvas.draw_circle(uv, rad + 1.0, Color(1.0, 1.0, 1.0, 0.55))
	canvas.draw_circle(uv, rad, col)


# ── 玩家箭头图标 + 蓝色发光底座 ─────────────────────────────────────────
func _draw_player_triangle(canvas: Control, ms: float) -> void:
	var center := Vector2(ms * 0.5, ms * 0.5)
	var r := ms * 0.040
	var a := -_player_ry

	# 蓝色发光底座（三层，由大到小）
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
		# 降级：程序化三角形
		var tip   := center + Vector2( sin(a),        -cos(a))        * r * 1.8
		var left  := center + Vector2( sin(a + 2.35), -cos(a + 2.35)) * r
		var right := center + Vector2( sin(a - 2.35), -cos(a - 2.35)) * r
		canvas.draw_polygon(PackedVector2Array([tip, left, right]), PackedColorArray([Color.WHITE]))


# ═════════════════════════════════════════════════════════════════════════
# 坐标转换：世界坐标 → 小地图 UI 像素（以玩家为中心）
# ═════════════════════════════════════════════════════════════════════════
func _world_to_ui(wx: float, wz: float, ms: float) -> Vector2:
	var half := ms * 0.5
	return Vector2(
		(wx - _player_wx) / VIEW_RADIUS * half + half,
		(wz - _player_wz) / VIEW_RADIUS * half + half
	)
