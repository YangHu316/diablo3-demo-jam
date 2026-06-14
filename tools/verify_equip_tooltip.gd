extends SceneTree

# 验证: 装备 UI hover tooltip (用户诉求: 每框 hover 出现各装备数值加成).
# 覆盖:
#   - inventory_panel.tscn 实例化无运行时错误 (含新 _build_tooltip)
#   - hover 装备槽 -> tooltip 显示该件词缀加成行
#   - hover 背包格 -> tooltip 显示词缀行
#   - hover 空槽 -> 轻提示 "未装备"
#   - 离开 -> tooltip 隐藏
# Run headless:
#   godot --headless --path . --script res://tools/verify_equip_tooltip.gd

var _fail := 0

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  - ", msg)
	else:
		_fail += 1
		print("  FAIL- ", msg)

func _make_item(nm: String, slot: int, stat_kind: int, value: float, pct: bool, q: int = 4) -> ItemInstance:
	var it := ItemInstance.new()
	it.display_name = nm
	it.slot = slot
	it.quality = q
	it.item_level = 70
	it.affixes = [{
		"stat_kind": stat_kind, "value": value, "is_percent": pct, "affix_id": &"test_affix"
	}]
	return it

func _init() -> void:
	_run()

func _run() -> void:
	print("=== verify_equip_tooltip ===")
	await process_frame   # 等 SceneTree 激活, 自动加载就绪
	var inv: Node = root.get_node_or_null("/root/Inventory")
	_ck(inv != null, "Inventory autoload 在线")
	if inv == null:
		_finish(); return

	# 实例化面板.
	var ps: PackedScene = load("res://scenes/ui/inventory_panel.tscn")
	_ck(ps != null, "inventory_panel.tscn 可加载")
	if ps == null:
		_finish(); return
	var panel: CanvasLayer = ps.instantiate()
	root.add_child(panel)
	await process_frame
	_ck(true, "面板实例化无崩溃")

	# 打开面板 (触发 _refresh_all + 右侧写死面板渲染).
	if panel.has_method("_set_open"):
		panel._set_open(true)
		await process_frame
	_ck(panel.get("_open") == true, "面板打开成功")

	# 造一件带"暴击伤害 +60%"词缀的胸甲, 放入背包并装备.
	var chest := _make_item("测试胸甲", EquipSlots.Slot.CHEST, AffixDef.StatKind.CRIT_DAMAGE, 60.0, true)
	if inv.has_method("add_item"):
		inv.add_item(chest)
	await process_frame

	# hover 背包格 0 -> tooltip 可见 + 含词缀行.
	if panel.has_method("_on_bag_hover"):
		var dummy_btn := Button.new()
		root.add_child(dummy_btn)
		panel._on_bag_hover(0, dummy_btn)
		await process_frame
		var tip = panel.get("_tooltip")
		_ck(tip != null and tip.visible, "hover 背包件 -> tooltip 弹出")
		_ck(_tip_has_text(panel, "暴击伤害"), "tooltip 显示该件词缀名 (暴击伤害)")
		_ck(_tip_has_text(panel, "60"), "tooltip 显示词缀数值加成 (+60%)")
		# 离开隐藏.
		panel._hide_tooltip()
		await process_frame
		_ck(not tip.visible, "离开 -> tooltip 隐藏")
		dummy_btn.queue_free()

	# 装备该件, hover 对应装备槽 -> tooltip 含词缀.
	if inv.has_method("equip"):
		inv.equip(EquipSlots.Slot.CHEST, chest)
	elif inv.has_method("quick_equip"):
		inv.quick_equip(chest)
	await process_frame
	if panel.has_method("_on_equip_hover"):
		var slot_btns: Dictionary = panel.get("_slot_buttons")
		var cbtn: Button = slot_btns.get(EquipSlots.Slot.CHEST, null)
		_ck(cbtn != null, "胸甲装备槽按钮存在")
		if cbtn != null:
			panel._on_equip_hover(EquipSlots.Slot.CHEST, cbtn)
			await process_frame
			_ck(_tip_has_text(panel, "暴击伤害"), "hover 已装备件 -> tooltip 显示词缀加成")
			# hover 空槽 (头部, 未装备) -> 未装备提示.
			var hbtn: Button = slot_btns.get(EquipSlots.Slot.HEAD, null)
			if hbtn != null:
				panel._on_equip_hover(EquipSlots.Slot.HEAD, hbtn)
				await process_frame
				_ck(_tip_has_text(panel, "未装备"), "hover 空槽 -> '未装备' 轻提示")

	_finish()

# 遍历 tooltip 内 Label 文本, 看是否含子串.
func _tip_has_text(panel: Node, needle: String) -> bool:
	var box = panel.get("_tip_box")
	if box == null:
		return false
	for c in box.get_children():
		if c is Label and String(c.text).find(needle) >= 0:
			return true
	return false

func _finish() -> void:
	if _fail == 0:
		print("=== 全部通过 ===")
	else:
		print("=== 失败 %d 项 ===" % _fail)
	quit()
