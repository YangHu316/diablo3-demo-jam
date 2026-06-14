@tool
extends Node3D

# level_02_art.gd —— L2 非黑盒美术层(角色D)。
# 读取 level_02_depths 的同一份 WALK/SCALE 平面图数据,把可走区域栅格化到 5 单位网格:
#   · 每个可走格 → 一块真 Synty 地砖(SM_Env_Tiles_01)
#   · 每条"可走↔不可走"边界 → 一段真墙(SM_Env_Wall_01_DoubleSided)
# 因为用的是同一份 WALK×SCALE 世界坐标,所以和玩法(刷怪/路径/碰撞/导航)天然对齐。
#
# 不碰队友逻辑:本脚本只加"视觉"(无碰撞);depths 的碰撞/导航/刷怪全部保留。
# 同时把兄弟 Level02Depths 的黑盒"地面+墙"网格隐藏(只隐藏视觉,保留其 StaticBody 碰撞与 NavRegion)。
#   —— 立柱/拱门/火盆/祭坛/断墙/灯光等装饰保留(用户:仅地面与墙换非黑盒)。
#
# @tool:编辑器里也生成,可直接预览对齐效果。改了 depths 的 WALK 后重载本场景即可同步。

const Depths = preload("res://scripts/levels/level_02_depths.gd")
const FLOOR_FBX = preload("res://assets/PolygonDungeon/Models/Environment/Floors/SM_Env_Tiles_01.fbx")
const WALL_FBX = preload("res://assets/PolygonDungeon/Models/Environment/Walls/SM_Env_Wall_01_DoubleSided.fbx")
const T := 5.0
const FLOOR_Y := 0.02   # 略高于 depths 黑盒地面顶(y=0),避免 z-fighting

@export var hide_depths_floor_walls: bool = true

func _ready() -> void:
	_build()

func _build() -> void:
	for c in get_children():
		c.free()
	var S: float = Depths.SCALE
	var WALK: Array = Depths.WALK
	var cells := _walkable_cells(S, WALK)
	# 地砖中心相对其 origin 的偏移(FBX 轴心在角,需校正使中心落到格心)
	var foff := _center_offset(FLOOR_FBX)
	_build_floors(cells, foff)
	_build_walls(cells)
	if hide_depths_floor_walls and not Engine.is_editor_hint():
		call_deferred("_hide_depths")
	elif hide_depths_floor_walls:
		call_deferred("_hide_depths")

# ── 可走格栅格化:格心(col*5,row*5)落在任一 WALK×S 矩形内 ──
func _walkable_cells(S: float, WALK: Array) -> Dictionary:
	var xmn := 9e9; var xmx := -9e9; var zmn := 9e9; var zmx := -9e9
	for r in WALK:
		xmn = min(xmn, r[0] * S); xmx = max(xmx, r[1] * S)
		zmn = min(zmn, r[2] * S); zmx = max(zmx, r[3] * S)
	var cells := {}
	for col in range(floori(xmn / T), ceili(xmx / T) + 1):
		for row in range(floori(zmn / T), ceili(zmx / T) + 1):
			var wx := col * T; var wz := row * T
			for r in WALK:
				if wx > r[0] * S and wx < r[1] * S and wz > r[2] * S and wz < r[3] * S:
					cells["%d_%d" % [col, row]] = Vector2i(col, row)
					break
	return cells

func _center_offset(fbx: PackedScene) -> Vector3:
	var inst: Node3D = fbx.instantiate()
	add_child(inst)
	var mn := Vector3(9e9, 9e9, 9e9); var mx := Vector3(-9e9, -9e9, -9e9)
	for m in _meshes(inst):
		var mi: MeshInstance3D = m
		var a: AABB = mi.mesh.get_aabb()
		for ci in 8:
			var wp: Vector3 = mi.global_transform * a.get_endpoint(ci)
			mn = mn.min(wp); mx = mx.max(wp)
	inst.free()
	return Vector3((mn.x + mx.x) * 0.5, mn.y, (mn.z + mx.z) * 0.5)

func _build_floors(cells: Dictionary, foff: Vector3) -> void:
	var holder := Node3D.new(); holder.name = "Floors"; add_child(holder)
	for k in cells:
		var cv: Vector2i = cells[k]
		var inst: Node3D = FLOOR_FBX.instantiate()
		holder.add_child(inst)
		# 让瓷砖中心落到格心 (col*5,row*5),底贴 FLOOR_Y
		inst.position = Vector3(cv.x * T - foff.x, FLOOR_Y - foff.y, cv.y * T - foff.z)

func _build_walls(cells: Dictionary) -> void:
	var holder := Node3D.new(); holder.name = "Walls"; add_child(holder)
	# N/S 墙沿 X(不旋转);E/W 墙沿 Z(绕 Y 90°)。墙骑在格边线上。
	var ns_basis := Basis()                       # 单位(默认沿 X)
	var ew_basis := Basis(Vector3.UP, deg_to_rad(90.0))
	for k in cells:
		var cv: Vector2i = cells[k]
		var cx := cv.x * T; var cz := cv.y * T
		if not cells.has("%d_%d" % [cv.x, cv.y - 1]):  # N (-Z)
			_wall(holder, Vector3(cx - 2.5, 0, cz - 2.5), ns_basis)
		if not cells.has("%d_%d" % [cv.x, cv.y + 1]):  # S (+Z)
			_wall(holder, Vector3(cx - 2.5, 0, cz + 2.5), ns_basis)
		if not cells.has("%d_%d" % [cv.x - 1, cv.y]):  # W (-X)
			_wall(holder, Vector3(cx - 2.5, 0, cz + 2.5), ew_basis)
		if not cells.has("%d_%d" % [cv.x + 1, cv.y]):  # E (+X)
			_wall(holder, Vector3(cx + 2.5, 0, cz + 2.5), ew_basis)

func _wall(holder: Node3D, origin: Vector3, basis: Basis) -> void:
	var inst: Node3D = WALL_FBX.instantiate()
	holder.add_child(inst)
	inst.transform = Transform3D(basis, origin)

# ── 隐藏 depths 黑盒"地面+墙"视觉(保留碰撞/导航)──
# 识别:StaticBody3D 下的 BoxMesh,薄高(墙 y≈2.4)或薄平(地面 y≈0.4)→ 隐藏 MeshInstance;
#       立柱(Cylinder)/装饰/灯光保留。
func _hide_depths() -> void:
	var depths: Node = get_parent().get_node_or_null("Level02Depths")
	if depths == null:
		return
	for body in _all(depths):
		if not (body is StaticBody3D):
			continue
		for ch in body.get_children():
			if ch is MeshInstance3D and ch.mesh is BoxMesh:
				var sz: Vector3 = (ch.mesh as BoxMesh).size
				var is_floor := sz.y <= 0.6 and sz.x > 2.0 and sz.z > 2.0
				var is_wall := sz.y >= 2.0 and (sz.x <= 0.8 or sz.z <= 0.8)
				if is_floor or is_wall:
					ch.visible = false

func _meshes(n: Node, a: Array = []) -> Array:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		a.append(n)
	for c in n.get_children():
		_meshes(c, a)
	return a

func _all(n: Node, a: Array = []) -> Array:
	a.append(n)
	for c in n.get_children():
		_all(c, a)
	return a
