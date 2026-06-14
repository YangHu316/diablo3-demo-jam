extends SceneTree
# verify_settlement.gd — 校验守门人结算面板支撑 (系统②/程序②):
#   ① RiftManager 有 run_cleared 信号 + reset_rift/get_kill_count/get_clear_time 方法
#   ② reset_rift 后击杀计数累加正确 (含守门人), get_clear_time>=0
#   ③ 击杀守门人(butcher/guardian) 触发 run_cleared, 且不喂进度
#   ④ settlement_panel.gd 解析 OK
#   ⑤ DataTables.get_boss_drop_items() == 14 件

var _cleared: int = 0
var _last_kills: int = 0

func _init() -> void:
	var ok := 0
	var tot := 0
	var rm_script := load("res://scripts/autoload/rift_manager.gd")
	var rm: Node = rm_script.new()

	# ① 信号 + 方法存在
	tot += 1
	if rm.has_signal("run_cleared") and rm.has_method("reset_rift") \
			and rm.has_method("get_kill_count") and rm.has_method("get_clear_time"):
		ok += 1; print("OK① run_cleared 信号 + 访问器齐全")
	else:
		printerr("FAIL① 缺信号或方法")

	rm.run_cleared.connect(func(_t, k): _cleared += 1; _last_kills = k)

	var mk := func(mid: StringName) -> Node:
		var n := Node.new()
		n.set_meta("monster_id", mid)
		return n

	# ② reset 后计数累加 + 用时>=0
	tot += 1
	rm.reset_rift()
	rm._on_enemy_killed(mk.call(&"trash"), null, 0, Vector3.ZERO)
	rm._on_enemy_killed(mk.call(&"elite_blue"), null, 0, Vector3.ZERO)
	if rm.get_kill_count() == 2 and rm.get_clear_time() >= 0.0:
		ok += 1; print("OK② 击杀计数=%d 用时=%.2fs" % [rm.get_kill_count(), rm.get_clear_time()])
	else:
		printerr("FAIL② kills=%d time=%.2f" % [rm.get_kill_count(), rm.get_clear_time()])

	# ③ 守门人死触发 run_cleared 且不喂进度
	tot += 1
	rm.reset_rift()
	_cleared = 0
	var p_before: float = rm.progress
	rm._on_enemy_killed(mk.call(&"butcher"), null, 0, Vector3.ZERO)
	if _cleared == 1 and _last_kills == 1 and absf(rm.progress - p_before) < 0.01:
		ok += 1; print("OK③ 守门人死触发 run_cleared(kills=%d) 不喂进度" % _last_kills)
	else:
		printerr("FAIL③ cleared=%d kills=%d progress=%.1f" % [_cleared, _last_kills, rm.progress])

	# ④ settlement_panel.gd 解析
	tot += 1
	var sp := load("res://scripts/ui/settlement_panel.gd")
	if sp != null:
		ok += 1; print("OK④ settlement_panel.gd 加载/解析成功")
	else:
		printerr("FAIL④ settlement_panel.gd 加载失败")

	# ⑤ 掉落 14 件
	tot += 1
	var dt_script := load("res://scripts/autoload/data_tables.gd")
	var dt: Node = dt_script.new()
	dt._load_boss_drops()
	var items: Array = dt.get_boss_drop_items() if dt.has_method("get_boss_drop_items") else []
	if items.size() == 14:
		ok += 1; print("OK⑤ boss 掉落 = 14 件")
	else:
		printerr("FAIL⑤ 期望14 实得%d" % items.size())
	dt.free()

	print("==== verify_settlement: %d/%d 判定通过 ====" % [ok, tot])
	rm.free()
	quit(0 if ok == tot else 1)
