extends Node3D

# 时间标签 in-game 校验(真实场景树, autoload 生效).
# 跑: <console.exe> --headless --path . res://tools/itest_time_orb.tscn --quit-after 200
# 校验:
#   ⓪ RiftManager 暴露 get_time_limit/get_time_remaining, 初始剩余≈总时
#   ① HUD 时间标签节点(_time_label)建好
#   ② 推进时间后剩余递减, _refresh_time_orb 后 MM:SS 文字与剩余一致
#   ③ 计时冻结(快照 _frozen_clear_sec)后剩余不再变化(进 boss 关行为, 完整路径见 verify_rift_timer_freeze)
#   ④ reset_rift 后剩余回满

const HUD_SCENE := preload("res://scenes/ui/hud.tscn")

var _fails: int = 0
var _phase: int = 0
var _hud: CanvasLayer = null
var _t0_remaining: float = 0.0
var _frozen_remaining: float = 0.0

func _ready() -> void:
	var rm: Node = get_node_or_null("/root/RiftManager")
	_check(rm != null, "RiftManager autoload 存在")
	_check(rm.has_method("get_time_limit"), "RiftManager.get_time_limit 存在")
	_check(rm.has_method("get_time_remaining"), "RiftManager.get_time_remaining 存在")
	if rm == null:
		_finish()
		return
	rm.reset_rift()
	var limit: float = float(rm.get_time_limit())
	_check(absf(limit - 120.0) < 0.001, "时限=120s (实=%.1f)" % limit)
	_t0_remaining = float(rm.get_time_remaining())
	_check(_t0_remaining > limit - 1.0, "⓪ 初始剩余≈总时 (=%.2f)" % _t0_remaining)

	# 实例化真实 HUD 场景(节点引用来自 hud.tscn, 须用场景而非裸脚本).
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	# 等一帧让 _ready 完成.
	await get_tree().process_frame
	_check(_hud.get("_time_label") != null, "① 时间标签 _time_label 节点建好")

func _physics_process(_d: float) -> void:
	var rm: Node = get_node_or_null("/root/RiftManager")
	if rm == null:
		_finish()
		return
	_phase += 1
	if _phase == 30:
		# 已过约 0.5s, 剩余应略减.
		var r: float = float(rm.get_time_remaining())
		_check(r < _t0_remaining, "② 时间推进后剩余递减 (%.2f→%.2f)" % [_t0_remaining, r])
		_hud.call("_refresh_time_orb")
		var lbl: Label = _hud.get("_time_label")
		var secs: int = int(ceil(r))
		var expect_txt: String = "%d:%02d" % [secs / 60, secs % 60]
		_check(lbl != null and lbl.text == expect_txt,
			"② MM:SS 文字=%s (期望%s)" % [lbl.text if lbl != null else "<null>", expect_txt])
	elif _phase == 35:
		# 模拟"进守门人=切 boss 关"的计时冻结: 直接快照已用时到 _frozen_clear_sec.
		# (不调 _trigger_guardian, 因其会 call_deferred 切到 boss 场景, 拆掉本测试场景树;
		#  冻结的完整路径校验见 verify_rift_timer_freeze.gd)
		rm.set("_frozen_clear_sec", rm.get_clear_time())
		_frozen_remaining = float(rm.get_time_remaining())
	elif _phase == 70:
		# 冻结后又过了约 0.5s, 剩余不应再变.
		var rf: float = float(rm.get_time_remaining())
		_check(absf(rf - _frozen_remaining) < 0.01,
			"③ 冻结后计时静止, 剩余不变 (%.3f→%.3f)" % [_frozen_remaining, rf])
	elif _phase == 80:
		# reset 回满, 并解除冻结.
		rm.reset_rift()
		var r2: float = float(rm.get_time_remaining())
		_check(r2 > 119.0, "④ reset 后剩余回满且解冻 (=%.2f)" % r2)
		_finish()

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		print("  [FAIL] ", msg)
		_fails += 1

func _finish() -> void:
	if _fails == 0:
		print("VERIFY OK — 时间标签全部通过")
	else:
		print("VERIFY FAIL — %d 项未通过" % _fails)
	get_tree().quit(_fails)
