extends Node
# settlement_ui_harness.gd — 结算面板"在真实运行树里"集成校验.
#   作为临时主场景跑 (autoloads 全活: DataTables/RiftManager...), 真实挂面板 ->
#   等一帧让 _ready/路径解析生效 -> 真实 emit RiftManager.run_cleared ->
#   断言面板 visible + 用时/击杀文案 + 14 行掉落上色.
# Run: godot --headless --path . --scene res://tools/settlement_ui_harness.tscn

var _fail := 0

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  - ", msg)
	else:
		_fail += 1
		print("  FAIL- ", msg)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# 等两帧, 确保 autoload + 本场景节点都进树、路径可解析.
	await get_tree().process_frame
	await get_tree().process_frame

	# autoload 应已就绪.
	var dt := get_node_or_null("/root/DataTables")
	var rm := get_node_or_null("/root/RiftManager")
	_ck(dt != null, "DataTables autoload 在树 (/root/DataTables)")
	_ck(rm != null, "RiftManager autoload 在树 (/root/RiftManager)")

	# 实例化结算面板, 挂进真实树 (走真实 _ready 构建 UI + 连 run_cleared).
	var ps := load("res://scenes/ui/settlement_panel.tscn")
	_ck(ps != null, "settlement_panel.tscn 加载成功")
	var panel: Node = ps.instantiate()
	add_child(panel)
	await get_tree().process_frame   # 让面板 _ready + 信号连接生效

	var ui_root: Control = panel.get_node_or_null("Root")
	_ck(ui_root != null, "UI Root 已构建")
	_ck(ui_root != null and not ui_root.visible, "初始隐藏")

	# ── 真实通过 RiftManager 发 run_cleared (而非直调回调) ──
	_ck(rm != null and rm.has_signal("run_cleared"), "RiftManager 有 run_cleared 信号")
	if rm != null:
		rm.run_cleared.emit(125.4, 37)
	await get_tree().process_frame

	_ck(ui_root != null and ui_root.visible, "run_cleared 后面板显示")

	var tk: Label = panel._time_kill_lbl
	_ck(tk != null and tk.text.find("02:05") >= 0, "用时 02:05 (实: %s)" % (tk.text if tk else "<null>"))
	_ck(tk != null and tk.text.find("37") >= 0, "击杀 37 已填")

	var loot: VBoxContainer = panel._loot_box
	_ck(loot != null, "战利品容器存在")
	if loot != null:
		var rows := loot.get_child_count()
		_ck(rows == 14, "掉落 14 行 (实: %d)" % rows)
		var has_text := 0
		var colored := 0
		var greens := 0
		for c in loot.get_children():
			if c is Label:
				if (c as Label).text != "":
					has_text += 1
				var col: Color = (c as Label).get_theme_color("font_color")
				if col != Color.WHITE:
					colored += 1
				# 套装绿 ≈ (0.2,0.85,0.2)
				if col.g > 0.7 and col.r < 0.4 and col.b < 0.4:
					greens += 1
		_ck(has_text == 14, "14 行都有物品名 (实: %d)" % has_text)
		_ck(colored >= 1, "至少一行品质色上色 (实: %d)" % colored)
		_ck(greens >= 1, "至少一行绿套色 (boss_drop 含 is_set, 实: %d)" % greens)

	# 重开目标场景常量正确.
	_ck(panel.START_SCENE == "res://scenes/levels/level_02_play.tscn", "重开目标=L2")

	# 幂等: 再发一次不重复堆行.
	var before := loot.get_child_count() if loot != null else -1
	if rm != null:
		rm.run_cleared.emit(99.0, 99)
	await get_tree().process_frame
	var after := loot.get_child_count() if loot != null else -2
	_ck(before == after, "重复 run_cleared 幂等")

	print("\n========================================")
	if _fail == 0:
		print("VERIFY OK - 结算面板运行树集成校验全部通过")
	else:
		print("VERIFY FAIL - %d 项未通过" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
