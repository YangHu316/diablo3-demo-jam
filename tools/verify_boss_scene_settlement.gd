extends Node
# verify_boss_scene_settlement.gd — 确认结算面板已真正并入 boss 房主流程:
#   直接加载并实例化 boss_room_play.tscn (RiftManager 满进度后切的就是它) ->
#   等其进树 -> 在树里找 SettlementPanel 节点 (证明已挂) ->
#   真实 emit RiftManager.run_cleared -> 断言面板显示 + 14 行掉落。
# Run: godot --headless --path . --scene res://tools/verify_boss_scene_settlement.tscn

var _fail := 0

func _ck(c: bool, m: String) -> void:
	if c: print("  OK  - ", m)
	else: _fail += 1; print("  FAIL- ", m)

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	var rm := get_node_or_null("/root/RiftManager")
	_ck(rm != null, "RiftManager autoload 在树")

	# 加载并挂 boss 房 (= RiftManager.BOSS_SCENE).
	var ps := load("res://scenes/levels/boss_room_play.tscn")
	_ck(ps != null, "boss_room_play.tscn 加载成功")
	var boss: Node = ps.instantiate()
	add_child(boss)
	await get_tree().process_frame
	await get_tree().process_frame

	# 在 boss 房子树里找三块 UI, 证明已并入.
	var hud := boss.get_node_or_null("HUD")
	var inv := boss.get_node_or_null("InventoryPanel")
	var sp := boss.get_node_or_null("SettlementPanel")
	_ck(hud != null, "boss 房挂 HUD")
	_ck(inv != null, "boss 房挂 InventoryPanel")
	_ck(sp != null, "boss 房挂 SettlementPanel (已并入主流程)")

	var ui_root: Control = sp.get_node_or_null("Root") if sp != null else null
	_ck(ui_root != null and not ui_root.visible, "结算面板初始隐藏")

	# 真实发通关信号 (守门人死的等价事件).
	if rm != null:
		rm.run_cleared.emit(212.0, 53)
	await get_tree().process_frame

	_ck(ui_root != null and ui_root.visible, "run_cleared 后结算面板显示")
	if sp != null and sp._loot_box != null:
		_ck(sp._loot_box.get_child_count() == 14, "掉落 14 行 (实: %d)" % sp._loot_box.get_child_count())
	if sp != null and sp._time_kill_lbl != null:
		_ck(sp._time_kill_lbl.text.find("03:32") >= 0, "用时 03:32 (212s, 实: %s)" % sp._time_kill_lbl.text)
		_ck(sp._time_kill_lbl.text.find("53") >= 0, "击杀 53 已填")

	print("\n========================================")
	if _fail == 0:
		print("VERIFY OK - 结算面板已并入 boss 房主流程, 端到端通过")
	else:
		print("VERIFY FAIL - %d 项未通过" % _fail)
	get_tree().quit(0 if _fail == 0 else 1)
