extends Node3D

# 时间球 in-game 校验(真实场景树, autoload 生效).
# 跑: <console.exe> --headless --path . res://tools/itest_time_orb.tscn --quit-after 200
# 校验:
#   ⓪ RiftManager 暴露 get_time_limit/get_time_remaining, 初始剩余≈总时
#   ① 推进时间后剩余递减
#   ② HUD 时间球节点建好, _refresh_time_orb 后 fill.anchor_top 与剩余比例一致
#   ③ MM:SS 文字格式正确
#   ④ reset_rift 后剩余回满

const HUD := preload("res://scripts/ui/hud.gd")

var _fails: int = 0
var _phase: int = 0
var _hud: CanvasLayer = null
var _t0_remaining: float = 0.0

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

	# 建 HUD(真实脚本), 触发 _build_ui → 时间球节点.
	_hud = HUD.new()
	add_child(_hud)
	# 等一帧让 _ready/_build_ui 完成.
	await get_tree().process_frame
	_check(_hud.get("_time_orb_fill") != null, "① 时间球 fill 节点建好")
	_check(_hud.get("_time_orb_label") != null, "① 时间球 label 节点建好")

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
		var fill: ColorRect = _hud.get("_time_orb_fill")
		var ratio: float = clampf(r / 120.0, 0.0, 1.0)
		var expect_top: float = 1.0 - ratio
		_check(absf(fill.anchor_top - expect_top) < 0.02,
			"② fill.anchor_top=%.3f ≈ 1-ratio=%.3f" % [fill.anchor_top, expect_top])
		var lbl: Label = _hud.get("_time_orb_label")
		var secs: int = int(ceil(r))
		var expect_txt: String = "%d:%02d" % [secs / 60, secs % 60]
		_check(lbl.text == expect_txt, "③ MM:SS 文字=%s (期望%s)" % [lbl.text, expect_txt])
	elif _phase == 40:
		# reset 回满.
		rm.reset_rift()
		var r2: float = float(rm.get_time_remaining())
		_check(r2 > 119.0, "④ reset 后剩余回满 (=%.2f)" % r2)
		_finish()

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [OK] ", msg)
	else:
		print("  [FAIL] ", msg)
		_fails += 1

func _finish() -> void:
	if _fails == 0:
		print("VERIFY OK — 时间球全部通过")
	else:
		print("VERIFY FAIL — %d 项未通过" % _fails)
	get_tree().quit(_fails)
