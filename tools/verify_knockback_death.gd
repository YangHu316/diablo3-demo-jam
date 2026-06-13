extends SceneTree

# 回归验证: 击退期间本体被销毁/缩放归零时, KnockbackComponent 不再对退化基底
# 调 move_and_slide (det==0 刷屏)。复现修复前的崩溃路径并确认已止血。
# Run headless:
#   godot --headless --path . --script res://tools/verify_knockback_death.gd

var _fail := 0

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  - ", msg)
	else:
		_fail += 1
		print("  FAIL- ", msg)

func _init() -> void:
	var root := get_root()

	# 模拟敌人本体 (CharacterBody3D) + KnockbackComponent 子节点。
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	shape.shape = cap
	body.add_child(shape)
	root.add_child(body)

	var KB = load("res://scripts/components/knockback_component.gd")
	var kb = KB.new()
	body.add_child(kb)
	# SceneTree 脚本里 add_child 不会同步触发 _ready, 手动注入 _body
	# (等价于 _ready 中 _body = get_parent())。
	kb._body = body

	print("\n=== 判定①: 击退正常启动 ===")
	kb.apply(Vector3(1, 0, 0), 2.5, 0.4)
	_ck(kb.is_active(), "apply 后 is_active() == true")
	_ck(kb._remaining > 0.0 and kb._initial_speed > 0.0, "初速/剩余时间已设置")

	print("\n=== 判定②: 本体标记销毁 -> 击退自动停止 (修复点) ===")
	# 模拟敌人 _die(): 标记 queue_free + 缩放归零动画把 scale 推向 0。
	body.queue_free()                 # is_queued_for_deletion() -> true
	body.scale = Vector3(0.001, 0.001, 0.001)   # 退化基底 (det≈0)
	# 修复前: 这一帧 kb._physics_process 会 move_and_slide -> det==0 刷屏。
	# 修复后: 检测到 is_queued_for_deletion() 立即 cancel(), 不再 move_and_slide。
	kb._physics_process(0.016)
	_ck(not kb.is_active(), "本体待销毁后, 击退已自动取消 (is_active==false)")

	# 再推进多帧, 确认不会复活/继续推动。
	for i in range(5):
		kb._physics_process(0.016)
	_ck(not kb.is_active(), "后续帧保持停止")

	print("\n========================================")
	if _fail == 0:
		print("VERIFY OK - 击退/死亡 det==0 回归全部通过")
	else:
		print("VERIFY FAIL - %d 项未通过" % _fail)
	quit()
