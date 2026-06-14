extends CanvasLayer

# 守门人死亡结算面板 (系统②/程序②) — V3.0 单局大秘境通关页, 视觉按 D3 风格重排 (美术 D)。
#   守门人 (=屠夫) 死亡 = 单局通关 -> RiftManager.run_cleared(用时, 击杀数) 触发.
#   展示: 通关标题 / 用时(mm:ss) / 击杀总数 / 固定掉落物 (橙+绿套, 带品质色).
#   操作: 按 R 重开本局 (RiftManager.reset_rift() 后切回 L2 起始场景).
#   数据源不变: RiftManager.run_cleared / reset_rift, DataTables.get_boss_drop_items.
#
# 盖在 HUD(100)/背包(110) 之上 (layer=120)。掉落行为带金框的占位条, 美术可替换图标。

const START_SCENE: String = "res://scenes/levels/level_02_play.tscn"
const SET_COLOR: Color = Color(0.2, 0.85, 0.2)   # 套装绿 (与 ItemInstance.display_color 一致)

# ── D3 配色 ───────────────────────────────────────────────────
const GOLD := Color(0.72, 0.56, 0.26)
const GOLD_DIM := Color(0.42, 0.34, 0.19)
const PANEL_FILL := Color(0.09, 0.075, 0.058, 0.99)
const SUB_FILL := Color(0.06, 0.05, 0.04, 1.0)
const ROW_FILL := Color(0.035, 0.03, 0.024, 1.0)
const TITLE := Color(1.0, 0.84, 0.42)
const TEXT := Color(0.85, 0.82, 0.74)
const MUTED := Color(0.6, 0.55, 0.46)

var _root: Control = null
var _time_kill_lbl: Label = null
var _loot_box: VBoxContainer = null
var _visible: bool = false

func _ready() -> void:
	layer = 120
	add_to_group("settlement_panel")
	_build_ui()
	_root.visible = false
	_connect()

# ── 样式工具 ──────────────────────────────────────────────────
func _sbox(fill: Color, border: int, bcol: Color, radius: int, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_border_width_all(border)
	s.border_color = bcol
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s

func _gold_rule() -> Panel:
	var r := Panel.new()
	r.custom_minimum_size = Vector2(0, 2)
	var s := StyleBoxFlat.new()
	s.bg_color = GOLD_DIM
	r.add_theme_stylebox_override("panel", s)
	return r

# ── UI 构建 ───────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)

	# 半透明遮罩.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	# 居中主面板.
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -340
	panel.offset_top = -300
	panel.offset_right = 340
	panel.offset_bottom = 300
	panel.add_theme_stylebox_override("panel", _sbox(PANEL_FILL, 3, GOLD, 4, 18))
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	# 通关标题.
	var title := Label.new()
	title.text = "大秘境通关！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TITLE)
	title.add_theme_font_size_override("font_size", 56)
	vbox.add_child(title)

	vbox.add_child(_gold_rule())

	# 用时 / 击杀 (框内强调).
	var stat_frame := PanelContainer.new()
	stat_frame.add_theme_stylebox_override("panel", _sbox(SUB_FILL, 2, GOLD_DIM, 3, 12))
	vbox.add_child(stat_frame)
	_time_kill_lbl = Label.new()
	_time_kill_lbl.text = "用时 00:00      击杀 0"
	_time_kill_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_kill_lbl.add_theme_color_override("font_color", TEXT)
	_time_kill_lbl.add_theme_font_size_override("font_size", 24)
	stat_frame.add_child(_time_kill_lbl)

	# 战利品标题.
	var loot_title := Label.new()
	loot_title.text = "战利品"
	loot_title.add_theme_color_override("font_color", GOLD)
	loot_title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(loot_title)

	# 掉落列表 (滚动容器防溢出).
	var loot_frame := PanelContainer.new()
	loot_frame.add_theme_stylebox_override("panel", _sbox(SUB_FILL, 2, GOLD_DIM, 3, 8))
	loot_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(loot_frame)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	loot_frame.add_child(scroll)
	_loot_box = VBoxContainer.new()
	_loot_box.add_theme_constant_override("separation", 4)
	_loot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_loot_box)

	# 底部重开按钮条.
	var btn_bar := PanelContainer.new()
	btn_bar.add_theme_stylebox_override("panel", _sbox(Color(0.16, 0.05, 0.04), 2, GOLD_DIM, 3, 8))
	vbox.add_child(btn_bar)
	var hint := Label.new()
	hint.text = "按 [ R ] 重新开始"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", TITLE)
	hint.add_theme_font_size_override("font_size", 20)
	btn_bar.add_child(hint)

func _connect() -> void:
	var rm: Node = get_node_or_null("/root/RiftManager")
	if rm != null and rm.has_signal("run_cleared"):
		rm.run_cleared.connect(_on_run_cleared)

func _dt() -> Node:
	return get_node_or_null("/root/DataTables")

# ── 通关回调 ──────────────────────────────────────────────────
func _on_run_cleared(clear_time_sec: float, kill_count: int) -> void:
	if _visible:
		return
	_time_kill_lbl.text = "用时 %s      击杀 %d" % [_fmt_time(clear_time_sec), kill_count]
	_fill_loot()
	_visible = true
	_root.visible = true
	_root.modulate.a = 0.0
	var tw: Tween = create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.5)

func _fill_loot() -> void:
	for c in _loot_box.get_children():
		c.queue_free()
	var dt: Node = _dt()
	var items: Array = []
	if dt != null and dt.has_method("get_boss_drop_items"):
		items = dt.get_boss_drop_items()
	for it in items:
		if it == null:
			continue
		var col: Color = Color.WHITE
		if it.has_method("display_color"):
			col = it.display_color()
		elif it.is_set:
			col = SET_COLOR
		else:
			col = ItemInstance.QUALITY_COLORS.get(it.quality, Color.WHITE)
		_loot_box.add_child(_loot_row(it.display_name, col))

# 单条掉落 = 金框条 (左侧品质色占位格 + 物品名), 美术可往占位格塞图标.
func _loot_row(item_name: String, col: Color) -> PanelContainer:
	var row := PanelContainer.new()
	var s := _sbox(ROW_FILL, 1, GOLD_DIM, 2, 6)
	row.add_theme_stylebox_override("panel", s)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	row.add_child(h)
	# 品质色占位格 (图标位).
	var icon := Panel.new()
	icon.custom_minimum_size = Vector2(28, 28)
	var isb := StyleBoxFlat.new()
	isb.bg_color = ROW_FILL
	isb.set_border_width_all(2)
	isb.border_color = col
	isb.set_corner_radius_all(2)
	icon.add_theme_stylebox_override("panel", isb)
	h.add_child(icon)
	var lbl := Label.new()
	lbl.text = item_name
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", col)
	h.add_child(lbl)
	return row

# ── R 重开 ────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _visible and Input.is_key_pressed(KEY_R):
		_visible = false
		Sfx.play("ui_confirm")
		var rm: Node = get_node_or_null("/root/RiftManager")
		if rm != null and rm.has_method("reset_rift"):
			rm.reset_rift()
		get_tree().change_scene_to_file(START_SCENE)

# ── 工具 ──────────────────────────────────────────────────────
func _fmt_time(sec: float) -> String:
	var total: int = int(sec)
	return "%02d:%02d" % [total / 60, total % 60]
