extends CanvasLayer

# 任务4 背包+装备面板 — 视觉按 D3《物品栏》参考重排 (美术 D)。
#   布局: 左=主属性栏 | 中=纸娃娃(立绘+13 装备槽) | 下=背包网格 | 底=资源占位栏
#   数据源全部沿用系统组接口, 仅重排视觉 + 加占位格 (PNG 由美术后替换):
#     - Inventory: get_bag_items / quick_equip / get_equipped / unequip + item_* 信号
#     - DataTables.get_fixed_panel_stats() (面板属性, 单一事实源)
#     - ProgressionManager.level (角色等级, 只读)
#   开关: toggle_inventory 动作 (默认 I; 缺省兜底 KEY_I)。
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

# 槽位 -> 装备图标 PNG (娜塔亚素材当视觉皮肤; 数据走配置表, 与 ItemInstance 解耦).
# 装备槽/背包格按 item.slot 查这里取图标, 不给 ItemInstance 加字段。
const SLOT_ICON: Dictionary = {
	EquipSlots.Slot.HEAD: "res://assets/ui/items/head.png",
	EquipSlots.Slot.SHOULDER: "res://assets/ui/items/shoulder.png",
	EquipSlots.Slot.CHEST: "res://assets/ui/items/chest.png",
	EquipSlots.Slot.WRIST: "res://assets/ui/items/wrist.png",
	EquipSlots.Slot.GLOVES: "res://assets/ui/items/gloves.png",
	EquipSlots.Slot.WAIST: "res://assets/ui/items/waist.png",
	EquipSlots.Slot.LEGS: "res://assets/ui/items/legs.png",
	EquipSlots.Slot.BOOTS: "res://assets/ui/items/boots.png",
	EquipSlots.Slot.AMULET: "res://assets/ui/items/amulet.png",
	EquipSlots.Slot.RING_1: "res://assets/ui/items/ring1.png",
	EquipSlots.Slot.RING_2: "res://assets/ui/items/ring2.png",
	EquipSlots.Slot.BOW: "res://assets/ui/items/bow.png",
	EquipSlots.Slot.QUIVER: "res://assets/ui/items/quiver.png",
}

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

# tooltip 浮层 (自建富文本; hover 即弹, 离开即隐).
var _tooltip: PanelContainer = null
var _tip_box: VBoxContainer = null
var _tip_border := StyleBoxFlat.new()

# 词缀 stat_kind -> 中文名 (与 STAT_DISPLAY 同源, 供 tooltip 词缀行用).
const AFFIX_NAMES: Dictionary = {
	AffixDef.StatKind.AGILITY: "敏捷",
	AffixDef.StatKind.CRIT_CHANCE: "暴击率",
	AffixDef.StatKind.CRIT_DAMAGE: "暴击伤害",
	AffixDef.StatKind.ATTACK_SPEED: "攻击速度",
	AffixDef.StatKind.WEAPON_DAMAGE: "武器伤害",
	AffixDef.StatKind.SKILL_DAMAGE: "技能伤害",
	AffixDef.StatKind.VITALITY: "体能",
	AffixDef.StatKind.ARMOR: "护甲",
	AffixDef.StatKind.ALL_RESIST: "全抗性",
	AffixDef.StatKind.MOVE_SPEED: "移动速度",
}

# ── 节点引用 (来自 inventory_panel.tscn; 架构对齐 hud.tscn: 视觉在 tscn, 脚本只数据绑定) ──
@onready var _bg: TextureRect = $Root/Bg
@onready var _stats_box: VBoxContainer = $Root/Bg/Stats
@onready var _close_btn: Button = $Root/Bg/CloseBtn

func _ready() -> void:
	layer = 110   # 盖在 HUD(100) 之上
	add_to_group("inventory_panel")
	_root = $Root
	_bag_grid = $Root/Bg/BagGrid
	_tooltip = $Root/Tooltip
	_tip_box = $Root/Tooltip/TipBox
	_level_label = $Root/Bg/Stats/LevelLabel
	_collect_slots()
	_collect_stat_labels()
	_build_bag_cells()
	_close_btn.pressed.connect(func(): Sfx.play("ui_decline"); _set_open(false))
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

