extends CanvasLayer

# HUD(角色D 美术布局,按 D3 参考重排;数据绑定沿用系统组契约,未改信号)
#   TopLeft   : 状态/Buff 占位容器(无 buff 系统前留空)
#   TopCenter : 大秘境进度条 (RiftManager.progress_changed)
#   TopRight  : 小地图框(占位)
#   BottomLeft: 生命球 (Player.health_changed)
#   BottomRight: 资源球·复仇/专注 (FocusResource.focus_changed)
#   BottomCenter: 5 技能槽(D3 图标 + 金框 + CD 扫描遮罩 + 按键)(SkillSlotManager.cooldown_changed)
#   Bottom    : 经验条 + 等级 (ProgressionManager.xp_gained/level_up)
# 信号:ProgressionManager / FocusResource / RiftManager / Player / SkillSlotManager

const SKILL_KEY_LABELS: Array = ["LMB", "RMB", "Q", "W", "E"]
# 技能图标:从 D3 恶魔猎手图集(64px 格)按 (列,行) 取区域(对应 利箭/多重/冰霜/翻滚/箭雨)
# 只依赖一张图集 png,代码里建 AtlasTexture,避免依赖易丢的切片 .tres
const SKILL_SHEET: String = "res://assets/ui/skills/2DUI_Skills_DemonHunter.png"
const SKILL_CELL: int = 64
const SKILL_REGIONS: Array = [Vector2i(2, 0), Vector2i(5, 0), Vector2i(9, 0), Vector2i(1, 1), Vector2i(1, 2)]
const GOLD := Color(0.72, 0.56, 0.26)
const DARK := Color(0.06, 0.05, 0.04, 0.92)

var _player: Node = null
var _slot_mgr: Node = null

var _hp_fill: ColorRect = null
var _hp_label: Label = null
var _focus_fill: ColorRect = null
var _focus_label: Label = null
var _xp_label: Label = null
var _xp_bar: ProgressBar = null
var _rift_label: Label = null
var _rift_bar: ProgressBar = null
var _buff_box: HBoxContainer = null
var _slot_panels: Array = []
var _slot_cd_overlays: Array = []
var _slot_cd_labels: Array = []
var _death_overlay: ColorRect = null
var _death_label: Label = null
var _death_hint: Label = null
var _is_dead: bool = false

func _ready() -> void:
	layer = 100
	add_to_group("hud")
	_build_ui()
	_connect_signals()
	_initial_refresh()

