extends CanvasLayer

# 任务4 背包+装备面板 (简版,美术 D 后期重做):
#   左: 40 格背包网格 (点击 = quick_equip 自动装备)
#   右: 13 装备槽列表 (点击 = 卸下回背包)
#   下: 主属性聚合 (敏捷/体能 + 词缀加成), 监听 Inventory.stats_changed 实时刷新
#
# 完全程序化生成 Control 树, 与 hud.gd 同风格。
# 开关: toggle_inventory 动作 (默认 B 键; 缺省时 _unhandled_key_input 兜底 KEY_B)。

const COLS: int = 8
const ROWS: int = 5   # 8*5 = 40

# 参与面板展示的属性顺序与中文名.
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

var _root: Control = null
var _bag_grid: GridContainer = null
var _slot_buttons: Dictionary = {}   # EquipSlots.Slot -> Button
var _stat_labels: Dictionary = {}    # StatKind -> Label
var _open: bool = false

func _ready() -> void:
	layer = 110   # 盖在 HUD(100) 之上
	add_to_group("inventory_panel")
	_build_ui()
	_connect_signals()
	_set_open(false)
	_refresh_all()

# ── UI 构建 ───────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)

	# 半透明遮罩.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
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
	panel.offset_left = -440
	panel.offset_top = -260
	panel.offset_right = 440
	panel.offset_bottom = 260
	_root.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	panel.add_child(hbox)

	# ── 左: 背包 40 格 ─────────────────────────────────
	var bag_box := VBoxContainer.new()
	hbox.add_child(bag_box)
	var bag_title := Label.new()
	bag_title.text = "背包 (40)"
	bag_box.add_child(bag_title)

	_bag_grid = GridContainer.new()
	_bag_grid.columns = COLS
	_bag_grid.add_theme_constant_override("h_separation", 4)
	_bag_grid.add_theme_constant_override("v_separation", 4)
	bag_box.add_child(_bag_grid)
	# 预建 40 个格子按钮.
	for i in range(COLS * ROWS):
		var b := Button.new()
		b.custom_minimum_size = Vector2(56, 56)
		b.clip_text = true
		b.pressed.connect(_on_bag_slot_pressed.bind(i))
		_bag_grid.add_child(b)

	# ── 右: 13 装备槽 + 属性 ───────────────────────────
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 6)
	hbox.add_child(right)

	var equip_title := Label.new()
	equip_title.text = "装备 (点击卸下)"
	right.add_child(equip_title)

	for s in range(EquipSlots.SLOT_COUNT):
		var row := HBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = "%s:" % str(EquipSlots.SLOT_DISPLAY.get(s, "?"))
		name_lbl.custom_minimum_size = Vector2(64, 0)
		row.add_child(name_lbl)
		var sb := Button.new()
		sb.custom_minimum_size = Vector2(220, 26)
		sb.clip_text = true
		sb.text = "[空]"
		sb.pressed.connect(_on_equip_slot_pressed.bind(s))
		row.add_child(sb)
		_slot_buttons[s] = sb
		right.add_child(row)

	# 属性区.
	var sep := HSeparator.new()
	right.add_child(sep)
	var stat_title := Label.new()
	stat_title.text = "角色属性"
	right.add_child(stat_title)
	for entry in STAT_DISPLAY:
		var sk: int = entry[0]
		var lbl := Label.new()
		lbl.text = "%s: 0" % entry[1]
		right.add_child(lbl)
		_stat_labels[sk] = lbl

	# 关闭提示.
	var hint := Label.new()
	hint.text = "[ B ] 关闭"
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	right.add_child(hint)

func _connect_signals() -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	if inv.has_signal("item_picked_up"):
		inv.item_picked_up.connect(func(_i): _refresh_bag())
	# V3.0: 换装只刷新背包/装备槽视觉, 不重算面板属性 (面板写死中期档).
	if inv.has_signal("item_equipped"):
		inv.item_equipped.connect(func(_s, _i): _refresh_bag(); _refresh_equip())
	if inv.has_signal("item_unequipped"):
		inv.item_unequipped.connect(func(_s, _i): _refresh_bag(); _refresh_equip())

func _dt() -> Node:
	return get_node_or_null("/root/DataTables")

func _inv() -> Node:
	return get_node_or_null("/root/Inventory")

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
	# 信号会触发 _refresh_all; 这里无需手动刷.

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
			btn.text = "[空]"
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
