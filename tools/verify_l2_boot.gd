extends SceneTree
# verify_l2_boot.gd — 校验启动场景 level_02_play.tscn 在删除 L1 后仍可加载,且不再引用 L1。
func _init() -> void:
	var ok := 0
	var tot := 0
	# ① 启动场景可加载
	tot += 1
	var ps := load("res://scenes/levels/level_02_play.tscn")
	if ps != null:
		ok += 1; print("OK① level_02_play.tscn 加载成功")
	else:
		printerr("FAIL① level_02_play.tscn 加载失败")
	# ② 可实例化(依赖链完整)
	tot += 1
	if ps != null:
		var inst = ps.instantiate()
		if inst != null:
			ok += 1; print("OK② level_02_play 实例化成功")
			inst.free()
		else:
			printerr("FAIL② 实例化返回 null")
	else:
		printerr("FAIL② 跳过(场景未加载)")
	# ③ L1 场景已删除
	tot += 1
	if not FileAccess.file_exists("res://scenes/levels/level_01_play.tscn") and not FileAccess.file_exists("res://scenes/levels/level_01_gate.tscn"):
		ok += 1; print("OK③ L1 场景文件已移除")
	else:
		printerr("FAIL③ L1 场景文件仍存在")
	print("==== verify_l2_boot: %d/%d 判定通过 ====" % [ok, tot])
	quit(0 if ok == tot else 1)