# ── UI 构建 ───────────────────────────────────────────────────
func _build_ui() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── TopLeft: 状态/Buff 占位容器(留空,等 buff 系统)──
	_buff_box = HBoxContainer.new()
	_buff_box.position = Vector2(16, 14)
	_buff_box.add_theme_constant_override("separation", 5)
	_buff_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_buff_box)

	# ── TopCenter: 大秘境进度条 ──
	var tc: VBoxContainer = VBoxContainer.new()
	tc.anchor_left = 0.5
	tc.anchor_right = 0.5
	tc.offset_left = -180
	tc.offset_top = 12
	tc.offset_right = 180
	tc.add_theme_constant_override("separation", 2)
	tc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tc)
	_rift_label = Label.new()
	_rift_label.text = "大秘境进度  0%"
	_rift_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rift_label.add_theme_color_override("font_color", Color(0.78, 0.6, 1.0))
	_rift_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(_rift_label)
	_rift_bar = ProgressBar.new()
	_rift_bar.show_percentage = false
	_rift_bar.custom_minimum_size = Vector2(360, 12)
	_rift_bar.modulate = Color(0.65, 0.45, 1.0, 1)
	_rift_bar.max_value = 100.0
	_rift_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(_rift_bar)

	# ── TopRight: 小地图框(占位)──
	var mm: Panel = Panel.new()
	mm.anchor_left = 1.0
	mm.anchor_right = 1.0
	mm.offset_left = -150
	mm.offset_top = 12
	mm.offset_right = -14
	mm.offset_bottom = 148
	mm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mm.add_theme_stylebox_override("panel", _frame_box(Color(0.05, 0.07, 0.05, 0.85), 4))
	root.add_child(mm)
	var mm_lbl: Label = Label.new()
	mm_lbl.text = "小地图"
	mm_lbl.anchor_right = 1.0
	mm_lbl.anchor_bottom = 1.0
	mm_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mm_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mm_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	mm_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mm.add_child(mm_lbl)

	# ── BottomLeft: 生命球 ──
	_hp_fill = _make_orb(root, Vector2(0, 1), Vector2(20, -118), 96, Color(0.64, 0.10, 0.07))
	_hp_label = _make_anchored_label(root, Vector2(20, -46), Vector2(96, 18),
			"生命", Color(1, 0.92, 0.92), Vector2(0, 1))
	_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ── BottomRight: 资源球(复仇/专注)──
	_focus_fill = _make_orb(root, Vector2(1, 1), Vector2(-116, -118), 96, Color(0.16, 0.30, 0.55))
	_focus_label = _make_anchored_label(root, Vector2(-128, -46), Vector2(120, 18),
			"专注", Color(0.85, 0.92, 1), Vector2(1, 1))
	_focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# ── BottomCenter: 5 技能槽 ──
	var slots: HBoxContainer = HBoxContainer.new()
	var slot_size: float = 58.0
	var spacing: int = 6
	var total_w: float = slot_size * 5 + spacing * 4
	slots.anchor_left = 0.5
	slots.anchor_top = 1.0
	slots.anchor_right = 0.5
	slots.anchor_bottom = 1.0
	slots.offset_left = -total_w * 0.5
	slots.offset_top = -slot_size - 30
	slots.offset_right = total_w * 0.5
	slots.offset_bottom = -30
	slots.add_theme_constant_override("separation", spacing)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(slots)

	for i in range(5):
		var panel: Panel = Panel.new()
		panel.custom_minimum_size = Vector2(slot_size, slot_size)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_theme_stylebox_override("panel", _frame_box(DARK, 4))
		slots.add_child(panel)
		_slot_panels.append(panel)

		# 技能图标(最底层):从图集切区域
		var icon: TextureRect = TextureRect.new()
		if ResourceLoader.exists(SKILL_SHEET):
			var at: AtlasTexture = AtlasTexture.new()
			at.atlas = load(SKILL_SHEET)
			var rc: Vector2i = SKILL_REGIONS[i]
			at.region = Rect2(rc.x * SKILL_CELL, rc.y * SKILL_CELL, SKILL_CELL, SKILL_CELL)
			icon.texture = at
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.anchor_right = 1.0
		icon.anchor_bottom = 1.0
		icon.offset_left = 3
		icon.offset_top = 3
		icon.offset_right = -3
		icon.offset_bottom = -3
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)

		# 按键标签(右下)
		var key_lbl: Label = Label.new()
		key_lbl.text = SKILL_KEY_LABELS[i]
		key_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		key_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
		key_lbl.add_theme_constant_override("outline_size", 4)
		key_lbl.add_theme_font_size_override("font_size", 12)
		key_lbl.anchor_right = 1.0
		key_lbl.anchor_bottom = 1.0
		key_lbl.offset_left = -34
		key_lbl.offset_top = -18
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(key_lbl)

		# CD 灰蒙板(从下往上消)
		var cd_overlay: ColorRect = ColorRect.new()
		cd_overlay.color = Color(0, 0, 0, 0.7)
		cd_overlay.anchor_right = 1.0
		cd_overlay.anchor_bottom = 1.0
		cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_overlay.visible = false
		panel.add_child(cd_overlay)
		_slot_cd_overlays.append(cd_overlay)

		# CD 剩余秒数
		var cd_lbl: Label = Label.new()
		cd_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		cd_lbl.add_theme_font_size_override("font_size", 18)
		cd_lbl.anchor_right = 1.0
		cd_lbl.anchor_bottom = 1.0
		cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd_lbl.text = ""
		cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(cd_lbl)
		_slot_cd_labels.append(cd_lbl)

	# ── Bottom: 经验条 + 等级(技能栏下方)──
	var xp_box: VBoxContainer = VBoxContainer.new()
	xp_box.anchor_left = 0.5
	xp_box.anchor_top = 1.0
	xp_box.anchor_right = 0.5
	xp_box.anchor_bottom = 1.0
	xp_box.offset_left = -250
	xp_box.offset_top = -24
	xp_box.offset_right = 250
	xp_box.offset_bottom = -6
	xp_box.add_theme_constant_override("separation", 1)
	xp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(xp_box)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(500, 8)
	_xp_bar.modulate = Color(1, 0.85, 0.4, 1)
	_xp_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_box.add_child(_xp_bar)
	_xp_label = Label.new()
	_xp_label.text = "Lv 1   0/300"
	_xp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_xp_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	_xp_label.add_theme_font_size_override("font_size", 11)
	_xp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	xp_box.add_child(_xp_label)

	# ── Death Overlay ──
	_death_overlay = ColorRect.new()
	_death_overlay.color = Color(0.55, 0.05, 0.05, 0.0)
	_death_overlay.anchor_right = 1.0
	_death_overlay.anchor_bottom = 1.0
	_death_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_overlay.visible = false
	root.add_child(_death_overlay)
	_death_label = Label.new()
	_death_label.text = "你死了"
	_death_label.anchor_left = 0.5
	_death_label.anchor_top = 0.5
	_death_label.anchor_right = 0.5
	_death_label.anchor_bottom = 0.5
	_death_label.offset_left = -240
	_death_label.offset_top = -80
	_death_label.offset_right = 240
	_death_label.offset_bottom = 0
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_death_label.add_theme_color_override("font_color", Color(1, 0.2, 0.2))
	_death_label.add_theme_font_size_override("font_size", 80)
	_death_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_label.visible = false
	root.add_child(_death_label)
	_death_hint = Label.new()
	_death_hint.text = "按 R 重新开始"
	_death_hint.anchor_left = 0.5
	_death_hint.anchor_top = 0.5
	_death_hint.anchor_right = 0.5
	_death_hint.anchor_bottom = 0.5
	_death_hint.offset_left = -200
	_death_hint.offset_top = 20
	_death_hint.offset_right = 200
	_death_hint.offset_bottom = 60
	_death_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_hint.add_theme_color_override("font_color", Color(1, 0.85, 0.85))
	_death_hint.add_theme_font_size_override("font_size", 28)
	_death_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_hint.visible = false
	root.add_child(_death_hint)