# ── 收集 tscn 节点引用 (替代旧的代码生成; 视觉布局在 inventory_panel.tscn) ──────
# 装备槽: $Root/Bg/Slots 下的 Slot<枚举名> Button, 按 EquipSlots.Slot 名匹配填 _slot_buttons.
func _collect_slots() -> void:
	var slots_node: Node = $Root/Bg/Slots
	for slot_id in EquipSlots.Slot.values():
		var key: String = EquipSlots.Slot.keys()[slot_id]
		var btn: Button = slots_node.get_node_or_null("Slot%s" % key)
		if btn == null:
			continue
		btn.pressed.connect(_on_equip_slot_pressed.bind(slot_id))
		_slot_buttons[slot_id] = btn

# 属性行: $Root/Bg/Stats 下的 Stat<StatKind名> Label, 按枚举名匹配填 _stat_labels.
func _collect_stat_labels() -> void:
	for entry in STAT_DISPLAY:
		var sk: int = entry[0]
		var key: String = AffixDef.StatKind.keys()[sk]
		var lbl: Label = _stats_box.get_node_or_null("Stat%s" % key)
		if lbl != null:
			_stat_labels[sk] = lbl

# 背包格: 运行时往 tscn 的 BagGrid 建满 40 格 (重复格子代码生成, 布局容器在 tscn).
func _build_bag_cells() -> void:
	for i in range(COLS * ROWS):
		var b := Button.new()
		b.flat = true
		b.expand_icon = true
		b.custom_minimum_size = Vector2(28, 28)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_bag_slot_pressed.bind(i))
		_bag_grid.add_child(b)

