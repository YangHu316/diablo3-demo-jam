extends SceneTree
# verify_rift_fail.gd — 校验大秘境超时失败 (RiftManager.rift_failed):
#   ① 倒计时归零 且 进度未满 → 发 rift_failed(progress,goal,kill_count) 恰一次
#   ② _process 多次调用只发一次 (run_failed 锁)
#   ③ 进度已满(guardian_triggered) → 即使超时也不发 rift_failed
#   ④ 失败后 _add_progress / add_time_ball 被冻结 (不再累计)
#   ⑤ reset_rift 清 run_failed → 可重新触发
#   ⑥ 未超时(剩余>0) 不发 rift_failed

var _failed_count: int = 0
var _last_payload: Array = []

func _init() -> void:
	var ok := 0
	var tot := 0
	var rm_script := load("res://scripts/autoload/rift_manager.gd")
	var rm: Node = rm_script.new()
	rm.rift_failed.connect(func(p, g, k): _failed_count += 1; _last_payload = [p, g, k])

	var mk := func(mid: StringName) -> Node:
		var n := Node.new()
		n.set_meta("monster_id", mid)
		return n

	# 工具: 把计时起点推到过去 N 秒前 (制造"已过 N 秒").
	var age := func(secs: float) -> void:
		rm.run_start_ms = Time.get_ticks_msec() - int(secs * 1000.0)

	# ⑥ 未超时不发 (剩余>0)
	tot += 1
	rm.reset_rift()
	_failed_count = 0
	age.call(10.0)   # 才过 10s, 剩 110s
	rm._process(0.0)
	if _failed_count == 0 and not rm.run_failed:
		ok += 1; print("OK⑥ 未超时(剩余>0)不发 rift_failed")
	else:
		printerr("FAIL⑥ 未超时却发了 failed=%d" % _failed_count)

	# ① 超时且未满 → 发一次
	tot += 1
	rm.reset_rift()
	_failed_count = 0
	rm._on_enemy_killed(mk.call(&"trash"), null, 0, Vector3.ZERO)  # 进度=1, 远未满106
	age.call(rm.RIFT_TIME_LIMIT + 1.0)   # 超时 1s
	rm._process(0.0)
	if _failed_count == 1 and rm.run_failed and absf(float(_last_payload[1]) - rm.goal) < 0.01:
		ok += 1; print("OK① 超时未满发 rift_failed(progress=%.0f goal=%.0f kill=%d)" % [_last_payload[0], _last_payload[1], _last_payload[2]])
	else:
		printerr("FAIL① failed=%d run_failed=%s payload=%s" % [_failed_count, rm.run_failed, str(_last_payload)])

	# ② 多次 _process 只发一次
	tot += 1
	rm._process(0.0)
	rm._process(0.0)
	if _failed_count == 1:
		ok += 1; print("OK② 多次 _process 仅发一次 (failed=%d)" % _failed_count)
	else:
		printerr("FAIL② 重复发 failed=%d" % _failed_count)

	# ④ 失败后进度冻结
	tot += 1
	var locked: float = rm.progress
	rm._on_enemy_killed(mk.call(&"trash"), null, 0, Vector3.ZERO)
	rm.add_time_ball()
	if absf(rm.progress - locked) < 0.01:
		ok += 1; print("OK④ 失败后进度冻结 (=%.0f)" % rm.progress)
	else:
		printerr("FAIL④ 失败后仍累计 %.1f->%.1f" % [locked, rm.progress])

	# ⑤ reset 后可重新触发
	tot += 1
	rm.reset_rift()
	_failed_count = 0
	if rm.run_failed == false:
		age.call(rm.RIFT_TIME_LIMIT + 1.0)
		rm._process(0.0)
		if _failed_count == 1 and rm.run_failed:
			ok += 1; print("OK⑤ reset 清标志后可重新触发 (failed=%d)" % _failed_count)
		else:
			printerr("FAIL⑤ reset 后未重新触发 failed=%d" % _failed_count)
	else:
		printerr("FAIL⑤ reset 未清 run_failed")

	# ③ 进度已满(guardian)→ 超时不发 failed
	tot += 1
	rm.reset_rift()
	_failed_count = 0
	for i in range(int(rm.GOAL)):
		rm._on_enemy_killed(mk.call(&"trash"), null, 0, Vector3.ZERO)  # 白怪×106 喂满 → guardian_triggered
	age.call(rm.RIFT_TIME_LIMIT + 5.0)
	rm._process(0.0)
	if rm.guardian_triggered and _failed_count == 0 and not rm.run_failed:
		ok += 1; print("OK③ 已通关(guardian)即使超时不发 failed")
	else:
		printerr("FAIL③ guardian=%s failed=%d run_failed=%s" % [rm.guardian_triggered, _failed_count, rm.run_failed])

	print("==== verify_rift_fail: %d/%d 判定通过 ====" % [ok, tot])
	rm.free()
	quit(0 if ok == tot else 1)
