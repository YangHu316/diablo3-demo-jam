@tool
extends Node3D

# level_02_art.gd —— L2 非黑盒美术层根脚本(角色D)。
# 地砖/墙是本场景里**烤好的真实节点**(每块可在编辑器单独选中/移动/替换),不再脚本生成。
# 本脚本只做一件事:把兄弟 Level02Depths 的**黑盒地面+墙网格**隐藏(保留其 StaticBody 碰撞 / NavRegion 导航 / 刷怪逻辑),
#   这样可见表面是我的真资产,而玩法(碰撞/路径)仍由 depths 提供 —— 不碰队友代码。
#   立柱/拱门/火盆/祭坛/断墙/灯光等装饰保留(只隐藏地面与墙)。

func _ready() -> void:
	call_deferred("_hide_depths_floor_walls")

func _hide_depths_floor_walls() -> void:
	var p: Node = get_parent()
	if p == null:
		return
	var depths: Node = p.get_node_or_null("Level02Depths")
	if depths == null:
		return
	_scan_hide(depths)

func _scan_hide(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		if mi.mesh is BoxMesh:
			var sz: Vector3 = (mi.mesh as BoxMesh).size
			var is_floor: bool = sz.y <= 0.6 and sz.x > 2.0 and sz.z > 2.0
			var is_wall: bool = sz.y >= 2.0 and (sz.x <= 0.8 or sz.z <= 0.8)
			if is_floor or is_wall:
				mi.visible = false
	for c in n.get_children():
		_scan_hide(c)
