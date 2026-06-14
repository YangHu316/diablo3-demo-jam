extends SceneTree
# verify_rift_timeout_durations.gd — 大秘境超时 (RiftManager.rift_failed) 的 **时长/计时边界** 专项校验.
# 与 verify_rift_fail.gd 互补: 后者验"失败语义"(发一次/幂等/冻结/reset/guardian跳过),
# 本工具专攻"时间维度"边界 —— clampf 上下界 / <=0 边界 / 子秒余量 / 超长溢出 / 时钟重启 /
# 失败与守门人的两种先后次序.
#
# 跑: <console.exe> --headless --path . --script res://tools/verify_rift_timeout_durations.gd
# 所有用例不真实等待: 用 age() 把 run_start_ms 推到过去/未来制造"已过 N 秒".

var _failed_count: int = 0
var _last_payload: Array = []

func _init() -> void:
	var ok := 0
	var tot := 0
	var rm_script := load("res://scripts/autoload/rift_manager.gd")
	var rm: Node = rm_script.new()
	rm.rift_failed.connect(func(p, g, k): _failed_count += 1; _last_payload = [p, g, k])

	var RIFT_TIME_LIMIT: float = rm.RIFT_TIME_LIMIT

	# 把计时起点推到 "secs 秒前" (secs<0 = 推到未来, 模拟时钟回拨).
	var age := func(secs: float) -> void:
		rm.run_start_ms = Time.get_ticks_msec() - int(secs * 1000.0)

	var mk := func(mid: StringName) -> Node:
		var n := Node.new()
		n.set_meta("monster_id", mid)
		return n

	# ① 精确边界: 剩余恰好≈0 (<=0.0 边界须触发). get_clear_time 读真实墙钟, 推满 LIMIT 后剩余≈0.
	tot += 1
	_failed_count = 0
	rm.reset_rift()
	age.call(RIFT_TIME_LIMIT)
	var rem1: float = rm.get_time_remaining()
	rm._process(0.0)
	if rem1 < 0.001 and rm.run_failed and _failed_count == 1:
		ok += 1; print("OK① 精确边界 剩余=%.4f → 失败发一次 (<=0.0 边界)" % rem1)
	else:
		printerr("FAIL① 剩余=%.4f run_failed=%s count=%d (期望 <0.001/true/1)" % [rem1, str(rm.run_failed), _failed_count])

	# ② 临界前 (剩~0.5s): remaining>0, 不应提前判负.
	tot += 1
	_failed_count = 0
	rm.reset_rift()
	age.call(RIFT_TIME_LIMIT - 0.5)
	var rem2: float = rm.get_time_remaining()
	rm._process(0.0)
	if rem2 > 0.001 and not rm.run_failed and _failed_count == 0:
		ok += 1; print("OK② 剩~0.5s (=%.3f) 不提前判负" % rem2)
	else:
		printerr("FAIL② 剩余=%.3f run_failed=%s count=%d (期望 >0/false/0)" % [rem2, str(rm.run_failed), _failed_count])

	# ③ 子秒余量 (剩~0.05s): 介于①(≈0)与②(0.5s)之间, >0 仍不触发.
	tot += 1
	_failed_count = 0
	rm.reset_rift()
	age.call(RIFT_TIME_LIMIT - 0.05)
	var rem3: float = rm.get_time_remaining()
	rm._process(0.0)
	if rem3 > 0.001 and not rm.run_failed and _failed_count == 0:
		ok += 1; print("OK③ 子秒余量 (=%.3f) >0 不触发" % rem3)
	else:
		printerr("FAIL③ 剩余=%.3f run_failed=%s count=%d (期望 >0.001/false/0)" % [rem3, str(rm.run_failed), _failed_count])

	# ④ clamp 上界 (未来起点/时钟回拨): elapsed<0 → 剩余钳到 RIFT_TIME_LIMIT, 不触发.
	tot += 1
	_failed_count = 0
	rm.reset_rift()
	age.call(-50.0)   # 起点在 50s 后 → elapsed≈-50 → LIMIT-(-50)=170 → clamp 回 120
	var rem4: float = rm.get_time_remaining()
	rm._process(0.0)
	if absf(rem4 - RIFT_TIME_LIMIT) < 0.01 and not rm.run_failed and _failed_count == 0:
		ok += 1; print("OK④ 时钟回拨 剩余钳到上界 (=%.3f) 不触发" % rem4)
	else:
		printerr("FAIL④ 剩余=%.3f run_failed=%s count=%d (期望≈%.0f/false/0)" % [rem4, str(rm.run_failed), _failed_count, RIFT_TIME_LIMIT])

	# ⑤ clamp 下界 (超长溢出, 超时 1 小时): 剩余仍钳到 0 (不为负), 失败仍只发一次.
	tot += 1
	_failed_count = 0
	rm.reset_rift()
	age.call(RIFT_TIME_LIMIT + 3600.0)   # 超时 1 小时
	var rem5: float = rm.get_time_remaining()
	rm._process(0.0)
	if absf(rem5) < 0.001 and rm.run_failed and _failed_count == 1:
		ok += 1; print("OK⑤ 超长溢出(+3600s) 剩余钳到 0 (=%.4f) 失败发一次" % rem5)
	else:
		printerr("FAIL⑤ 剩余=%.4f run_failed=%s count=%d (期望 0/true/1)" % [rem5, str(rm.run_failed), _failed_count])

	# ⑥ 时钟线性内点 (中段~30s): elapsed≈30 / 剩余≈90, 验证非钳制区线性正确, 不触发.
	tot += 1
	_failed_count = 0
	rm.reset_rift()
	age.call(30.0)
	var elapsed6: float = rm.get_clear_time()
	var rem6: float = rm.get_time_remaining()
	rm._process(0.0)
	if absf(elapsed6 - 30.0) < 0.5 and absf(rem6 - (RIFT_TIME_LIMIT - 30.0)) < 0.5 and not rm.run_failed:
		ok += 1; print("OK⑥ 线性内点 已过=%.2f 剩余=%.2f 不触发" % [elapsed6, rem6])
	else:
		printerr("FAIL⑥ 已过=%.2f 剩余=%.2f run_failed=%s (期望≈30/≈90/false)" % [elapsed6, rem6, str(rm.run_failed)])

	# ⑦ 截止瞬间填满进度 → 守门人先触发, 短路超时 (guardian-before-fail 次序).
	tot += 1
	_failed_count = 0
	rm.reset_rift()
	age.call(RIFT_TIME_LIMIT + 5.0)            # 已超时
	for i in range(14):                        # 14*8=112 >= goal(106) → 中途触发守门人
		rm._on_enemy_killed(mk.call(&"champion_yellow"), null, 0, Vector3.ZERO)
	if not rm.guardian_triggered:
		printerr("FAIL⑦ 填满后 guardian_triggered 应为 true")
	elif rm.get_time_remaining() >= 0.001:
		printerr("FAIL⑦ 应已超时 (剩余应=0) 实际=%f" % rm.get_time_remaining())
	else:
		rm._process(0.0)                       # 守门人已触发 → 短路
		if rm.run_failed or _failed_count != 0:
			printerr("FAIL⑦ 守门人应短路 但 run_failed=%s count=%d" % [str(rm.run_failed), _failed_count])
		else:
			ok += 1; print("OK⑦ 截止瞬间填满→守门人先触发 短路超时 (无 rift_failed)")

	# ⑧ 失败先触发, 之后再标 guardian_triggered → _process 不补发第二次 (fail-before-guardian 次序).
	tot += 1
	_failed_count = 0
	rm.reset_rift()
	age.call(RIFT_TIME_LIMIT + 1.0)
	rm._process(0.0)                           # 先超时失败 (count=1)
	var c8: int = _failed_count
	rm.guardian_triggered = true               # 事后人为置位 (模拟竞态)
	rm._process(0.0)
	rm._process(0.0)
	if c8 == 1 and _failed_count == 1 and rm.run_failed:
		ok += 1; print("OK⑧ 失败先于守门人 后续 _process 不补发 (count=%d)" % _failed_count)
	else:
		printerr("FAIL⑧ c8=%d count=%d run_failed=%s (期望 1/1/true)" % [c8, _failed_count, str(rm.run_failed)])

	# ⑨ reset 重启时钟: 超时失败后 reset → 剩余回满 RIFT_TIME_LIMIT (时钟重启, 非仅清标志).
	tot += 1
	_failed_count = 0
	rm.reset_rift()
	age.call(RIFT_TIME_LIMIT + 5.0)
	rm._process(0.0)
	if rm.run_failed and _failed_count == 1 and rm.get_time_remaining() < 0.001:
		_failed_count = 0
		rm.reset_rift()
		if not rm.run_failed and absf(rm.get_time_remaining() - RIFT_TIME_LIMIT) < 0.5:
			ok += 1; print("OK⑨ reset 后时钟回满 (剩余=%.2f)" % rm.get_time_remaining())
		else:
			printerr("FAIL⑨ reset 后 run_failed=%s 剩余=%.2f (期望 false/≈%.0f)" % [str(rm.run_failed), rm.get_time_remaining(), RIFT_TIME_LIMIT])
	else:
		printerr("FAIL⑨ 前置未满足 run_failed=%s count=%d 剩余=%.4f" % [str(rm.run_failed), _failed_count, rm.get_time_remaining()])

	print("==== verify_rift_timeout_durations: %d/%d 判定通过 ====" % [ok, tot])
	rm.free()
	quit(0 if ok == tot else 1)
