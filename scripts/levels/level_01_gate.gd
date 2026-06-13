@tool
extends Node3D

# Level 01 —「新崔斯特姆·城门」白盒(M1 协防城门).
# @tool:地面/墙体/地标在编辑器里也会构建(可见预览);navmesh/刷怪触发/出口在 .tscn 里手摆,本就可见。
# 程序化搭建地面/墙体/地标,使 .tscn 保持精简、易调参、可 headless 校验。
# 几何全部 collision_layer=4(玩家 mask=4 / 敌人 mask=5 与之碰撞)。
# 敌人寻路走 .tscn 里手工编排的 NavigationMesh(NavigationRegion3D),与本几何独立。
#
# 房间矩形(X 西→东 / Z 南(+)→北(−),玩家面朝 −Z 北):
#   A 入口广场 X[-7,7]  Z[16,26]   B 主街 X[-4,4] Z[6,16]
#   C 资源支廊 X[4,11]  Z[6,14]    D 城门广场(尸潮) X[-9,9] Z[-10,6]
#   E 休整出口 X[-5,5]  Z[-18,-10]
# 环路:B→D 直达 与 B→C→D 绕行 两条路汇于城门广场。

const PLAYER_SPAWN := Vector3(0, 0, 24)   # 广场南端,面朝 −Z

func _ready() -> void:
	# 清掉上一次程序生成的几何(地面/墙/地标盒/篝火光),保留 .tscn 手摆节点
	for c in get_children():
		if c is StaticBody3D or c is MeshInstance3D or c is OmniLight3D:
			c.free()
	_build_floors()
	_build_walls()
	_build_landmarks()

func _mat(c: Color, emissive: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	if emissive:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 0.6
	return m

func _box(pos: Vector3, size: Vector3, mat: StandardMaterial3D, collision: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	body.position = pos
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)
	if collision:
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
	return body

func _cyl(pos: Vector3, radius: float, h: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = h
	cm.material = mat
	mi.mesh = cm
	mi.position = pos
	add_child(mi)
	return mi

func _build_floors() -> void:
	var mat := _mat(Color(0.19, 0.19, 0.21))
	# [cx, cz, sx, sz]  顶面 y=0(厚 0.4,中心 y=-0.2)
	var floors := [
		[0.0, 21.0, 14.0, 10.0],   # A
		[0.0, 11.0, 8.0, 10.0],    # B
		[7.5, 10.0, 7.0, 8.0],     # C
		[0.0, -2.0, 18.0, 16.0],   # D
		[0.0, -14.0, 10.0, 8.0],   # E
	]
	for f in floors:
		_box(Vector3(f[0], -0.2, f[1]), Vector3(f[2], 0.4, f[3]), mat, true)

func _build_walls() -> void:
	var mat := _mat(Color(0.30, 0.28, 0.26))
	# [cx, cz, sx, sz]  墙高 3(中心 y=1.5),厚 0.5
	var walls := [
		# A 广场:北边留 X[-4,4] 通道到 B
		[-5.5, 16.0, 3.0, 0.5], [5.5, 16.0, 3.0, 0.5], [0.0, 26.0, 14.0, 0.5],
		[7.0, 21.0, 0.5, 10.0], [-7.0, 21.0, 0.5, 10.0],
		# B 主街:西墙 + 东墙仅 Z[14,16](Z[6,14] 通 C)
		[-4.0, 11.0, 0.5, 10.0], [4.0, 15.0, 0.5, 2.0],
		# C 支廊:东/北墙 + 南墙仅 X[9,11](X[4,9] 通 D)
		[11.0, 10.0, 0.5, 8.0], [7.5, 14.0, 7.0, 0.5], [10.0, 6.0, 2.0, 0.5],
		# D 城门广场:东西墙 + 南墙留 X[-4,9] + 北墙留 X[-5,5] 通 E
		[-9.0, -2.0, 0.5, 16.0], [9.0, -2.0, 0.5, 16.0], [-6.5, 6.0, 5.0, 0.5],
		[-7.0, -10.0, 4.0, 0.5], [7.0, -10.0, 4.0, 0.5],
		# E 休整:东西墙 + 北墙留 X[-1,1] 出口
		[-5.0, -14.0, 0.5, 8.0], [5.0, -14.0, 0.5, 8.0],
		[-3.0, -18.0, 4.0, 0.5], [3.0, -18.0, 4.0, 0.5],
	]
	for w in walls:
		_box(Vector3(w[0], 1.5, w[1]), Vector3(w[2], 3.0, w[3]), mat, true)

func _build_landmarks() -> void:
	# 广场地标:破井(朝向锚点)
	_box(Vector3(5, 0.6, 21), Vector3(1.6, 1.2, 1.6), _mat(Color(0.40, 0.38, 0.34)), true)
	# 城门(广场南入口 Z=6):两根门柱 + 门楣 —— 全关最强地标,远处可见牵引前进
	var gate := _mat(Color(0.45, 0.40, 0.32))
	_box(Vector3(-4, 2.0, 6), Vector3(0.9, 4.0, 0.9), gate, true)
	_box(Vector3(4, 2.0, 6), Vector3(0.9, 4.0, 0.9), gate, true)
	_box(Vector3(0, 3.7, 6), Vector3(9.0, 0.6, 0.9), gate, false)
	# 资源点:支廊宝箱(首把蓝弓脚本掉落位)
	_box(Vector3(8, 0.4, 10), Vector3(1.2, 0.8, 0.9), _mat(Color(0.85, 0.62, 0.15), true), true)
	# 休整点:篝火(安全区/治疗锚点)+ 暖光
	_cyl(Vector3(0, 0.2, -13), 0.8, 0.4, _mat(Color(0.25, 0.2, 0.18)))
	_cyl(Vector3(0, 0.7, -13), 0.35, 0.7, _mat(Color(1.0, 0.5, 0.12), true))
	var fire := OmniLight3D.new()
	fire.position = Vector3(0, 1.2, -13)
	fire.light_color = Color(1.0, 0.6, 0.25)
	fire.light_energy = 2.5
	fire.omni_range = 9.0
	add_child(fire)
	# 出口传送门(北墙缺口,可穿行)
	_box(Vector3(0, 1.25, -18), Vector3(1.8, 2.5, 0.25), _mat(Color(0.25, 0.55, 1.0), true), false)
	# 大教堂剪影(L2 方向地标,牵引玩家朝出口前进)
	_box(Vector3(0, 6.0, -27), Vector3(8.0, 12.0, 3.0), _mat(Color(0.12, 0.12, 0.15)), false)
