extends CanvasLayer

# 守门人死亡结算面板 (系统②/程序②) — V3.0 单局大秘境通关页.
#   守门人 (=屠夫) 死亡 = 单局通关 -> RiftManager.run_cleared(用时, 击杀数) 触发.
#   展示: 通关标题 / 用时(mm:ss) / 击杀总数 / 14 件固定掉落物 (橙+绿套, 带品质色).
#   操作: 按 R 重开本局 (RiftManager.reset_rift() 后切回 L2 起始场景).
#
# 完全程序化生成 Control 树, 与 hud.gd / inventory_panel.gd 同风格.
# 盖在 HUD(100)/背包(110) 之上 (layer=120).

const START_SCENE: String = "res://scenes/levels/level_02_play.tscn"
const SET_COLOR: Color = Color(0.2, 0.85, 0.2)   # 套装绿 (与 ItemInstance.display_color 一致)

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

# ── UI 构建 ───────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)

	# 半透明遮罩.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
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
	panel.offset_left = -320
	panel.offset_top = -280
	panel.offset_right = 320
	panel.offset_bottom = 280
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	# 通关标题.
	var title := Label.new()
	title.text = "大秘境通关！"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	title.add_theme_font_size_override("font_size", 64)
	vbox.add_child(title)

	# 用时 / 击杀.
	_time_kill_lbl = Label.new()
	_time_kill_lbl.text = "用时 00:00    击杀 0"
	_time_kill_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_kill_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	_time_kill_lbl.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_time_kill_lbl)

	vbox.add_child(HSeparator.new())

	# 战利品标题.
	var loot_title := Label.new()
	loot_title.text = "战利品"
	loot_title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	loot_title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(loot_title)

	# 掉落列表 (滚动容器防溢出).
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_loot_box = VBoxContainer.new()
	_loot_box.add_theme_constant_override("separation", 2)
	_loot_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_loot_box)

	# 底部提示.
	var hint := Label.new()
	hint.text = "按 R 重新开始"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	hint.add_theme_font_size_override("font_size", 18)
	vbox.add_child(hint)

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
	_time_kill_lbl.text = "用时 %s    击杀 %d" % [_fmt_time(clear_time_sec), kill_count]
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
		var lbl := Label.new()
		lbl.text = it.display_name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 18)
		var col: Color = Color.WHITE
		if it.has_method("display_color"):
			col = it.display_color()
		elif it.is_set:
			col = SET_COLOR
		else:
			col = ItemInstance.QUALITY_COLORS.get(it.quality, Color.WHITE)
		lbl.add_theme_color_override("font_color", col)
		_loot_box.add_child(lbl)

# ── R 重开 ────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if _visible and Input.is_key_pressed(KEY_R):
		_visible = false
		var rm: Node = get_node_or_null("/root/RiftManager")
		if rm != null and rm.has_method("reset_rift"):
			rm.reset_rift()
		get_tree().change_scene_to_file(START_SCENE)

# ── 工具 ──────────────────────────────────────────────────────
func _fmt_time(sec: float) -> String:
	var total: int = int(sec)
	return "%02d:%02d" % [total / 60, total % 60]
