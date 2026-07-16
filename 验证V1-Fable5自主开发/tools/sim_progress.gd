extends Node

# 验证V1 · 进度完整性仿真:加载可玩场景 → 全灭敌人 → 结算全部进度球
# 验证:计数链路无漏(每杀都进 RiftManager) + 总进度容量满足「八成击杀≈100%」口径。
# Run: Godot --headless --path . res://验证V1-Fable5自主开发/tools/sim_progress.tscn

const PLAY := "res://验证V1-Fable5自主开发/scenes/level_03_dh_play.tscn"
const OFFICIAL_GOAL := 106.0

func _ready() -> void:
	var ps := load(PLAY) as PackedScene
	add_child(ps.instantiate())
	await get_tree().create_timer(2.0).timeout
	var rm := get_node("/root/RiftManager")
	rm.set("goal", 999999.0)   # 防触发守门人切场,只测容量
	var enemies := get_tree().get_nodes_in_group("enemies")
	var total := enemies.size()
	print("[sim] 敌人总数 = ", total)
	for e in enemies:
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(9999999, null)
	await get_tree().create_timer(3.0).timeout   # 等死亡流程/自爆链/球生成
	var balls: Array = []
	_find_balls(get_tree().root, balls)
	for b in balls:
		rm.add_progress_ball(b.get("pct"))
	var prog: float = rm.get("progress")
	var kills: int = rm.get("kill_count")
	print("[sim] 击杀计数 = ", kills, " / ", total, " (漏计 ", total - kills, ")")
	print("[sim] 进度球 = ", balls.size(), " 颗")
	print("[sim] 全灭总进度 = %.1f / 正式goal %.0f = %.1f%%" % [prog, OFFICIAL_GOAL, prog / OFFICIAL_GOAL * 100.0])
	print("[sim] 八成击杀口径(仅小怪权重×0.8) = %.1f%%" % ((prog - balls.size() * 0.0375 * OFFICIAL_GOAL) * 0.8 / OFFICIAL_GOAL * 100.0))
	print("[sim] ", "SIM OK" if kills == total and prog >= OFFICIAL_GOAL * 1.2 else "SIM WARN")
	get_tree().quit(0)

func _find_balls(n: Node, out: Array) -> void:
	for c in n.get_children():
		var s: Script = c.get_script() as Script
		if s != null and String(s.resource_path).contains("progress_ball"):
			out.append(c)
		_find_balls(c, out)