func _tip_label(txt: String, col: Color, sz: int, center: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_color_override("font_color", col)
	l.add_theme_font_size_override("font_size", sz)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

# 一条词缀的展示文本: "+12% 暴击伤害" / "+340 护甲".
func _affix_line(a: Dictionary) -> String:
	var sk: int = int(a.get("stat_kind", -1))
	var val: float = float(a.get("value", 0.0))
	var pct: bool = bool(a.get("is_percent", false))
	var nm: String = String(AFFIX_NAMES.get(sk, "属性"))
	var num: String
	if pct:
		num = "+%.0f%%" % val if val == floor(val) else "+%.1f%%" % val
	else:
		num = "+%d" % int(round(val)) if val == floor(val) else "+%.1f" % val
	return "%s %s" % [num, nm]

func _show_tooltip_for_item(item: ItemInstance, anchor: Control) -> void:
	if item == null or _tooltip == null:
		return
	# 清旧内容.
	for c in _tip_box.get_children():
		c.queue_free()

	var qcol: Color = item.display_color()   # 套装绿优先, 否则品质色

	# 标题 = 物品名 (品质/套装色).
	_tip_box.add_child(_tip_label(item.display_name, qcol, 15, true))

	# 副标题: 品质名 + 槽位名 + 物品等级.
	var quality_name: String = String(ItemInstance.QUALITY_NAMES.get(item.quality, ""))
	var slot_name: String = String(EquipSlots.SLOT_DISPLAY.get(item.slot, ""))
	var sub: String = "%s %s · iLvl %d" % [quality_name, slot_name, item.item_level]
	_tip_box.add_child(_tip_label(sub.strip_edges(), MUTED, 10, true))

	# 套装标记 (绿).
	if item.is_set:
		_tip_box.add_child(_tip_label("【套装】", ItemInstance.SET_COLOR, 11, true))

	# 词缀行.
	if item.affixes != null and item.affixes.size() > 0:
		var rule := Panel.new()
		rule.custom_minimum_size = Vector2(0, 1)
		var rs := StyleBoxFlat.new()
		rs.bg_color = GOLD_DIM
		rule.add_theme_stylebox_override("panel", rs)
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_box.add_child(rule)
		for a in item.affixes:
			_tip_box.add_child(_tip_label(_affix_line(a), Color(0.55, 0.7, 1.0), 12))

	# 传说效果 (橙字).
	if item.is_legendary() and item.legendary_effect_text != "":
		var rule2 := Panel.new()
		rule2.custom_minimum_size = Vector2(0, 1)
		var rs2 := StyleBoxFlat.new()
		rs2.bg_color = GOLD_DIM
		rule2.add_theme_stylebox_override("panel", rs2)
		rule2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tip_box.add_child(rule2)
		_tip_box.add_child(_tip_label(item.legendary_effect_text, ItemInstance.QUALITY_COLORS[ItemInstance.Quality.LEGENDARY], 11))

	# 边框色: 套装=绿, 传说=橙, 其余=品质色.
	_tip_border = _sbox(Color(0.06, 0.05, 0.04, 0.98), 2, qcol, 4, 10)
	_tooltip.add_theme_stylebox_override("panel", _tip_border)

	_tooltip.visible = true
	_tooltip.reset_size()
	_position_tooltip(anchor)

# tooltip 放在锚点右侧; 越界则翻到左侧 / 上移, 始终留在视口内.
func _position_tooltip(anchor: Control) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var tip_size: Vector2 = _tooltip.size
	var arect: Rect2 = anchor.get_global_rect()
	var pos := Vector2(arect.position.x + arect.size.x + 8.0, arect.position.y)
	# 右侧放不下 -> 翻到锚点左边.
	if pos.x + tip_size.x > vp.x:
		pos.x = arect.position.x - tip_size.x - 8.0
	pos.x = clampf(pos.x, 4.0, max(4.0, vp.x - tip_size.x - 4.0))
	pos.y = clampf(pos.y, 4.0, max(4.0, vp.y - tip_size.y - 4.0))
	_tooltip.global_position = pos

func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false

# 空槽轻提示: 槽位名 + "未装备".
func _show_empty_tooltip(slot_name: String, anchor: Control) -> void:
	if _tooltip == null:
		return
	for c in _tip_box.get_children():
		c.queue_free()
	_tip_box.add_child(_tip_label(slot_name, MUTED, 13, true))
	_tip_box.add_child(_tip_label("未装备", MUTED, 11, true))
	_tip_border = _sbox(Color(0.06, 0.05, 0.04, 0.98), 2, GOLD_DIM, 4, 10)
	_tooltip.add_theme_stylebox_override("panel", _tip_border)
	_tooltip.visible = true
	_tooltip.reset_size()
	_position_tooltip(anchor)

# hover 处理: 装备槽 -> 取已装备件; 背包格 -> 取背包件.
func _on_equip_hover(slot: int, btn: Button) -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	var it = inv.get_equipped(slot)
	if it != null:
		_show_tooltip_for_item(it, btn)
	else:
		# 空槽: 仍弹一个轻提示, 让 hover 行为一致可发现.
		_show_empty_tooltip(String(EquipSlots.SLOT_DISPLAY.get(slot, "")), btn)

func _on_bag_hover(index: int, btn: Button) -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	var items: Array = inv.get_bag_items()
	if index >= 0 and index < items.size() and items[index] != null:
		_show_tooltip_for_item(items[index], btn)

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
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_I:
		toggled = true
	if toggled:
		_set_open(not _open)
		Sfx.play("ui_pause" if _open else "ui_unpause")
		get_viewport().set_input_as_handled()

func _set_open(v: bool) -> void:
	_open = v
	_root.visible = v
	if v:
		_refresh_all()
	else:
		_hide_tooltip()

# ── 交互 ──────────────────────────────────────────────────────
# 点背包格子 -> 若有物品则 quick_equip 自动装备.
func _on_bag_slot_pressed(index: int) -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	var items: Array = inv.get_bag_items()
	if index < 0 or index >= items.size():
		Sfx.play("ui_denied")
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
			# 背包物品 -> 按 item.slot 查 SLOT_ICON 显图标 (装备类); 无图标则退回文字名.
			var it: ItemInstance = items[i]
			var icon_path: String = String(SLOT_ICON.get(it.slot, ""))
			if icon_path != "":
				b.icon = load(icon_path) as Texture2D
				b.text = ""
			else:
				b.icon = null
				b.text = it.display_name
				b.add_theme_color_override("font_color", ItemInstance.QUALITY_COLORS.get(it.quality, Color.WHITE))
		else:
			b.text = ""
			b.icon = null
			b.remove_theme_color_override("font_color")

func _refresh_equip() -> void:
	var inv: Node = _inv()
	if inv == null:
		return
	for s in _slot_buttons:
		var it = inv.get_equipped(s)
		var btn: Button = _slot_buttons[s]
		if it != null:
			# 装上 -> 显示该槽位的装备图标 (皮肤); 文字名清空 (改由 hover tooltip 展示).
			btn.text = ""
			var icon_path: String = String(SLOT_ICON.get(s, ""))
			btn.icon = (load(icon_path) as Texture2D) if icon_path != "" else null
			btn.remove_theme_color_override("font_color")
		else:
			# 空槽 -> 无图标无文字.
			btn.text = ""
			btn.icon = null
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
