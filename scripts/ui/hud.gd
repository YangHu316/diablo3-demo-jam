extends CanvasLayer

# HUD —— 视觉布局已外置到 hud.tscn 节点树(美术可在编辑器里直接对各节点拖 PNG 换素材),
# 本脚本只负责"引用节点 + 数据绑定 + 动态特效",逻辑/信号契约未改。
#   节点树(hud.tscn):Root/{BuffBox, RiftBox, TimeOrb, LifeOrb+LifeLabel,
#     FocusOrb+FocusLabel, Skills/Slot0..4{Icon,KeyBg,Cd,CdLabel}, XpBox, Death*}
#   换素材落点:Slot*/Icon(技能图标 AtlasTexture)、各 *Orb 的 Panel(可换 StyleBoxTexture/
#     塞 TextureRect)、各 Bar、BuffBox。改外观不用动这个脚本。
#   数据源:ProgressionManager / FocusResource / RiftManager / Player / SkillSlotManager / TowerBuffManager

const MinimapPanel := preload("res://scripts/ui/minimap_panel.gd")
const TabMap := preload("res://scripts/ui/tab_map.gd")

var _player: Node = null
var _slot_mgr: Node = null

# ── 节点引用(对应 hud.tscn 里的节点;美术换素材改的是这些节点本身)──
@onready var _buff_box: HBoxContainer = $Root/BuffBox
@onready var _rift_label: Label = $Root/RiftBox/RiftLabel
@onready var _rift_bar: ProgressBar = $Root/RiftBox/RiftBar
@onready var _time_orb_fill: ColorRect = $Root/TimeOrb/Fill
@onready var _time_orb_label: Label = $Root/TimeOrb/TimeLabel
@onready var _hp_fill: Control = $Root/LifeOrb/OrbClip
@onready var _hp_label: Label = $Root/LifeOrb/LifeLabel
@onready var _focus_fill: Control = $Root/FocusOrb/OrbClip
@onready var _focus_label: Label = $Root/FocusOrb/FocusLabel
@onready var _xp_bar: ProgressBar = $Root/XpBox/XpBar
@onready var _xp_label: Label = $Root/XpBox/XpLabel
@onready var _death_overlay: ColorRect = $Root/DeathOverlay
@onready var _death_label: Label = $Root/DeathLabel
@onready var _death_hint: Label = $Root/DeathHint

var _time_orb_accum: float = 0.0
# 功能塔 buff 图标(运行时按需建,挂在 BuffBox 下)
var _tower_buff_panel: Panel = null
var _tower_buff_fill: ColorRect = null
var _tower_buff_label: Label = null
# 5 技能槽(_ready 时从 hud.tscn 收集)
var _slot_panels: Array = []
var _slot_cd_overlays: Array = []
var _slot_cd_labels: Array = []
var _is_dead: bool = false
var _hp_tween: Tween = null
var _focus_tween: Tween = null

# F3 调试 FPS 面板(代码创建,非美术素材;合并自远端 perf 提交)
var _debug_label: Label = null
var _debug_visible: bool = false

func _ready() -> void:
	layer = 100
	add_to_group("hud")
	_collect_slots()
	_build_debug_label()
	_connect_signals()
	_initial_refresh()
	# 常驻小地图 / Tab 大地图(独立 CanvasLayer,挂到场景根)
	# 重载场景时 minimap/tab_map 挂在 root 下不会自动销毁，需先清理旧实例再创建新的，防止叠加
	for node in get_tree().root.get_children():
		if is_instance_valid(node) and node.get_script() != null:
			var sp: String = str(node.get_script().resource_path)
			if "minimap_panel" in sp or "tab_map" in sp:
				node.queue_free()
	var minimap := MinimapPanel.new()
	get_tree().root.call_deferred("add_child", minimap)
	var tab_map := TabMap.new()
	get_tree().root.call_deferred("add_child", tab_map)

