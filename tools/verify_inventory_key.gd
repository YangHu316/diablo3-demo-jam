extends SceneTree

# 回归验证: 背包面板开关键 = B (physical_keycode 66)。
# 真实加载 main.tscn, 走完整输入管线注入 B 键事件, 断言面板可见性翻转;
# 并交叉验证 B 不误触其它动作、E(旧键) 不再开面板。
# Run headless:
#   godot --headless --path . --script res://tools/verify_inventory_key.gd

var _fail := 0

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  - ", msg)
	else:
		_fail += 1
		print("  FAIL- ", msg)

# 构造一个 InputEventKey 并经真实输入管线分发, 再 await 一帧让 _unhandled_key_input 处理。
func _press(physical_keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical_keycode
	ev.keycode = physical_keycode   # 兜底分支用 keycode == KEY_B
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()

func _init() -> void:
	_run()

func _run() -> void:
	# 真实加载主场景 (含 InventoryPanel 实例)。
	var err := change_scene_to_file("res://scenes/main.tscn")
	_ck(err == OK, "main.tscn 加载成功 (err=%d)" % err)

	# 等几帧让 autoload / 场景 _ready 跑完。
	for _i in range(5):
		await process_frame

	var panel := _find_panel()
	if panel == null:
		panel = get_root().get_node_or_null("Main/InventoryPanel")
	_ck(panel != null, "找到 InventoryPanel 节点")
	if panel == null:
		_finish()
		return

	# ── 判定①: 输入映射正确 ──
	print("=== 判定①: toggle_inventory 绑定 B(66) ===")
	_ck(InputMap.has_action("toggle_inventory"), "toggle_inventory 动作存在")
	var bound_b := false
	var bound_other := false
	for ev in InputMap.action_get_events("toggle_inventory"):
		if ev is InputEventKey:
			if ev.physical_keycode == KEY_B:
				bound_b = true
			else:
				bound_other = true
	_ck(bound_b, "toggle_inventory 绑定 physical_keycode == KEY_B(66)")
	_ck(not bound_other, "toggle_inventory 未残留其它键 (E 已移除)")

	# ── 判定②: 初始隐藏 ──
	print("=== 判定②: 初始面板隐藏 ===")
	_ck(panel._open == false, "初始 _open == false")

	# ── 判定③: 按 B 打开 ──
	print("=== 判定③: 按 B -> 打开 ===")
	_press(KEY_B)
	await process_frame
	_ck(panel._open == true, "按 B 后 _open == true (面板打开)")

	# ── 判定④: 再按 B 关闭 ──
	print("=== 判定④: 再按 B -> 关闭 ===")
	_press(KEY_B)
	await process_frame
	_ck(panel._open == false, "再按 B 后 _open == false (面板关闭)")

	# ── 判定⑤: 按旧键 E 不再开面板 ──
	print("=== 判定⑤: 旧键 E 失效 ===")
	_press(KEY_E)
	await process_frame
	_ck(panel._open == false, "按 E 不开面板 (旧键已废)")

	_finish()

func _find_panel() -> Node:
	var nodes := get_nodes_in_group("inventory_panel")
	if nodes.size() > 0:
		return nodes[0]
	return null

func _finish() -> void:
	print("========================================")
	if _fail == 0:
		print("VERIFY OK - 背包 B 键开关全部通过")
		quit(0)
	else:
		print("VERIFY FAIL - %d 项未通过" % _fail)
		quit(1)
