extends Node

# screen_shake.gd — 屏震组件,挂在 Camera3D 子节点(命名 "ScreenShake")。
# 实现策略:直接 tween 父相机的 _shake_offset 变量(topdown_camera.gd 里已有该字段
# 并在 _process 里把它叠加到最终位置)。这样无需修改相机脚本。
#
# 调用: $Camera3D/ScreenShake.shake(0.05, 0.1)

@export var max_intensity: float = 0.5  # 安全上限,避免误传过大值

var _tween: Tween = null

func shake(intensity: float, duration: float) -> void:
	var cam: Node = get_parent()
	if cam == null or not is_instance_valid(cam):
		return
	var amp: float = clamp(intensity, 0.0, max_intensity)
	if amp <= 0.0 or duration <= 0.0:
		return

	# 中断已有抖动
	if _tween != null and _tween.is_valid():
		_tween.kill()

	# 优先走相机的 apply_shake(它能正确平滑回原位,且与 follow 协调)
	if cam.has_method("apply_shake"):
		cam.call("apply_shake", amp, duration)
		return

	# 兼容回退:相机没有 apply_shake 时,自己 tween 父节点 position
	if cam is Node3D:
		var dir: Vector3 = _random_unit_xy() * amp
		var base_pos: Vector3 = (cam as Node3D).position
		_tween = create_tween()
		_tween.tween_property(cam, "position", base_pos + dir, duration * 0.5)
		_tween.tween_property(cam, "position", base_pos, duration * 0.5)

func _random_unit_xy() -> Vector3:
	# 屏震方向只在 X/Y 平面有意义(Z 是相机进退,会让画面缩放感不舒服)
	var v: Vector3 = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0)
	if v.length() < 0.001:
		return Vector3(1, 0, 0)
	return v.normalized()