# F3 调试标签(挂 Root 左上,默认隐藏)
func _build_debug_label() -> void:
	var root: Node = get_node_or_null("Root")
	if root == null:
		return
	_debug_label = Label.new()
	_debug_label.add_theme_font_size_override("font_size", 14)
	_debug_label.add_theme_color_override("font_color", Color(0.0, 1.0, 0.4))
	_debug_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_debug_label.add_theme_constant_override("outline_size", 3)
	_debug_label.offset_left = 8
	_debug_label.offset_top = 8
	_debug_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_label.visible = false
	root.add_child(_debug_label)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_debug_visible = not _debug_visible
			if _debug_label != null:
				_debug_label.visible = _debug_visible
			get_viewport().set_input_as_handled()

# 从 hud.tscn 的 Skills 容器收集 5 个技能槽的 CD 蒙板/文字引用.
func _collect_slots() -> void:
	var skills: Node = $Root/Skills
	if skills == null:
		return
	for i in range(5):
		var slot: Node = skills.get_node_or_null("Slot%d" % i)
		if slot == null:
			continue
		_slot_panels.append(slot)
		_slot_cd_overlays.append(slot.get_node("Cd"))
		_slot_cd_labels.append(slot.get_node("CdLabel"))

# 读 RiftManager 剩余时间, 刷新时间球填充高度与 MM:SS 文字.
func _refresh_time_orb() -> void:
	if _time_orb_fill == null:
		return
	var rm: Node = get_node_or_null("/root/RiftManager")
	if rm == null or not rm.has_method("get_time_remaining"):
		return
	var remaining: float = float(rm.get_time_remaining())
	var limit: float = float(rm.get_time_limit()) if rm.has_method("get_time_limit") else 120.0
	var ratio: float = clampf(remaining / maxf(limit, 1.0), 0.0, 1.0)
	_time_orb_fill.anchor_top = 1.0 - ratio
	_time_orb_fill.offset_top = 0.0
	# 时间紧迫(<20%)转红, 提示玩家.
	_time_orb_fill.color = Color(0.85, 0.20, 0.20, 0.92) if ratio < 0.2 else Color(0.62, 0.42, 1.0, 0.92)
	if _time_orb_label != null:
		var secs: int = int(ceil(remaining))
		_time_orb_label.text = "%d:%02d" % [secs / 60, secs % 60]

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
	var tbm: Node = get_node_or_null("/root/TowerBuffManager")
	if tbm != null and tbm.has_signal("tower_buff_changed"):
		tbm.tower_buff_changed.connect(_on_tower_buff_changed)
		tbm.tower_buff_activated.connect(_on_tower_buff_activated)
		tbm.tower_buff_expired.connect(_on_tower_buff_expired)
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
	_refresh_time_orb()
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

# 功能塔 buff 显示(TopLeft _buff_box). 互斥 = 最多一个图标:激活/刷新更新, 清除移除.
func _on_tower_buff_changed(tower_id: StringName, buff_type: StringName, remaining: float, duration: float) -> void:
	if _buff_box == null:
		return
	if String(tower_id) == "" or remaining <= 0.0:
		_remove_tower_buff_icon()
		return
	if _tower_buff_panel == null:
		_build_tower_buff_icon()
	var col: Color = Color(1.0, 0.3, 0.3) if String(buff_type) == "damage" else Color(0.3, 0.6, 1.0)
	_tower_buff_panel.modulate = col
	if _tower_buff_label != null:
		var tag: String = "伤害" if String(buff_type) == "damage" else "加速"
		_tower_buff_label.text = "%s %.0f" % [tag, ceil(remaining)]
	if _tower_buff_fill != null and duration > 0.0:
		var ratio: float = clampf(remaining / duration, 0.0, 1.0)
		_tower_buff_fill.custom_minimum_size = Vector2(44.0 * ratio, 6.0)
		_tower_buff_fill.size.x = 44.0 * ratio

func _build_tower_buff_icon() -> void:
	_tower_buff_panel = Panel.new()
	_tower_buff_panel.custom_minimum_size = Vector2(52, 30)
	_tower_buff_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_buff_box.add_child(_tower_buff_panel)
	var vb: VBoxContainer = VBoxContainer.new()
	vb.position = Vector2(4, 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tower_buff_panel.add_child(vb)
	_tower_buff_label = Label.new()
	_tower_buff_label.add_theme_font_size_override("font_size", 12)
	_tower_buff_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_tower_buff_label)
	_tower_buff_fill = ColorRect.new()
	_tower_buff_fill.color = Color(1, 1, 1, 0.9)
	_tower_buff_fill.custom_minimum_size = Vector2(44, 6)
	_tower_buff_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(_tower_buff_fill)

