extends SceneTree

# Headless 验证: 功能塔 TowerBuffManager 状态机(互斥/计时/CD + 伤害乘区注入).
# 运行: godot --headless --path . --script res://tools/verify_tower_buff.gd
#
# 与 verify_boss_drop 同口径: 手动实例化脚本, 不挂树/不依赖 autoload, 全程同步, 末尾 quit().
# DataTables 手动注入到 manager (set_data_tables); 移速乘区因无树无玩家自动跳过(不崩即可).

const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")

func _init() -> void:
	var fails: int = 0
	var checks: int = 0

	var dt = load("res://scripts/autoload/data_tables.gd").new()
	dt._load_tower_buffs()
	var tbm = load("res://scripts/autoload/tower_buff_manager.gd").new()
	tbm.set_data_tables(dt)

	# 判定①: CSV 加载出 2 个塔, 数值正确.
	checks += 1
	var dmg_def: Dictionary = dt.get_tower_buff("damage_tower")
	var spd_def: Dictionary = dt.get_tower_buff("speed_tower")
	if dmg_def.is_empty() or spd_def.is_empty():
		push_error("FAIL①: tower_buffs.csv 未加载出 damage/speed_tower"); fails += 1
	elif abs(float(dmg_def["magnitude"]) - 0.30) > 0.001 or abs(float(spd_def["magnitude"]) - 0.35) > 0.001:
		push_error("FAIL①: 加成幅度不符"); fails += 1
	else:
		print("OK① CSV 加载 2 塔: 伤害+%.0f%%/加速+%.0f%%" % [float(dmg_def["magnitude"])*100, float(spd_def["magnitude"])*100])

	# 判定②: 激活伤害塔 → tower_dmg_mult=1.30, 进 CD.
	checks += 1
	DamageCalculator.tower_dmg_mult = 1.0
	var ok_act: bool = tbm.activate(&"damage_tower")
	if not ok_act or abs(DamageCalculator.tower_dmg_mult - 1.30) > 0.001 or tbm.active_tower_id() != &"damage_tower":
		push_error("FAIL②: 激活伤害塔失败/乘区不符 mult=%f" % DamageCalculator.tower_dmg_mult); fails += 1
	else:
		print("OK② 伤害塔激活 → tower_dmg_mult=1.30, 进 CD")

	# 判定③: 互斥替换 — 激活加速塔, 伤害乘区还原 1.0, 当前=speed_tower.
	checks += 1
	var ok_swap: bool = tbm.activate(&"speed_tower")
	if not ok_swap or abs(DamageCalculator.tower_dmg_mult - 1.0) > 0.001 or tbm.active_tower_id() != &"speed_tower":
		push_error("FAIL③: 互斥替换不符 mult=%f id=%s" % [DamageCalculator.tower_dmg_mult, tbm.active_tower_id()]); fails += 1
	else:
		print("OK③ 互斥替换: 激活加速塔 → 伤害乘区还原 1.0, 当前=speed_tower")

	# 判定④: 同塔 CD 内再激活失败.
	checks += 1
	if tbm.activate(&"speed_tower"):
		push_error("FAIL④: CD 内不应可再激活"); fails += 1
	else:
		print("OK④ CD 内再激活被拒")

	# 判定⑤: 持续到期 → buff 自动清除 (步进 9s, speed duration=8s).
	checks += 1
	for i in range(18):
		tbm._process(0.5)
	if tbm.is_active():
		push_error("FAIL⑤: 超过持续时间 buff 未清除"); fails += 1
	else:
		print("OK⑤ 持续到期 buff 自动清除")

	# 判定⑥: CD 到期 → 塔可再次激活 (再步进 12s, cooldown=20s).
	checks += 1
	for i in range(24):
		tbm._process(0.5)
	if not (tbm.is_tower_ready(&"speed_tower") and tbm.activate(&"speed_tower")):
		push_error("FAIL⑥: CD 到期后塔应可再激活 cd=%f" % tbm.cooldown_remaining(&"speed_tower")); fails += 1
	else:
		print("OK⑥ CD 到期塔重新可激活")

	print("\n==== verify_tower_buff: %d/%d 判定通过 ====" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)
