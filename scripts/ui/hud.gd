extends CanvasLayer

# 简版 HUD(占位,美术 D 后期重做):
#   TopLeft   : Lv X + XP 条
#   BottomLeft: HP 红条 (current/max)
#   BottomCtr : 5 技能槽 + CD 灰蒙板 + 剩余秒数
#   BottomRight: Focus 蓝条 (current/max)
#
# 完全由脚本程序化生成 Control 树,不依赖具体 tscn 节点结构。
# 监听:ProgressionManager.{xp_gained,level_up}, FocusResource.focus_changed,
#       Player.health_changed, SkillSlotManager.cooldown_changed

const SKILL_KEY_LABELS: Array = ["LMB", "RMB", "Q", "W", "E"]

var _player: Node = null
var _slot_mgr: Node = null

var _hp_label: Label = null
var _hp_bar: ProgressBar = null
var _focus_label: Label = null
var _focus_bar: ProgressBar = null
var _xp_label: Label = null
var _xp_bar: ProgressBar = null
var _rift_label: Label = null
var _rift_bar: ProgressBar = null
var _slot_panels: Array = []
var _slot_cd_overlays: Array = []
var _slot_cd_labels: Array = []
var _death_overlay: ColorRect = null
var _death_label: Label = null
var _death_hint: Label = null
var _is_dead: bool = false

const MinimapPanel := preload("res://scripts/ui/minimap_panel.gd")

func _ready() -> void:
	layer = 100
	add_to_group("hud")
	_build_ui()
	_connect_signals()
	_initial_refresh()
	# 常驻小地图（独立 CanvasLayer layer=105，挂到场景根）
	var minimap := MinimapPanel.new()
	get_tree().root.call_deferred("add_child", minimap)

# ── UI 构建 ───────────────────────────────────────────────────
func _build_ui() -> void:
	var root: Control = Control.new()
	root.name = "Root"
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# ── TopLeft: 等级 + XP ─────────────────────────────
	var tl: VBoxContainer = VBoxContainer.new()
	tl.position = Vector2(16, 16)
	tl.custom_minimum_size = Vector2(220, 40)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tl)

	_xp_label = Label.new()
	_xp_label.text = "Lv 1   0/300"
	_xp_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	tl.add_child(_xp_label)

	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.custom_minimum_size = Vector2(220, 8)
	_xp_bar.modulate = Color(1, 0.85, 0.4, 1)
	tl.add_child(_xp_bar)

	# ── TopCenter: 大秘境进度条 (RiftManager) ──────────
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
	_rift_label.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	_rift_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(_rift_label)

	_rift_bar = ProgressBar.new()
	_rift_bar.show_percentage = false
	_rift_bar.custom_minimum_size = Vector2(360, 12)
	_rift_bar.modulate = Color(0.65, 0.45, 1.0, 1)
	_rift_bar.max_value = 100.0
	_rift_bar.value = 0.0
	_rift_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tc.add_child(_rift_bar)

	# ── BottomLeft: HP ─────────────────────────────────
	_hp_label = _make_anchored_label(root, Vector2(16, -82), Vector2(220, 22),
			"HP", Color(1, 1, 1), Vector2(0, 1))
	_hp_bar = _make_anchored_bar(root, Vector2(16, -56), Vector2(220, 22),
			Color(0.95, 0.2, 0.2), Vector2(0, 1))

	# ── BottomRight: Focus ─────────────────────────────
	_focus_label = _make_anchored_label(root, Vector2(-236, -82), Vector2(220, 22),
			"Focus", Color(0.7, 0.85, 1), Vector2(1, 1))
	_focus_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_focus_bar = _make_anchored_bar(root, Vector2(-236, -56), Vector2(220, 22),
			Color(0.3, 0.5, 1.0), Vector2(1, 1))

	# ── BottomCenter: 5 个技能槽 ────────────────────────
	var slots: HBoxContainer = HBoxContainer.new()
	var slot_size: float = 56.0
	var spacing: int = 6
	var total_w: float = slot_size * 5 + spacing * 4
	slots.anchor_left = 0.5
	slots.anchor_top = 1.0
	slots.anchor_right = 0.5
	slots.anchor_bottom = 1.0
	slots.offset_left = -total_w * 0.5
	slots.offset_top = -slot_size - 16
	slots.offset_right = total_w * 0.5
	slots.offset_bottom = -16
	slots.add_theme_constant_override("separation", spacing)
	slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(slots)

	for i in range(5):
		var panel: Panel = Panel.new()
		panel.custom_minimum_size = Vector2(slot_size, slot_size)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slots.add_child(panel)
		_slot_panels.append(panel)

		# 按键标签(右下)
		var key_lbl: Label = Label.new()
		key_lbl.text = SKILL_KEY_LABELS[i]
		key_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		key_lbl.add_theme_font_size_override("font_size", 12)
		key_lbl.anchor_right = 1.0
		key_lbl.anchor_bottom = 1.0
		key_lbl.offset_left = -32
		key_lbl.offset_top = -18
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(key_lbl)

		# CD 灰蒙板 — 从下往上消(anchor_top 动态)
		var cd_overlay: ColorRect = ColorRect.new()
		cd_overlay.color = Color(0, 0, 0, 0.7)
		cd_overlay.anchor_right = 1.0
		cd_overlay.anchor_bottom = 1.0
		cd_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cd_overlay.visible = false
		panel.add_child(cd_overlay)
		_slot_cd_overlays.append(cd_overlay)

		# CD 剩余秒数(中央)
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

	# ── Death Overlay(红屏 + 大字)─────────────────────
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

