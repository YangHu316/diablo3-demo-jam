extends SceneTree
# verify_elite_progress_ball.gd — 校验精英进度球系统 (数据层 + RiftManager API):
#   数据层 (DataTables.elites.csv):
#     ① elite_blue 进度球数 = 1
#     ② champion_yellow 进度球数 = 2
#     ③ 每球进度% 解析为小数 = 0.05 (蓝/黄一致)
#     ④ 非精英 id 球数 = 0 (兜底)
#   进度 API (RiftManager.add_progress_ball):
#     ⑤ add_progress_ball(0.05) -> progress ≈ 0.05×goal ≈ 5.3
#     ⑥ 蓝精英满球 (1 球 × 5%) -> progress ≈ 5.3
#     ⑦ 黄首领满球 (2 球 × 5%) -> progress ≈ 10.6
#     ⑧ 精英击杀本身不直接加权 (杀蓝+黄, progress 仍=0, kill_count=2)

func _init() -> void:
	var ok := 0
	var tot := 0

	# ── 数据层: 直接 new DataTables 读 elites.csv ──
	var dt_script := load("res://scripts/autoload/data_tables.gd")
	var dt: Node = dt_script.new()
	dt._load_elites()   # 仅跑精英表加载 (不触发其它 .tres, 隔离)

	# ① elite_blue 球数 = 1
	tot += 1
	var blue_balls: int = dt.get_elite_ball_count("elite_blue")
	if blue_balls == 1:
		ok += 1; print("OK① elite_blue 进度球数 = %d" % blue_balls)
	else:
		printerr("FAIL① 期望 elite_blue 球数=1 实得 %d" % blue_balls)

	# ② champion_yellow 球数 = 2
	tot += 1
	var yellow_balls: int = dt.get_elite_ball_count("champion_yellow")
	if yellow_balls == 2:
		ok += 1; print("OK② champion_yellow 进度球数 = %d" % yellow_balls)
	else:
		printerr("FAIL② 期望 champion_yellow 球数=2 实得 %d" % yellow_balls)

	# ③ 每球进度% = 0.05 (蓝/黄一致)
	tot += 1
	var blue_pct: float = dt.get_elite_per_ball_pct("elite_blue")
	var yellow_pct: float = dt.get_elite_per_ball_pct("champion_yellow")
	if absf(blue_pct - 0.05) < 0.0001 and absf(yellow_pct - 0.05) < 0.0001:
		ok += 1; print("OK③ 每球进度%% 解析 = %.3f (蓝/黄一致)" % blue_pct)
	else:
		printerr("FAIL③ 期望 0.05 实得 蓝=%.3f 黄=%.3f" % [blue_pct, yellow_pct])

	# ④ 非精英 id 球数 = 0
	tot += 1
	var trash_balls: int = dt.get_elite_ball_count("trash")
	if trash_balls == 0:
		ok += 1; print("OK④ 非精英(trash) 球数 = %d" % trash_balls)
	else:
		printerr("FAIL④ 期望 trash 球数=0 实得 %d" % trash_balls)

	dt.free()

	# ── 进度 API: new RiftManager 直接调 ──
	var rm_script := load("res://scripts/autoload/rift_manager.gd")
	var rm: Node = rm_script.new()
	var goal: float = rm.goal   # 默认 = GOAL(106)

	# ⑤ add_progress_ball(0.05) -> ≈ 5.3
	tot += 1
	rm.reset_rift()
	rm.add_progress_ball(0.05)
	var expect5: float = 0.05 * goal
	if absf(rm.progress - expect5) < 0.01:
		ok += 1; print("OK⑤ add_progress_ball(0.05) -> progress=%.2f (=5%%×%.0f)" % [rm.progress, goal])
	else:
		printerr("FAIL⑤ 期望 %.2f 实得 %.2f" % [expect5, rm.progress])

	# ⑥ 蓝精英满球 (1 球) -> ≈ 5.3
	tot += 1
	rm.reset_rift()
	for i in range(1):
		rm.add_progress_ball(0.05)
	if absf(rm.progress - (1.0 * 0.05 * goal)) < 0.01:
		ok += 1; print("OK⑥ 蓝精英 1 球 -> progress=%.2f" % rm.progress)
	else:
		printerr("FAIL⑥ 期望 %.2f 实得 %.2f" % [1.0 * 0.05 * goal, rm.progress])

	# ⑦ 黄首领满球 (2 球) -> ≈ 10.6
	tot += 1
	rm.reset_rift()
	for i in range(2):
		rm.add_progress_ball(0.05)
	if absf(rm.progress - (2.0 * 0.05 * goal)) < 0.01:
		ok += 1; print("OK⑦ 黄首领 2 球 -> progress=%.2f" % rm.progress)
	else:
		printerr("FAIL⑦ 期望 %.2f 实得 %.2f" % [2.0 * 0.05 * goal, rm.progress])

	# ⑧ 精英击杀不直接加权
	tot += 1
	rm.reset_rift()
	var mk := func(mid: StringName) -> Node:
		var n := Node.new()
		n.set_meta("monster_id", mid)
		return n
	rm._on_enemy_killed(mk.call(&"elite_blue"), null, 0, Vector3.ZERO)
	rm._on_enemy_killed(mk.call(&"champion_yellow"), null, 0, Vector3.ZERO)
	if absf(rm.progress) < 0.01 and rm.kill_count == 2:
		ok += 1; print("OK⑧ 精英击杀不直接加权 (progress=%.1f kills=%d)" % [rm.progress, rm.kill_count])
	else:
		printerr("FAIL⑧ 期望 progress=0 kills=2 实得 progress=%.1f kills=%d" % [rm.progress, rm.kill_count])

	print("==== verify_elite_progress_ball: %d/%d 判定通过 ====" % [ok, tot])
	rm.free()
	quit(0 if ok == tot else 1)
