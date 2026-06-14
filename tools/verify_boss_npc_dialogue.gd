extends SceneTree

# headless 校验: BOSS 死 → NPC 现身 → 点击 → 两轮台词 → 结算.
# 直接驱动 RiftManager / dialogue_panel / boss_npc 的公开接口, 不跑完整 boss 场景.
# 跑法: <godot_console_exe> --headless --path . --script res://tools/verify_boss_npc_dialogue.gd

var _fail: int = 0
var _pass: int = 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  [OK] ", msg)
	else:
		_fail += 1
		print("  [FAIL] ", msg)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	await process_frame   # 让 tree 激活, autoload 可达

	var rm: Node = root.get_node_or_null("/root/RiftManager")
	_ok(rm != null, "RiftManager autoload 可达")
	_ok(rm.has_signal("boss_defeated"), "RiftManager 有 boss_defeated 信号")
	_ok(rm.has_signal("run_cleared"), "RiftManager 有 run_cleared 信号")
	_ok(rm.has_method("emit_run_cleared"), "RiftManager 有 emit_run_cleared() 方法")

	# 监听 run_cleared 是否被过早触发.
	var cleared := {"hit": false}
	rm.run_cleared.connect(func(_t, _k): cleared.hit = true)

	# 监听 boss_defeated.
	var defeated := {"hit": false}
	rm.boss_defeated.connect(func(_t, _k): defeated.hit = true)

	# 1) 模拟守门人死亡: 直接调 _on_enemy_killed 喂一个带 monster_id=butcher 的假敌人.
	var fake_boss := Node3D.new()
	fake_boss.set_meta("monster_id", "butcher")
	root.add_child(fake_boss)
	rm._on_enemy_killed(fake_boss, null, 0, Vector3.ZERO)
	await process_frame
	_ok(defeated.hit, "屠夫死亡发出了 boss_defeated")
	_ok(not cleared.hit, "屠夫死亡后结算未被过早触发 (run_cleared 未发)")

	# 2) 搭建对话面板 + NPC (模拟场景内挂载).
	var DialogueScn := load("res://scenes/ui/dialogue_panel.tscn")
	_ok(DialogueScn != null, "dialogue_panel.tscn 可加载")
	var panel: Node = DialogueScn.instantiate()
	root.add_child(panel)
	await process_frame
	_ok(panel.is_in_group("dialogue_panel"), "对话面板加入了 dialogue_panel 组")
	_ok(not panel._root.visible, "对话面板初始隐藏")

	var BossNpcScript := load("res://scripts/entities/boss_npc.gd")
	_ok(BossNpcScript != null, "boss_npc.gd 可加载")
	var npc := Area3D.new()
	npc.set_script(BossNpcScript)
	root.add_child(npc)
	await process_frame
	_ok(npc.is_in_group("boss_npc"), "NPC 加入了 boss_npc 组")
	_ok(npc.get_node_or_null("Nameplate") != null, "NPC 有头顶名牌")

	# 3) 模拟点击 NPC → 启动对话.
	npc._start_dialogue()
	await process_frame
	_ok(panel._active, "点击 NPC 后对话激活")
	_ok(panel._root.visible, "对话面板已显示")
	_ok(panel._index == 0, "停在第一句")
	_ok(String(panel._line_lbl.text) == String(npc.LINES[0]), "第一句台词正确")
	_ok(not cleared.hit, "对话进行中结算仍未触发")

	# 玩家冻结校验 (若场景内有 player; headless 无 player 时跳过, 不算失败).
	# 这里没有真 player 节点, 只验证方法存在不报错 —— 已在 _start_dialogue 内安全调用.

	# 4) 推进到第二句.
	panel._advance()
	await process_frame
	_ok(panel._index == 1, "推进到第二句")
	_ok(String(panel._line_lbl.text) == String(npc.LINES[1]), "第二句台词正确")
	_ok(not cleared.hit, "第二句时结算仍未触发")

	# 5) 再推进 → 对话结束 → 触发结算.
	panel._advance()
	await process_frame
	await process_frame
	_ok(not panel._active, "对话结束后面板停用")
	_ok(cleared.hit, "对话两轮结束后 run_cleared 触发 (弹结算)")

	print("")
	print("==== 结果: %d 通过 / %d 失败 ====" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