# ── 工具:哥特金框 StyleBox ──
func _frame_box(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = GOLD
	sb.set_corner_radius_all(radius)
	return sb

# ── 工具:圆形球体(返回 fill ColorRect,refresh 时改 anchor_top)──
func _make_orb(parent: Node, anchor_xy: Vector2, off: Vector2, diam: float, fill_color: Color) -> ColorRect:
	var orb: Panel = Panel.new()
	orb.anchor_left = anchor_xy.x
	orb.anchor_top = anchor_xy.y
	orb.anchor_right = anchor_xy.x
	orb.anchor_bottom = anchor_xy.y
	orb.offset_left = off.x
	orb.offset_top = off.y
	orb.offset_right = off.x + diam
	orb.offset_bottom = off.y + diam
	orb.clip_contents = true
	orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.add_theme_stylebox_override("panel", _frame_box(Color(0.04, 0.04, 0.05, 0.95), int(diam / 2)))
	parent.add_child(orb)
	var fill: ColorRect = ColorRect.new()
	fill.color = fill_color
	fill.anchor_left = 0.0
	fill.anchor_top = 0.5
	fill.anchor_right = 1.0
	fill.anchor_bottom = 1.0
	fill.offset_top = 0.0
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	orb.add_child(fill)
	return fill

# anchor_xy: Vector2(left_anchor, top_anchor) ∈ {0,1}
func _make_anchored_label(parent: Node, off: Vector2, size: Vector2,
		text: String, color: Color, anchor_xy: Vector2) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.anchor_left = anchor_xy.x
	lbl.anchor_top = anchor_xy.y
	lbl.anchor_right = anchor_xy.x
	lbl.anchor_bottom = anchor_xy.y
	lbl.offset_left = off.x
	lbl.offset_top = off.y
	lbl.offset_right = off.x + size.x
	lbl.offset_bottom = off.y + size.y
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)
	return lbl

# ── 信号连接(沿用系统组契约,未改)──────────────────────
func _connect_signals() -> void:
	var pm: Node = get_node_or_null("/root/ProgressionManager")
	if pm != null:
		if pm.has_signal("xp_gained"):
			pm.xp_gained.connect(_on_xp_gained)
		if pm.has_signal("level_up"):
			pm.level_up.connect(_on_level_up)
	var fr: Node = get_node_or_null("/root/FocusResource")
	if fr != null and fr.has_signal("focus_changed"):
		fr.focus_changed.connect(_on_focus_changed)
	var rm: Node = get_node_or_null("/root/RiftManager")
	if rm != null and rm.has_signal("progress_changed"):
		rm.progress_changed.connect(_on_rift_progress)
	call_deferred("_acquire_player")

func _acquire_player() -> void:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.size() == 0:
		await get_tree().process_frame
		arr = get_tree().get_nodes_in_group("player")
	if arr.size() == 0:
		return
	_player = arr[0]
	if _player.has_signal("health_changed"):
		_player.health_changed.connect(_on_health_changed)
	if _player.has_signal("player_died"):
		_player.player_died.connect(_on_player_died)
	for c in _player.get_children():
		if c.has_signal("cooldown_changed"):
			_slot_mgr = c
			break
	if _slot_mgr != null:
		_slot_mgr.cooldown_changed.connect(_on_cooldown_changed)
	_initial_refresh()