# ── 锚定工具函数(anchor 设到 0 或 1,offset 是负数表示从右/下边贴边)
# anchor_xy: Vector2(left_anchor, top_anchor) ∈ {0, 1}
func _make_anchored_label(parent: Node, off: Vector2, size: Vector2,
		text: String, color: Color, anchor_xy: Vector2) -> Label:
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
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

func _make_anchored_bar(parent: Node, off: Vector2, size: Vector2,
		color: Color, anchor_xy: Vector2) -> ProgressBar:
	var bar: ProgressBar = ProgressBar.new()
	bar.show_percentage = false
	bar.modulate = color
	bar.anchor_left = anchor_xy.x
	bar.anchor_top = anchor_xy.y
	bar.anchor_right = anchor_xy.x
	bar.anchor_bottom = anchor_xy.y
	bar.offset_left = off.x
	bar.offset_top = off.y
	bar.offset_right = off.x + size.x
	bar.offset_bottom = off.y + size.y
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar

# ── 信号连接 ──────────────────────────────────────────────
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
	# Skill slot manager — 战斗组挂在 Player 子节点
	for c in _player.get_children():
		if c.has_signal("cooldown_changed"):
			_slot_mgr = c
			break
	if _slot_mgr != null:
		_slot_mgr.cooldown_changed.connect(_on_cooldown_changed)
	_initial_refresh()

# ── 首次刷新(信号连上之前已经发生的状态)──────────────
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
		if value >= goal:
			_rift_label.text = "守门人降临!"
		else:
			_rift_label.text = "大秘境进度  %d%%" % pct

func _on_focus_changed(cur: float, max_focus: float) -> void:
	if _focus_bar == null:
		return
	_focus_bar.max_value = max(max_focus, 1.0)
	_focus_bar.value = cur
	_focus_label.text = "Focus  %d/%d" % [int(cur), int(max_focus)]

func _on_health_changed(cur: int, mx: int) -> void:
	if _hp_bar == null:
		return
	_hp_bar.max_value = max(mx, 1)
	_hp_bar.value = cur
	_hp_label.text = "HP  %d/%d" % [cur, mx]

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
		# 蒙板从下往上消:anchor_top 越接近 1,蒙板越小
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

# Boss 死亡演出:全屏短暂白闪(由 butcher.gd 调用)
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