func _remove_tower_buff_icon() -> void:
	if _tower_buff_panel != null:
		_tower_buff_panel.queue_free()
		_tower_buff_panel = null
		_tower_buff_fill = null
		_tower_buff_label = null

# 功能塔激活瞬间反馈:屏幕中央大字横幅 + 屏幕边缘染色闪一下(伤害红/加速蓝).
func _on_tower_buff_activated(_tower_id: StringName, buff_type: StringName, duration: float) -> void:
	var is_dmg: bool = String(buff_type) == "damage"
	var col: Color = Color(1.0, 0.3, 0.3) if is_dmg else Color(0.3, 0.65, 1.0)
	var title: String = "伤害强化 +30%" if is_dmg else "极速 +35%"
	_show_buff_banner(title, col, duration)
	_flash_screen_edge(col)
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("channel_charge")

func _show_buff_banner(text: String, col: Color, _duration: float) -> void:
	var root: Control = get_node_or_null("Root")
	if root == null:
		return
	var lbl: Label = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.5
	lbl.anchor_right = 0.5
	lbl.anchor_top = 0.32
	lbl.offset_left = -360
	lbl.offset_right = 360
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(lbl)
	var tw: Tween = create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "offset_top", lbl.offset_top - 36.0, 0.9)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.5)
	tw.chain().tween_callback(Callable(lbl, "queue_free"))

func _flash_screen_edge(col: Color) -> void:
	var root: Control = get_node_or_null("Root")
	if root == null:
		return
	var rect: ColorRect = ColorRect.new()
	rect.color = Color(col.r, col.g, col.b, 0.0)
	rect.anchor_right = 1.0
	rect.anchor_bottom = 1.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	var tw: Tween = create_tween()
	tw.tween_property(rect, "color:a", 0.28, 0.12)
	tw.tween_property(rect, "color:a", 0.0, 0.5)
	tw.tween_callback(Callable(rect, "queue_free"))

func _on_tower_buff_expired(_tower_id: StringName, buff_type: StringName) -> void:
	var col: Color = Color(0.8, 0.8, 0.8)
	var tag: String = "伤害强化" if String(buff_type) == "damage" else "极速"
	_show_buff_banner("%s 结束" % tag, col, 0.0)

func _on_focus_changed(cur: float, max_focus: float) -> void:
	if _focus_fill == null:
		return
	var ratio: float = clampf(cur / maxf(max_focus, 1.0), 0.0, 1.0)
	var target_anchor: float = 1.0 - ratio
	if _focus_tween != null and _focus_tween.is_valid():
		_focus_tween.kill()
	_focus_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_focus_tween.tween_property(_focus_fill, "anchor_top", target_anchor, 0.3)
	if _focus_label != null:
		_focus_label.text = "专注 %d/%d" % [int(cur), int(max_focus)]

func _on_health_changed(cur: int, mx: int) -> void:
	if _hp_fill == null:
		return
	var ratio: float = clampf(float(cur) / float(max(mx, 1)), 0.0, 1.0)
	var target_anchor: float = 1.0 - ratio
	if _hp_tween != null and _hp_tween.is_valid():
		_hp_tween.kill()
	_hp_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_hp_tween.tween_property(_hp_fill, "anchor_top", target_anchor, 0.3)
	if _hp_label != null:
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

func _process(delta: float) -> void:
	if _is_dead and Input.is_key_pressed(KEY_R):
		_is_dead = false
		get_tree().reload_current_scene()
	# 时间球: 倒计时每帧推进, 节流 0.25s 刷新 UI.
	_time_orb_accum += delta
	if _time_orb_accum >= 0.25:
		_time_orb_accum = 0.0
		_refresh_time_orb()
	# F3 调试 FPS
	if _debug_label != null and _debug_label.visible:
		_debug_label.text = "FPS: %d" % Engine.get_frames_per_second()
