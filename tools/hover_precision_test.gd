extends Node

# 实窗口 hover 精度自测 (非 headless).
# 运行: Godot_console.exe --path . res://tools/hover_precision_test.tscn
# 行为:
#   - 实例化并打开 inventory_panel
#   - 每帧读真实鼠标位置, 找几何上命中的格子(get_global_rect().has_point)
#   - 同时读该按钮 is_hovered() (引擎实际判定的 hover)
#   - 画十字准星 + 命中格高亮框 + 文本: 几何命中 slot / 引擎 hover slot / 是否一致
#   一致 = 输入映射与渲染 1:1 贴合; 不一致 = 仍有偏移.
# 退出: Esc.

var _panel: CanvasLayer = null
var _slot_btns: Dictionary = {}
var _bag_btns: Array = []
var _overlay: Control = null
var _label: Label = null

func _ready() -> void:
	var ps: PackedScene = load("res://scenes/ui/inventory_panel.tscn")
	_panel = ps.instantiate()
	add_child(_panel)
	await get_tree().process_frame
	if _panel.has_method("_set_open"):
		_panel._set_open(true)
	await get_tree().process_frame
	_slot_btns = _panel.get("_slot_buttons")
	var grid = _panel.get("_bag_grid")
	if grid != null:
		_bag_btns = grid.get_children()

	# 自测覆盖层 (画在最上层 CanvasLayer).
	var cl := CanvasLayer.new()
	cl.layer = 200
	add_child(cl)
	_overlay = Control.new()
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_script(_make_drawer_script())
	cl.add_child(_overlay)
	_overlay.set("host", self)

	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 28)
	_label.add_theme_color_override("font_color", Color(1, 1, 0.4))
	cl.add_child(_label)

func _process(_dt: float) -> void:
	if _overlay != null:
		_overlay.queue_redraw()
	var mp: Vector2 = _overlay.get_global_mouse_position() if _overlay != null else Vector2.ZERO
	var geo_slot: int = -99
	var eng_slot: int = -99
	for s in _slot_btns:
		var b: Button = _slot_btns[s]
		if b.get_global_rect().has_point(mp):
			geo_slot = s
		if b.is_hovered():
			eng_slot = s
	var bag_geo := -1
	var bag_eng := -1
	for i in range(_bag_btns.size()):
		var b: Button = _bag_btns[i]
		if b.get_global_rect().has_point(mp):
			bag_geo = i
		if b.is_hovered():
			bag_eng = i
	var match_ok: bool = (geo_slot == eng_slot) and (bag_geo == bag_eng)
	if _label != null:
		_label.text = "mouse=%s\n装备: 几何命中=%s 引擎hover=%s\n背包: 几何命中=%s 引擎hover=%s\n%s" % [
			str(mp.round()), str(geo_slot), str(eng_slot), str(bag_geo), str(bag_eng),
			("OK 贴合 (输入<->渲染 1:1)" if match_ok else "FAIL 偏移!")
		]
		_label.add_theme_color_override("font_color", Color(0.4, 1, 0.4) if match_ok else Color(1, 0.4, 0.4))

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		get_tree().quit()

# 覆盖层绘制脚本: 画鼠标十字 + 命中格高亮.
func _make_drawer_script() -> GDScript:
	var src := """
extends Control
var host = null
func _draw():
	if host == null: return
	var mp = get_global_mouse_position()
	# 鼠标十字 (绿).
	draw_line(mp - Vector2(40,0), mp + Vector2(40,0), Color(0,1,0), 2.0)
	draw_line(mp - Vector2(0,40), mp + Vector2(0,40), Color(0,1,0), 2.0)
	# 装备槽: 几何命中=黄框, 引擎hover=青框 (重合则贴合).
	for s in host._slot_btns:
		var b = host._slot_btns[s]
		var r = b.get_global_rect()
		if r.has_point(mp):
			draw_rect(r, Color(1,1,0), false, 3.0)
		if b.is_hovered():
			draw_rect(r.grow(-4), Color(0,1,1), false, 3.0)
	for i in range(host._bag_btns.size()):
		var b = host._bag_btns[i]
		var r = b.get_global_rect()
		if r.has_point(mp):
			draw_rect(r, Color(1,1,0), false, 3.0)
		if b.is_hovered():
			draw_rect(r.grow(-3), Color(0,1,1), false, 3.0)
"""
	var gd := GDScript.new()
	gd.source_code = src
	gd.reload()
	return gd
