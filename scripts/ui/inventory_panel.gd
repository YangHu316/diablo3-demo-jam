extends CanvasLayer

# 任务4 背包+装备面板 — 视觉按 D3《物品栏》参考重排 (美术 D)。
#   布局: 左=主属性栏 | 中=纸娃娃(立绘+13 装备槽) | 下=背包网格 | 底=资源占位栏
#   数据源全部沿用系统组接口, 仅重排视觉 + 加占位格 (PNG 由美术后替换):
#     - Inventory: get_bag_items / quick_equip / get_equipped / unequip + item_* 信号
#     - DataTables.get_fixed_panel_stats() (面板属性, 单一事实源)
#     - ProgressionManager.level (角色等级, 只读)
#   开关: toggle_inventory 动作 (默认 B; 缺省兜底 KEY_B)。
#
# 占位说明: 立绘/职业徽章/铁砧/物品图标都是带 D3 金框的占位格,
#   美术替换时把对应 PNG 塞进 TextureRect / 给 Button 设 icon 即可, 不动数据逻辑。

const COLS: int = 10
const ROWS: int = 4   # 10*4 = 40

# 参与面板展示的属性顺序与中文名 (绑定 DataTables.get_fixed_panel_stats).
const STAT_DISPLAY: Array = [
	[AffixDef.StatKind.AGILITY, "敏捷"],
	[AffixDef.StatKind.VITALITY, "体能"],
	[AffixDef.StatKind.ARMOR, "护甲"],
	[AffixDef.StatKind.ALL_RESIST, "全抗"],
	[AffixDef.StatKind.CRIT_CHANCE, "暴击率"],
	[AffixDef.StatKind.CRIT_DAMAGE, "暴伤"],
	[AffixDef.StatKind.ATTACK_SPEED, "攻速"],
	[AffixDef.StatKind.SKILL_DAMAGE, "技能伤害"],
	[AffixDef.StatKind.WEAPON_DAMAGE, "武器伤害"],
	[AffixDef.StatKind.MOVE_SPEED, "移速"],
]

# 纸娃娃槽位排布 (左列 5 / 右列 5 / 底部行 3), 控制总高度适配 648 基准.
const SLOT_COL_L: Array = [
	EquipSlots.Slot.HEAD, EquipSlots.Slot.SHOULDER, EquipSlots.Slot.AMULET,
	EquipSlots.Slot.CHEST, EquipSlots.Slot.GLOVES,
]
const SLOT_COL_R: Array = [
	EquipSlots.Slot.WRIST, EquipSlots.Slot.WAIST, EquipSlots.Slot.LEGS,
	EquipSlots.Slot.BOOTS, EquipSlots.Slot.RING_1,
]
const SLOT_ROW_B: Array = [EquipSlots.Slot.RING_2, EquipSlots.Slot.BOW, EquipSlots.Slot.QUIVER]

# ── D3 配色 ───────────────────────────────────────────────────
const GOLD := Color(0.72, 0.56, 0.26)
const GOLD_DIM := Color(0.42, 0.34, 0.19)
const PANEL_FILL := Color(0.10, 0.085, 0.065, 0.98)
const SUB_FILL := Color(0.07, 0.06, 0.048, 1.0)
const SLOT_FILL := Color(0.035, 0.03, 0.024, 1.0)
const TEXT := Color(0.84, 0.80, 0.72)
const TITLE := Color(0.96, 0.80, 0.42)
const MUTED := Color(0.52, 0.47, 0.40)

var _root: Control = null
var _bag_grid: GridContainer = null
var _slot_buttons: Dictionary = {}   # EquipSlots.Slot -> Button
var _stat_labels: Dictionary = {}    # StatKind -> Label
var _level_label: Label = null
var _open: bool = false

func _ready() -> void:
	layer = 110   # 盖在 HUD(100) 之上
	add_to_group("inventory_panel")
	_build_ui()
	_connect_signals()
	_set_open(false)
	_refresh_all()

# ── 样式工具 ──────────────────────────────────────────────────
func _sbox(fill: Color, border: int, bcol: Color, radius: int, pad: int = 8) -> StyleBoxFlat:
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

func _slot_style(hot: bool = false) -> StyleBoxFlat:
	return _sbox(SLOT_FILL, 2, GOLD if hot else GOLD_DIM, 2, 2)

