extends SceneTree
# verify_rift_timer_freeze.gd — 校验"进入最终boss关时停止计时"(RiftManager 计时冻结):
#   ① 未触发守门人时, get_clear_time 随真实时间推进 (计时进行中)
#   ② _trigger_guardian (=进boss关) 后, get_clear_time 冻结为快照值
#   ③ 冻结后 get_time_remaining 也静止 (= limit - 冻结值)
#   ④ reset_rift 清除冻结, 计时重新开始

func _init() -> void:
	var ok := 0
	var tot := 0
	var rm_script := load("res://scripts/autoload/rift_manager.gd")
	var rm: Node = rm_script.new()
	rm.reset_rift()

	# ① 未冻结: 连测两次 get_clear_time, 中间忙等几 ms, 第二次应 >= 第一次 (时间在走).
	tot += 1
	var t0: float = rm.get_clear_time()
	var spin: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - spin < 20:
		pass
	var t1: float = rm.get_clear_time()
	if t1 >= t0 and rm._frozen_clear_sec < 0.0:
		ok += 1; print("OK① 未触发守门人: 计时进行中 (%.3f→%.3f, 未冻结)" % [t0, t1])
	else:
		printerr("FAIL① 期望计时推进且未冻结, t0=%.3f t1=%.3f frozen=%.3f" % [t0, t1, rm._frozen_clear_sec])

	# ② 触发守门人 (=进boss关) → 冻结. 记录冻结瞬间值.
	tot += 1
	rm._trigger_guardian()
	var frozen: float = rm.get_clear_time()
	if rm.guardian_triggered and rm._frozen_clear_sec >= 0.0 and absf(frozen - rm._frozen_clear_sec) < 0.001:
		ok += 1; print("OK② 进boss关触发守门人 → 计时冻结快照=%.3f" % frozen)
	else:
		printerr("FAIL② 期望冻结, triggered=%s frozen_sec=%.3f get=%.3f" % [rm.guardian_triggered, rm._frozen_clear_sec, frozen])

	# ③ 冻结后忙等再读, get_clear_time / get_time_remaining 均静止.
	tot += 1
	var rem_before: float = rm.get_time_remaining()
	var spin2: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - spin2 < 30:
		pass
	var clear_after: float = rm.get_clear_time()
	var rem_after: float = rm.get_time_remaining()
	if absf(clear_after - frozen) < 0.001 and absf(rem_after - rem_before) < 0.001:
		ok += 1; print("OK③ 冻结后忙等30ms: clear静止(%.3f) 剩余静止(%.3f)" % [clear_after, rem_after])
	else:
		printerr("FAIL③ 期望静止, clear %.3f→%.3f 剩余 %.3f→%.3f" % [frozen, clear_after, rem_before, rem_after])

	# ④ reset_rift 清冻结, 计时重新走.
	tot += 1
	rm.reset_rift()
	if rm._frozen_clear_sec < 0.0 and not rm.guardian_triggered:
		ok += 1; print("OK④ reset_rift 清除冻结, 计时可重新开始 (frozen=%.1f)" % rm._frozen_clear_sec)
	else:
		printerr("FAIL④ reset 后仍冻结 frozen=%.3f triggered=%s" % [rm._frozen_clear_sec, rm.guardian_triggered])

	print("==== verify_rift_timer_freeze: %d/%d 判定通过 ====" % [ok, tot])
	rm.free()
	quit(0 if ok == tot else 1)
