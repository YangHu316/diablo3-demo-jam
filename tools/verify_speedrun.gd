extends SceneTree
# verify_speedrun.gd — 校验速通 override (数值表/测试-1分钟速通):
#   ① 默认无 override: speedrun=false, goal=106 (正式值零污染)
#   ② _apply_overrides(启用=1,进度条目标=15,守门人HP=4000) → goal=15 / _sr_guardian_hp=4000 / speedrun=true
#   ③ 启用=0 → 忽略 (speedrun=false, goal 不变)
#   ④ 缺字段时回落默认 (只给启用=1 → goal 保持 106, hp=0)
#   ⑤ goal 改 15 后进度逻辑生效: 喂 15 白怪即满 + 触发 guardian
#   ⑥ 守门人 HP 覆写: 造带 monster_id=butcher + current_health 的假怪, 走 _try_apply_guardian_hp → current_health=4000
#   ⑦ speedrun_test.csv 文件存在且 启用=1 (表本身就是开启态)

func _init() -> void:
	var ok := 0
	var tot := 0
	var rm_script := load("res://scripts/autoload/rift_manager.gd")

	# ① 默认无 override
	tot += 1
	var rm: Node = rm_script.new()
	if rm.speedrun == false and absf(rm.goal - 106.0) < 0.01:
		ok += 1; print("OK① 默认 speedrun=false goal=%.0f (零污染)" % rm.goal)
	else:
		printerr("FAIL① speedrun=%s goal=%.1f" % [rm.speedrun, rm.goal])
	rm.free()

	# ② 套用速通 override
	tot += 1
	rm = rm_script.new()
	rm._apply_overrides({"启用": "1", "进度条目标": "15", "守门人HP": "4000", "守门人ATK": "40"})
	if rm.speedrun == true and absf(rm.goal - 15.0) < 0.01 and rm._sr_guardian_hp == 4000:
		ok += 1; print("OK② override 套用: goal=%.0f hp=%d speedrun=%s" % [rm.goal, rm._sr_guardian_hp, rm.speedrun])
	else:
		printerr("FAIL② goal=%.1f hp=%d speedrun=%s" % [rm.goal, rm._sr_guardian_hp, rm.speedrun])
	rm.free()

	# ③ 启用=0 → 忽略
	tot += 1
	rm = rm_script.new()
	rm._apply_overrides({"启用": "0", "进度条目标": "15", "守门人HP": "4000"})
	if rm.speedrun == false and absf(rm.goal - 106.0) < 0.01 and rm._sr_guardian_hp == 0:
		ok += 1; print("OK③ 启用=0 忽略 (goal=%.0f speedrun=%s)" % [rm.goal, rm.speedrun])
	else:
		printerr("FAIL③ goal=%.1f speedrun=%s hp=%d" % [rm.goal, rm.speedrun, rm._sr_guardian_hp])
	rm.free()

	# ④ 缺字段回落默认
	tot += 1
	rm = rm_script.new()
	rm._apply_overrides({"启用": "1"})
	if rm.speedrun == true and absf(rm.goal - 106.0) < 0.01 and rm._sr_guardian_hp == 0:
		ok += 1; print("OK④ 缺字段回落 (goal=%.0f hp=%d)" % [rm.goal, rm._sr_guardian_hp])
	else:
		printerr("FAIL④ goal=%.1f hp=%d" % [rm.goal, rm._sr_guardian_hp])
	rm.free()

	# ⑤ goal=15 后进度逻辑生效
	tot += 1
	rm = rm_script.new()
	rm._apply_overrides({"启用": "1", "进度条目标": "15", "守门人HP": "4000"})
	var fired := [0]
	rm.guardian_ready.connect(func(): fired[0] += 1)
	var mk := func(mid: StringName) -> Node:
		var n := Node.new()
		n.set_meta("monster_id", mid)
		return n
	for i in range(15):
		rm._on_enemy_killed(mk.call(&"trash"), null, 0, Vector3.ZERO)
	if rm.guardian_triggered and fired[0] == 1 and rm.progress >= 15.0:
		ok += 1; print("OK⑤ goal=15 喂15白怪即满+触发 guardian (progress=%.0f)" % rm.progress)
	else:
		printerr("FAIL⑤ triggered=%s fired=%d progress=%.1f" % [rm.guardian_triggered, fired[0], rm.progress])
	rm.free()

	# ⑥ 守门人 HP 覆写 (_try_apply_guardian_hp)
	tot += 1
	rm = rm_script.new()
	rm._apply_overrides({"启用": "1", "进度条目标": "15", "守门人HP": "4000"})
	var guard := FakeGuardian.new()
	guard.set_meta("monster_id", &"butcher")
	rm._try_apply_guardian_hp(guard)
	var applied: bool = guard.get_meta("_sr_hp_applied", false)
	if guard.current_health == 4000 and applied:
		ok += 1; print("OK⑥ 守门人进场 current_health 覆写为 %d" % guard.current_health)
	else:
		printerr("FAIL⑥ current_health=%d applied=%s" % [guard.current_health, applied])
	# 非守门人不被覆写
	tot += 1
	var trash := FakeGuardian.new()
	trash.set_meta("monster_id", &"trash")
	rm._try_apply_guardian_hp(trash)
	if trash.current_health == 24000 and not trash.get_meta("_sr_hp_applied", false):
		ok += 1; print("OK⑥b 非守门人 (trash) 不被覆写 (=%d)" % trash.current_health)
	else:
		printerr("FAIL⑥b trash current_health=%d" % trash.current_health)
	guard.free()
	trash.free()
	rm.free()

	# ⑦ CSV 文件存在 + 启用=1
	tot += 1
	var csv := "res://数值表/测试-1分钟速通/speedrun_test.csv"
	if FileAccess.file_exists(csv):
		var ov: Dictionary = {}
		var f := FileAccess.open(csv, FileAccess.READ)
		f.get_line()
		while not f.eof_reached():
			var cols := f.get_line().split(",")
			if cols.size() >= 2 and not cols[0].is_empty():
				ov[cols[0]] = cols[1]
		f.close()
		if String(ov.get("启用", "0")) == "1" and String(ov.get("进度条目标", "")) == "5" and String(ov.get("守门人HP", "")) == "1500":
			ok += 1; print("OK⑦ CSV 存在·启用=1·目标=5·守门人HP=1500 (20s体验版)")
		else:
			printerr("FAIL⑦ CSV 字段不符: %s" % ov)
	else:
		printerr("FAIL⑦ 缺 %s" % csv)

	print("==== verify_speedrun: %d/%d 判定通过 ====" % [ok, tot])
	quit(0 if ok == tot else 1)


# 假守门人: 模拟 butcher.gd 的 current_health 实例字段 (默认正式 24000).
class FakeGuardian extends Node:
	var current_health: int = 24000