# 一个带 D3 金框 + 居中占位字的占位格 (美术把 PNG 放进返回的 TextureRect).
func _placeholder(w: float, h: float, caption: String) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(w, h)
	p.add_theme_stylebox_override("panel", _sbox(SLOT_FILL, 2, GOLD_DIM, 3, 0))
	var tex := TextureRect.new()
	tex.name = "Art"
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tex)
	var cap := Label.new()
	cap.text = caption
	cap.set_anchors_preset(Control.PRESET_FULL_RECT)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap.add_theme_color_override("font_color", MUTED)
	cap.add_theme_font_size_override("font_size", 12)
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(cap)
	return p

# ── UI 构建 ───────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)

	# 半透明遮罩.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
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
	panel.offset_left = -480
	panel.offset_top = -314
	panel.offset_right = 480
	panel.offset_bottom = 314
	panel.add_theme_stylebox_override("panel", _sbox(PANEL_FILL, 3, GOLD, 4, 12))
	_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	_build_header(vbox)
	vbox.add_child(_gold_rule())

	# 中部: 左属性栏 | 纸娃娃.
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 16)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(mid)
	_build_stats_column(mid)
	_build_paperdoll(mid)

	_build_bag(vbox)
	_build_bottom_bar(vbox)

func _build_header(vbox: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	vbox.add_child(header)
	# 职业徽章占位 (D3 顶部圆形彩窗).
	header.add_child(_placeholder(46, 46, "职业"))
	var title := Label.new()
	title.text = "物品栏"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_color_override("font_color", TITLE)
	title.add_theme_font_size_override("font_size", 30)
	header.add_child(title)
	# 关闭 X.
	var close := Button.new()
	close.text = "✕"
	close.custom_minimum_size = Vector2(40, 40)
	close.add_theme_color_override("font_color", Color(0.85, 0.4, 0.3))
	close.add_theme_stylebox_override("normal", _sbox(SUB_FILL, 2, GOLD_DIM, 3, 0))
	close.add_theme_stylebox_override("hover", _sbox(Color(0.2, 0.08, 0.06), 2, GOLD, 3, 0))
	close.add_theme_stylebox_override("pressed", _sbox(SUB_FILL, 2, GOLD, 3, 0))
	close.pressed.connect(func(): _set_open(false))
	header.add_child(close)

func _gold_rule() -> Panel:
	var r := Panel.new()
	r.custom_minimum_size = Vector2(0, 2)
	var s := StyleBoxFlat.new()
	s.bg_color = GOLD_DIM
	r.add_theme_stylebox_override("panel", s)
	return r

# 左: 角色属性 (绑 DataTables.get_fixed_panel_stats + ProgressionManager.level).
func _build_stats_column(parent: HBoxContainer) -> void:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(220, 0)
	frame.add_theme_stylebox_override("panel", _sbox(SUB_FILL, 2, GOLD_DIM, 3, 12))
	parent.add_child(frame)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	frame.add_child(col)

	_level_label = Label.new()
	_level_label.text = "等级  1"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.add_theme_color_override("font_color", Color(0.55, 0.7, 1.0))
	_level_label.add_theme_font_size_override("font_size", 18)
	col.add_child(_level_label)

	col.add_child(_section_label("主属性"))
	for entry in STAT_DISPLAY:
		var sk: int = entry[0]
		var lbl := _stat_row("%s" % entry[1])
		col.add_child(lbl)
		_stat_labels[sk] = lbl

	col.add_child(_gold_rule())
	var detail := Button.new()
	detail.text = "详细信息"
	detail.add_theme_color_override("font_color", TEXT)
	detail.add_theme_stylebox_override("normal", _sbox(Color(0.16, 0.05, 0.04), 2, GOLD_DIM, 3, 4))
	detail.add_theme_stylebox_override("hover", _sbox(Color(0.24, 0.08, 0.06), 2, GOLD, 3, 4))
	detail.add_theme_stylebox_override("pressed", _sbox(Color(0.16, 0.05, 0.04), 2, GOLD, 3, 4))
	col.add_child(detail)

func _section_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", GOLD)
	l.add_theme_font_size_override("font_size", 13)
	return l

func _stat_row(name_txt: String) -> Label:
	var l := Label.new()
	l.text = "%s: 0" % name_txt
	l.add_theme_color_override("font_color", TEXT)
	l.add_theme_font_size_override("font_size", 12)
	return l

# 中: 纸娃娃 (立绘占位 + 13 装备槽).
func _build_paperdoll(parent: HBoxContainer) -> void:
	var doll := VBoxContainer.new()
	doll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll.add_theme_constant_override("separation", 4)
	parent.add_child(doll)

	var upper := HBoxContainer.new()
	upper.alignment = BoxContainer.ALIGNMENT_CENTER
	upper.add_theme_constant_override("separation", 12)
	upper.size_flags_vertical = Control.SIZE_EXPAND_FILL
	doll.add_child(upper)

	upper.add_child(_slot_column(SLOT_COL_L))
	# 中央角色立绘占位.
	var portrait := _placeholder(200, 255, "角色立绘\n(PNG 占位)")
	portrait.name = "Portrait"
	portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	upper.add_child(portrait)
	upper.add_child(_slot_column(SLOT_COL_R))

	# 底部武器行 (弓 / 箭袋), 居中.
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.add_theme_constant_override("separation", 16)
	doll.add_child(wrow)
	for s in SLOT_ROW_B:
		wrow.add_child(_make_equip_cell(s))

func _slot_column(slots: Array) -> VBoxContainer:
	var c := VBoxContainer.new()
	c.alignment = BoxContainer.ALIGNMENT_CENTER
	c.add_theme_constant_override("separation", 3)
	for s in slots:
		c.add_child(_make_equip_cell(s))
	return c

# 单个装备槽 = 金框方格按钮 (空=显示槽位名占位; 装上=物品名/品质色) + 下方说明.
func _make_equip_cell(slot_id: int) -> Control:
	var cell := VBoxContainer.new()
	cell.add_theme_constant_override("separation", 1)
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(40, 40)
	btn.clip_text = true
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	btn.add_theme_font_size_override("font_size", 8)
	btn.add_theme_stylebox_override("normal", _slot_style())
	btn.add_theme_stylebox_override("hover", _slot_style(true))
	btn.add_theme_stylebox_override("pressed", _slot_style(true))
	btn.add_theme_stylebox_override("disabled", _slot_style())
	btn.pressed.connect(_on_equip_slot_pressed.bind(slot_id))
	_slot_buttons[slot_id] = btn
	var cap := Label.new()
	cap.text = str(EquipSlots.SLOT_DISPLAY.get(slot_id, "?"))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", MUTED)
	cap.add_theme_font_size_override("font_size", 9)
	cell.add_child(btn)
	cell.add_child(cap)
	return cell

# 下: 背包 40 格.
func _build_bag(vbox: VBoxContainer) -> void:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", _sbox(SUB_FILL, 2, GOLD_DIM, 3, 10))
	vbox.add_child(frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	frame.add_child(box)

	var cap := _section_label("背包")
	box.add_child(cap)

	_bag_grid = GridContainer.new()
	_bag_grid.columns = COLS
	_bag_grid.add_theme_constant_override("h_separation", 3)
	_bag_grid.add_theme_constant_override("v_separation", 3)
	box.add_child(_bag_grid)
	for i in range(COLS * ROWS):
		var b := Button.new()
		b.custom_minimum_size = Vector2(30, 30)
		b.clip_text = true
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 9)
		b.add_theme_stylebox_override("normal", _slot_style())
		b.add_theme_stylebox_override("hover", _slot_style(true))
		b.add_theme_stylebox_override("pressed", _slot_style(true))
		b.add_theme_stylebox_override("disabled", _slot_style())
		b.pressed.connect(_on_bag_slot_pressed.bind(i))
		_bag_grid.add_child(b)

# 底: 资源占位栏 (铁砧/材料/金币/血岩 — 暂无数据源, 美术占位, 系统后接).
func _build_bottom_bar(vbox: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	vbox.add_child(bar)
	bar.add_child(_placeholder(40, 40, "铁砧"))
	bar.add_child(_resource_chip("材料", "—"))
	bar.add_child(_resource_chip("金币", "—"))
	bar.add_child(_resource_chip("血岩", "—"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var hint := Label.new()
	hint.text = "[ B ] 关闭"
	hint.add_theme_color_override("font_color", MUTED)
	hint.add_theme_font_size_override("font_size", 14)
	bar.add_child(hint)

func _resource_chip(name_txt: String, val: String) -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.add_theme_constant_override("separation", 4)
	var n := Label.new()
	n.text = name_txt
	n.add_theme_color_override("font_color", MUTED)
	n.add_theme_font_size_override("font_size", 13)
	var v := Label.new()
	v.text = val
	v.add_theme_color_override("font_color", TITLE)
	v.add_theme_font_size_override("font_size", 14)
	chip.add_child(n)
	chip.add_child(v)
	return chip

func _connect_signals() -> void:
	var inv: Node = _inv()
	if inv != null:
		if inv.has_signal("item_picked_up"):
			inv.item_picked_up.connect(func(_i): _refresh_bag())
		# V3.0: 换装只刷新背包/装备槽视觉, 不重算面板属性 (面板写死中期档).
		if inv.has_signal("item_equipped"):
			inv.item_equipped.connect(func(_s, _i): _refresh_bag(); _refresh_equip())
		if inv.has_signal("item_unequipped"):
			inv.item_unequipped.connect(func(_s, _i): _refresh_bag(); _refresh_equip())
	var pm: Node = _pm()
	if pm != null and pm.has_signal("level_up"):
		pm.level_up.connect(func(_lv, _u): _refresh_level())

func _dt() -> Node:
	return get_node_or_null("/root/DataTables")

func _inv() -> Node:
	return get_node_or_null("/root/Inventory")

func _pm() -> Node:
	return get_node_or_null("/root/ProgressionManager")

# ── 开关 ──────────────────────────────────────────────────────
func _unhandled_key_input(event: InputEvent) -> void:
	var toggled := false
	if InputMap.has_action("toggle_inventory"):
		if event.is_action_pressed("toggle_inventory"):
			toggled = true
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		toggled = true
	if toggled:
		_set_open(not _open)
		get_viewport().set_input_as_handled()

func _set_open(v: bool) -> void:
	_open = v
	_root.visible = v
	if v:
		_refresh_all()

# ── 交互 ──────────────────────────────────────────────────────
# 点背包格子 -> 若有物品则 quick_equip 自动装备.
func _on_bag_slot_pressed(index: int) -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	var items: Array = inv.get_bag_items()
	if index < 0 or index >= items.size():
		return
	inv.quick_equip(items[index])
	# 信号会触发刷新; 这里无需手动刷.

# 点装备槽 -> 卸下回背包.
func _on_equip_slot_pressed(slot: int) -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	if inv.get_equipped(slot) != null:
		inv.unequip(slot)

# ── 刷新 ──────────────────────────────────────────────────────
func _refresh_all() -> void:
	_refresh_bag()
	_refresh_equip()
	_refresh_stats(_fixed_stats())
	_refresh_level()

func _refresh_level() -> void:
	if _level_label == null:
		return
	var pm: Node = _pm()
	if pm != null and "level" in pm:
		_level_label.text = "等级  %d" % int(pm.level)

# V3.0: 面板数字写死中期档 (单一事实源 DataTables.player_loadout); 换装不改.
func _fixed_stats() -> Dictionary:
	var dt: Node = _dt()
	if dt != null and dt.has_method("get_fixed_panel_stats"):
		return dt.get_fixed_panel_stats()
	return {}

func _refresh_bag() -> void:
	var inv: Node = _inv()
	var items: Array = inv.get_bag_items() if inv != null else []
	var slots: Array = _bag_grid.get_children()
	for i in range(slots.size()):
		var b: Button = slots[i] as Button
		if b == null:
			continue
		if i < items.size() and items[i] != null:
			var it: ItemInstance = items[i]
			b.text = it.display_name
			b.disabled = false
			b.add_theme_color_override("font_color", ItemInstance.QUALITY_COLORS.get(it.quality, Color.WHITE))
		else:
			b.text = ""
			b.disabled = true
			b.remove_theme_color_override("font_color")

func _refresh_equip() -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	for s in _slot_buttons:
		var it = inv.get_equipped(s)
		var btn: Button = _slot_buttons[s]
		if it != null:
			btn.text = it.display_name
			btn.add_theme_color_override("font_color", ItemInstance.QUALITY_COLORS.get(it.quality, Color.WHITE))
		else:
			btn.text = ""
			btn.remove_theme_color_override("font_color")

func _refresh_stats(st: Dictionary) -> void:
	for sk in _stat_labels:
		var v: float = float(st.get(sk, 0.0))
		var name_txt: String = _stat_name(sk)
		var lbl: Label = _stat_labels[sk]
		# 整数属性显示整数, 其余保留一位.
		if v == floor(v):
			lbl.text = "%s: %d" % [name_txt, int(v)]
		else:
			lbl.text = "%s: %.1f" % [name_txt, v]

func _stat_name(sk: int) -> String:
	for entry in STAT_DISPLAY:
		if entry[0] == sk:
			return entry[1]
	return str(sk)