func _initial_refresh() -> void:
	var pm: Node = get_node_or_null("/root/ProgressionManager")
	if pm != null and "level" in pm and "current_xp" in pm:
		var to_next: int = 300
		if pm.has_method("_xp_to_next"):
			to_next = int(pm._xp_to_next())
		_refresh_xp(int(pm.current_xp), to_next, int(pm.level))
	var fr: Node = get_node_or_null("/root/FocusResource")
	if fr != null and "current" in fr and "max_focus" in fr:
		_on_focus_changed(float(fr.current), float(fr.max_focus))
	var rm: Node = get_node_or_null("/root/RiftManager")
	if rm != null and "progress" in rm:
		_on_rift_progress(float(rm.progress), float(rm.GOAL))
	if _player != null and "current_health" in _player and "max_health" in _player:
		_on_health_changed(int(_player.current_health), int(_player.max_health))

# ── 信号回调 ──────────────────────────────────────────────
func _on_xp_gained(current_xp: int, xp_to_next: int, lvl: int) -> void:
	_refresh_xp(current_xp, xp_to_next, lvl)

func _on_level_up(new_level: int, _unlocked) -> void:
	var pm: Node = get_node_or_null("/root/ProgressionManager")
	if pm == null:
		return
	var to_next: int = 300
	if pm.has_method("_xp_to_next"):
		to_next = int(pm._xp_to_next())
	var cur: int = int(pm.current_xp) if "current_xp" in pm else 0
	_refresh_xp(cur, to_next, new_level)

func _refresh_xp(current_xp: int, xp_to_next: int, lvl: int) -> void:
	if _xp_label == null:
		return
	_xp_label.text = "Lv %d   %d/%d" % [lvl, current_xp, xp_to_next]
	if _xp_bar != null:
		_xp_bar.max_value = max(xp_to_next, 1)
		_xp_bar.value = current_xp

func _on_rift_progress(value: float, goal: float) -> void:
	if _rift_bar == null:
		return
	_rift_bar.max_value = maxf(goal, 1.0)
	_rift_bar.value = value
	var pct: int = int(clampf(value / maxf(goal, 1.0), 0.0, 1.0) * 100.0)
	if _rift_label != null:
		_rift_label.text = "守门人降临!" if value >= goal else "大秘境进度  %d%%" % pct

func _on_focus_changed(cur: float, max_focus: float) -> void:
	if _focus_fill == null:
		return
	var ratio: float = clampf(cur / maxf(max_focus, 1.0), 0.0, 1.0)
	_focus_fill.anchor_top = 1.0 - ratio
	_focus_fill.offset_top = 0.0
	_focus_label.text = "专注 %d/%d" % [int(cur), int(max_focus)]

func _on_health_changed(cur: int, mx: int) -> void:
	if _hp_fill == null:
		return
	var ratio: float = clampf(float(cur) / float(max(mx, 1)), 0.0, 1.0)
	_hp_fill.anchor_top = 1.0 - ratio
	_hp_fill.offset_top = 0.0
	_hp_label.text = "生命 %d" % cur

func _on_cooldown_changed(slot_index: int, remaining: float, total: float) -> void:
	if slot_index < 0 or slot_index >= _slot_cd_overlays.size():
		return
	var overlay: ColorRect = _slot_cd_overlays[slot_index]
	var label: Label = _slot_cd_labels[slot_index]
	if remaining <= 0.01:
		overlay.visible = false
		label.text = ""
	else:
		overlay.visible = true
		var ratio: float = clamp(remaining / max(total, 0.01), 0.0, 1.0)
		overlay.anchor_top = 1.0 - ratio
		overlay.offset_top = 0.0
		label.text = "%.1f" % remaining

# ── 死亡演出 / R 重开 ─────────────────────────────────────
func _on_player_died() -> void:
	if _is_dead:
		return
	_is_dead = true
	if _death_overlay == null:
		return
	_death_overlay.visible = true
	_death_label.visible = true
	_death_hint.visible = true
	var tw: Tween = create_tween()
	tw.tween_property(_death_overlay, "color:a", 0.55, 0.5)

func boss_killed_flash() -> void:
	var root: Control = get_node_or_null("Root")
	if root == null:
		return
	var flash: ColorRect = ColorRect.new()
	flash.color = Color(1, 1, 1, 0.85)
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash)
	var tw: Tween = create_tween()
	tw.tween_property(flash, "color:a", 0.0, 0.6)
	tw.tween_callback(Callable(flash, "queue_free"))

func _process(_delta: float) -> void:
	if _is_dead and Input.is_key_pressed(KEY_R):
		_is_dead = false
		get_tree().reload_current_scene()
