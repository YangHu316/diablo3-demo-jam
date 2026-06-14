extends SceneTree
# verify_rift_progress.gd — 校验 P1-2 大秘境进度系统 (RiftManager):
#   ① 白怪+1 权重正确; 精英(蓝/黄)击杀本身不直接加权 (改掉进度球, 见 verify_elite_progress_ball)
#   ② 同一只怪重复发 enemy_killed 只计一次 (防重复)
#   ③ 守门人(guardian/butcher)不计进度
#   ④ 时间球 +3.0
#   ⑤ 进度满 GOAL 触发 guardian_ready 信号 + guardian_triggered=true
#   ⑥ 满后不再累计 (锁定)

var _guardian_fired: int = 0

func _init() -> void:
	var ok := 0
	var tot := 0
	var rm_script := load("res://scripts/autoload/rift_manager.gd")
	var rm: Node = rm_script.new()
	# 手动跑 _ready 会尝试连 CombatManager(此时无 autoload 树), 不影响:我们直接调内部.
	rm.guardian_ready.connect(func(): _guardian_fired += 1)

	# 造假怪: 带 monster_id 元数据.
	var mk := func(mid: StringName) -> Node:
		var n := Node.new()
		n.set_meta("monster_id", mid)
		return n

	# ① 白怪+1; 精英击杀本身不加权 (蓝/黄各杀1只, progress 仍只 = 白怪那 1)
	tot += 1
	rm.reset_rift()
	rm._on_enemy_killed(mk.call(&"trash"), null, 0, Vector3.ZERO)
	rm._on_enemy_killed(mk.call(&"elite_blue"), null, 0, Vector3.ZERO)
	rm._on_enemy_killed(mk.call(&"champion_yellow"), null, 0, Vector3.ZERO)
	if absf(rm.progress - 1.0) < 0.01 and rm.kill_count == 3:
		ok += 1; print("OK① 白怪+1 精英击杀不直接加权 (progress=%.0f kills=%d)" % [rm.progress, rm.kill_count])
	else:
		printerr("FAIL① 期望progress=1 kills=3 实得 progress=%.1f kills=%d" % [rm.progress, rm.kill_count])

	# ② 防重复: 同一实例发两次只计一次
	tot += 1
	rm.reset_rift()
	var same: Node = mk.call(&"trash")
	rm._on_enemy_killed(same, null, 0, Vector3.ZERO)
	rm._on_enemy_killed(same, null, 0, Vector3.ZERO)
	if absf(rm.progress - 1.0) < 0.01:
		ok += 1; print("OK② 同怪重复只计一次 (=%.0f)" % rm.progress)
	else:
		printerr("FAIL② 期望1 实得%.1f" % rm.progress)

	# ③ 守门人不计
	tot += 1
	rm.reset_rift()
	rm._on_enemy_killed(mk.call(&"guardian"), null, 0, Vector3.ZERO)
	rm._on_enemy_killed(mk.call(&"butcher"), null, 0, Vector3.ZERO)
	if absf(rm.progress) < 0.01:
		ok += 1; print("OK③ 守门人/屠夫不计进度 (=%.0f)" % rm.progress)
	else:
		printerr("FAIL③ 期望0 实得%.1f" % rm.progress)

	# ④ 时间球 +3
	tot += 1
	rm.reset_rift()
	rm.add_time_ball()
	if absf(rm.progress - 3.0) < 0.01:
		ok += 1; print("OK④ 时间球 +3 (=%.0f)" % rm.progress)
	else:
		printerr("FAIL④ 期望3 实得%.1f" % rm.progress)

	# ⑤ 满 GOAL 触发 guardian
	tot += 1
	rm.reset_rift()
	_guardian_fired = 0
	# 用白怪(1) 喂满 106 -> 106 只
	for i in range(int(rm.GOAL)):
		rm._on_enemy_killed(mk.call(&"trash"), null, 0, Vector3.ZERO)
	if rm.guardian_triggered and _guardian_fired == 1 and rm.progress >= rm.GOAL:
		ok += 1; print("OK⑤ 满%.0f 触发 guardian_ready (progress=%.0f)" % [rm.GOAL, rm.progress])
	else:
		printerr("FAIL⑤ triggered=%s fired=%d progress=%.1f" % [rm.guardian_triggered, _guardian_fired, rm.progress])

	# ⑥ 满后锁定, 不再累计
	tot += 1
	var locked: float = rm.progress
	rm._on_enemy_killed(mk.call(&"trash"), null, 0, Vector3.ZERO)
	rm.add_time_ball()
	if absf(rm.progress - locked) < 0.01:
		ok += 1; print("OK⑥ 满后锁定不再累计 (=%.0f)" % rm.progress)
	else:
		printerr("FAIL⑥ 满后仍变 %.1f->%.1f" % [locked, rm.progress])

	print("==== verify_rift_progress: %d/%d 判定通过 ====" % [ok, tot])
	rm.free()
	quit(0 if ok == tot else 1)
