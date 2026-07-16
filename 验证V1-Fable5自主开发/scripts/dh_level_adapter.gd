extends Node3D

# 验证V1 · 小地图/战争迷雾适配器(挂在美术副本场景根)
# minimap_panel.gd / tab_map.gd 的数据契约: level 组节点提供 WALK / SCALE / LANDMARKS。
# 本关几何为有机多边形(scene_walk.json),运行时按 1m 行扫描线转成矩形条带供小地图绘制;
# 战争迷雾与玩家箭头由 minimap_panel 自带逻辑处理。

const WALK_JSON := "res://验证V1-Fable5自主开发/tools/scene_walk.json"

var WALK: Array = []
var SCALE: float = 1.0
var LANDMARKS: Array = [
	[44.3, -33.9, "portal_out"],   # 入口传送门(金)
	[-42.1, 42.6, "boss_pillar"],  # 红门(红)
]

func _ready() -> void:
	add_to_group("level")
	_build_walk_rects()

func _build_walk_rects() -> void:
	var f := FileAccess.open(ProjectSettings.globalize_path(WALK_JSON), FileAccess.READ)
	if f == null:
		push_warning("dh_level_adapter: 缺 scene_walk.json,小地图无地形")
		return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary) or not d.has("loops"):
		return
	var loops: Array = []
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for lp in d["loops"]:
		var pv := PackedVector2Array()
		for p in lp["pts"]:
			var v := Vector2(p[0], p[1])
			pv.append(v)
			mn = mn.min(v)
			mx = mx.max(v)
		loops.append(pv)
	# 行扫描线 → 水平矩形条带(1m 高;奇偶规则,洞环自然扣除)
	var row := 1.0
	var z := mn.y
	while z < mx.y:
		var zc := z + row * 0.5
		var xs: Array[float] = []
		for pv in loops:
			var n: int = (pv as PackedVector2Array).size()
			for i in n:
				var a: Vector2 = pv[i]
				var b: Vector2 = pv[(i + 1) % n]
				if (a.y <= zc) == (b.y <= zc):
					continue
				xs.append(a.x + (zc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var i2 := 0
		while i2 + 1 < xs.size():
			if xs[i2 + 1] - xs[i2] > 0.4:
				WALK.append([xs[i2], xs[i2 + 1], z, z + row])
			i2 += 2
		z += row
