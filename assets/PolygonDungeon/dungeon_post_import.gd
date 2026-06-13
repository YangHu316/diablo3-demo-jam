@tool
extends EditorScenePostImport

# 1) 把共享图集材质烤进每个网格的所有表面(原 FBX 引用缺失的 .psd)。
# 2) 修正比例:Synty FBX 多数用厘米建模,导入后缩小约 100 倍,
#    自动检测过小的模型放大 100 倍,已正常的跳过。
const ATLAS := preload("res://assets/PolygonDungeon/DungeonAtlas.tres")
const SCALE_FIX := 100.0
const SMALL_THRESHOLD := 0.5

func _post_import(scene: Node) -> Object:
	_apply_material(scene)
	_normalize_scale(scene)
	return scene

func _apply_material(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		var m: Mesh = node.mesh
		for i in m.get_surface_count():
			m.surface_set_material(i, ATLAS)
	for c in node.get_children():
		_apply_material(c)

func _normalize_scale(scene: Node) -> void:
	if not (scene is Node3D):
		return
	var merged: Variant = null
	for mi in _all_meshes(scene):
		var xf := _xform_to(mi, scene)
		var box: AABB = xf * mi.mesh.get_aabb()
		merged = box if merged == null else (merged as AABB).merge(box)
	if merged == null:
		return
	var sz: Vector3 = (merged as AABB).size
	var maxdim: float = maxf(maxf(sz.x, sz.y), sz.z)
	if maxdim > 0.0 and maxdim < SMALL_THRESHOLD:
		(scene as Node3D).scale = Vector3.ONE * SCALE_FIX

func _xform_to(node: Node, root: Node) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != root:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t

func _all_meshes(n: Node, arr: Array = []) -> Array:
	if n is MeshInstance3D and n.mesh != null:
		arr.append(n)
	for c in n.get_children():
		_all_meshes(c, arr)
	return arr
