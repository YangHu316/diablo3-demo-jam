extends RefCounted

# 可走区域判定(验证V1):基于 关卡/level_trace.json 的描迹轮廓环。
# 奇偶规则判定点是否在可走区内 + 到边界最小距离(clearance)。
# 供敌人生成器/装饰摆放做「生成范围不得越出墙面」的硬约束。

const SCENE_WALK_PATH := "res://验证V1-Fable5自主开发/tools/scene_walk.json"   # 场景几何导出(用户编辑后重建时更新,优先)
const TRACE_PATH := "res://关卡/level_trace.json"                              # 平面图描迹(兜底)

static var _loops: Array = []      # Array[PackedVector2Array]
static var _loaded := false

static func _ensure() -> bool:
	if _loaded:
		return not _loops.is_empty()
	_loaded = true
	var f := FileAccess.open(ProjectSettings.globalize_path(SCENE_WALK_PATH), FileAccess.READ)
	if f == null:
		f = FileAccess.open(ProjectSettings.globalize_path(TRACE_PATH), FileAccess.READ)
	if f == null:
		push_error("WalkableArea: 可走区域数据缺失")
		return false
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary) or not d.has("loops"):
		return false
	for lp in d["loops"]:
		var pv := PackedVector2Array()
		for p in lp["pts"]:
			pv.append(Vector2(p[0], p[1]))
		_loops.append(pv)
	return true

# 点是否在可走区(世界 XZ 坐标;所有环统一奇偶,洞环内=false)
static func is_walkable(p: Vector2) -> bool:
	if not _ensure():
		return false
	var crossings := 0
	for pv in _loops:
		var n: int = (pv as PackedVector2Array).size()
		for i in n:
			var a: Vector2 = pv[i]
			var b: Vector2 = pv[(i + 1) % n]
			if (a.y <= p.y) == (b.y <= p.y):
				continue
			var x: float = a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if x > p.x:
				crossings += 1
	return (crossings & 1) == 1

# 到最近边界(墙面/洞缘)的距离
static func clearance(p: Vector2) -> float:
	if not _ensure():
		return 0.0
	var best := INF
	for pv in _loops:
		var n: int = (pv as PackedVector2Array).size()
		for i in n:
			var a: Vector2 = pv[i]
			var b: Vector2 = pv[(i + 1) % n]
			var d := p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b))
			if d < best:
				best = d
	return best

# 在圆内采样一个合法点(可走 + 距边界≥min_clear);失败逐步向圆心收缩,最后回退圆心
static func sample_in_disc(rng: RandomNumberGenerator, center: Vector2, radius: float, min_clear: float) -> Vector2:
	for attempt in 24:
		var shrink := 1.0 - float(attempt) * 0.03
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * radius * shrink
		var p := center + Vector2(cos(ang), sin(ang)) * r
		if is_walkable(p) and clearance(p) >= min_clear:
			return p
	return center
