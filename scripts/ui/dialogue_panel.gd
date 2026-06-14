extends CanvasLayer

# DialoguePanel: BOSS 死后 NPC 对话框 (系统②/程序②). D3 风格底部对话条.
#   由 boss_npc 调用 start_dialogue(speaker, lines) 启动; 点击对话框任意处推进下一句;
#   最后一句后再点击 → emit dialogue_finished → boss_npc 调 RiftManager.emit_run_cleared() 弹结算.
#
# 盖在 HUD(100)/背包(110) 之上、结算(120) 之下 → layer=118.
# 视觉与 settlement_panel 同源 D3 配色 (金框暗底).

signal dialogue_finished()

# ── D3 配色 (与 settlement_panel 一致) ───────────────────────
const GOLD := Color(0.72, 0.56, 0.26)
const GOLD_DIM := Color(0.42, 0.34, 0.19)
const PANEL_FILL := Color(0.09, 0.075, 0.058, 0.99)
const NAME_COL := Color(1.0, 0.84, 0.42)
const TEXT := Color(0.88, 0.85, 0.78)
const HINT_COL := Color(0.62, 0.56, 0.46)

var _root: Control = null
var _name_lbl: Label = null
var _line_lbl: Label = null
var _hint_lbl: Label = null

var _lines: Array = []
var _index: int = 0
var _active: bool = false

func _ready() -> void:
	layer = 118
	add_to_group("dialogue_panel")
	_build_ui()
	_root.visible = false

func _sbox(fill: Color, border: int, bcol: Color, radius: int, pad: int = 16) -> StyleBoxFlat:
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

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	# 整个根接收点击 (点任意处推进), 但不挡掉点击事件之外的渲染.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(_on_gui_input)
	add_child(_root)

	# 屏幕中下方对话框 (锚定底边, 整体上移到下半屏中部, 避开 HUD 技能栏).
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -560
	panel.offset_right = 560
	panel.offset_top = -620
	panel.offset_bottom = -420
	panel.add_theme_stylebox_override("panel", _sbox(PANEL_FILL, 3, GOLD, 5, 22))
	# 让点击穿到 _root 的 gui_input (面板本身不吞事件).
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vbox)

	# 说话者名.
	_name_lbl = Label.new()
	_name_lbl.text = ""
	_name_lbl.add_theme_color_override("font_color", NAME_COL)
	_name_lbl.add_theme_font_size_override("font_size", 28)
	_name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_name_lbl)

	# 金色分隔线.
	var rule := Panel.new()
	rule.custom_minimum_size = Vector2(0, 2)
	var rs := StyleBoxFlat.new()
	rs.bg_color = GOLD_DIM
	rule.add_theme_stylebox_override("panel", rs)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rule)

	# 台词正文 (自动换行).
	_line_lbl = Label.new()
	_line_lbl.text = ""
	_line_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_lbl.add_theme_color_override("font_color", TEXT)
	_line_lbl.add_theme_font_size_override("font_size", 24)
	_line_lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_line_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_line_lbl)

	# 底部提示 (右对齐).
	_hint_lbl = Label.new()
	_hint_lbl.text = "▼ 点击继续"
	_hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_lbl.add_theme_color_override("font_color", HINT_COL)
	_hint_lbl.add_theme_font_size_override("font_size", 18)
	_hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_hint_lbl)

# ── 公开 API ──────────────────────────────────────────────────
func start_dialogue(speaker: String, lines: Array) -> void:
	if lines == null or lines.is_empty():
		dialogue_finished.emit()
		return
	_lines = lines
	_index = 0
	_active = true
	_name_lbl.text = speaker
	_show_current()
	_root.visible = true
	_root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.3)

func _show_current() -> void:
	_line_lbl.text = String(_lines[_index])
	# 最后一句改提示文案.
	_hint_lbl.text = "▼ 点击结束" if _index >= _lines.size() - 1 else "▼ 点击继续"

func _advance() -> void:
	if not _active:
		return
	_index += 1
	if _index >= _lines.size():
		_finish()
		return
	_show_current()

func _finish() -> void:
	_active = false
	_root.visible = false
	dialogue_finished.emit()

# ── 点击推进 ──────────────────────────────────────────────────
func _on_gui_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_advance()
			_root.accept_event()
