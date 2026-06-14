@tool
extends Node3D

# level_02_art.gd —— L2 非黑盒美术层根脚本(角色D)。
# 地砖/墙是本场景里**烤好的真实节点**(每块可在编辑器单独选中/移动/替换),不再脚本生成。
# 本脚本只做一件事:把兄弟 Level02Depths 的**黑盒地面+墙网格**隐藏(保留其 StaticBody 碰撞 / NavRegion 导航 / 刷怪逻辑),
#   这样可见表面是我的真资产,而玩法(碰撞/路径)仍由 depths 提供 —— 不碰队友代码。
#   立柱/拱门/火盆/祭坛/断墙/灯光等装饰保留(只隐藏地面与墙)。

func _ready() -> void:
	call_deferred("_hide_depths_floor_walls")
	# 自愈:墙被队友提交/编辑器回写覆盖回 scale-1(0.05,看不见)时,加载即自动 ×100 修回。
	# 编辑器+运行时都跑;幂等(已是 scale-100 则跳过,不产生改动/脏标记)。
	call_deferred("_fix_wall_scales")
	# D3 氛围+墙上火把:编辑器+运行时都搭建(这样编辑器预览框也能看到效果)。
	# 所有新建节点都用 INTERNAL 内部节点,Godot 不会保存进 .tscn → 不污染、不会被覆盖。
	# (后期调色 shader 是主视口屏幕特效,编辑器视口里不渲染,故仅运行时加 —— 见 _setup_d3_atmosphere)
	call_deferred("_setup_d3_atmosphere")
	call_deferred("_place_wall_torches")

# 墙尺寸自愈:LevelArt/Walls 下任何 basis 缩放 ~1 的墙(应为 ~100)自动放大 100 倍,保持旋转/原点。
func _fix_wall_scales() -> void:
	var walls: Node = get_node_or_null("Walls")
	if walls == null:
		return
	var n: int = 0
	for w in walls.get_children():
		if w is Node3D:
			var t: Transform3D = (w as Node3D).transform
			if t.basis.x.length() < 50.0:
				t.basis = t.basis.scaled(Vector3(100, 100, 100))
				(w as Node3D).transform = t
				n += 1
	if n > 0:
		print("[level_02_art] 墙尺寸自愈:%d 段 scale-1 → scale-100" % n)

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

# ── D3 关卡氛围(雾 / 灯光 / 后期调色 shader)──────────────────────────────
# 编辑器+运行时都搭建(预览框可见);新节点全用 INTERNAL,不存进 .tscn、不污染、不被覆盖。
# 不改 depths 文件、不改 play_art.tscn 结构。队友的 level_02_play 完全不受影响。
func _setup_d3_atmosphere() -> void:
	var p: Node = get_parent()
	if p == null:
		return
	# 1) 关掉 depths 自带的 WorldEnvironment(只对本场景运行实例,不动其 .tscn),
	#    并把它的平行光压暗调冷,让暖色火把主导,做出 D3 那种"黑底 + 暖光池"的关卡感。
	var depths: Node = p.get_node_or_null("Level02Depths")
	if depths != null:
		var dw := depths.get_node_or_null("WorldEnvironment") as WorldEnvironment
		if dw != null:
			dw.environment = null
		var dl := depths.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
		if dl != null:
			dl.light_energy = 0.35
			dl.light_color = Color(0.55, 0.62, 0.85)   # 冷蓝顶光做补光
	# 2) 我们自己的 D3 WorldEnvironment(雾 + 体积雾光柱 + 辉光 + 调色)。INTERNAL → 不入库。
	if p.get_node_or_null("D3Environment") == null:
		var we := WorldEnvironment.new()
		we.name = "D3Environment"
		we.environment = _make_d3_env()
		p.add_child(we, false, Node.INTERNAL_MODE_BACK)
	# 3) 全屏后期调色 shader —— 仅运行时(屏幕特效在编辑器视口里不渲染,加了反而可能盖黑)
	if not Engine.is_editor_hint() and p.get_node_or_null("D3Grade") == null:
		var cl := CanvasLayer.new()
		cl.name = "D3Grade"
		cl.layer = 1   # 在 3D 之上、HUD(更高层)之下:只调 3D 画面,不影响 UI
		var rect := ColorRect.new()
		rect.name = "Grade"
		rect.anchor_right = 1.0
		rect.anchor_bottom = 1.0
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sh := load("res://assets/shaders/d3_grade.gdshader") as Shader
		if sh != null:
			var mat := ShaderMaterial.new()
			mat.shader = sh
			rect.material = mat
		cl.add_child(rect)
		p.add_child(cl, false, Node.INTERNAL_MODE_BACK)

# ── 墙上批量火把(运行时)──────────────────────────────────────────────
# 沿墙按间距均匀布壁挂火把(背靠墙、朝最近地砖即室内方向),每个配暖色火光。
const TORCH_FBX := "res://assets/PolygonDungeon/Models/Props/Lighting/SM_Prop_Torch_Ornate_02.fbx"
const TORCH_MIN_SPACING := 22.0   # 火把最小间距(世界单位,5=一格)
const TORCH_HEIGHT := 2.7         # 离地高度(墙高约5)
const TORCH_MAX := 110            # 火光数量上限(性能保护)

func _place_wall_torches() -> void:
	var walls: Node = get_node_or_null("Walls")
	var floors: Node = get_node_or_null("Floors")
	if walls == null or floors == null:
		return
	var ps := load(TORCH_FBX) as PackedScene
	if ps == null:
		return
	# 地砖中心点(用于判断"内侧"=室内方向)
	var floor_pts: Array[Vector3] = []
	for f in floors.get_children():
		if f is Node3D:
			floor_pts.append((f as Node3D).position)
	if floor_pts.is_empty():
		return
	if get_node_or_null("Torches") != null:
		return   # 已生成(避免编辑器重复 _ready 时叠加)
	var holder := Node3D.new()
	holder.name = "Torches"
	add_child(holder, false, Node.INTERNAL_MODE_BACK)   # INTERNAL → 不入库
	var placed: Array[Vector3] = []
	for w in walls.get_children():
		if placed.size() >= TORCH_MAX:
			break
		if not (w is Node3D):
			continue
		var wp: Vector3 = (w as Node3D).position
		# 间距去重(均匀分布)
		var too_close := false
		for p in placed:
			if p.distance_to(wp) < TORCH_MIN_SPACING:
				too_close = true
				break
		if too_close:
			continue
		# 最近地砖 → 内侧水平方向
		var nearest := floor_pts[0]
		var nd := 1.0e20
		for fp in floor_pts:
			var d := Vector2(fp.x - wp.x, fp.z - wp.z).length_squared()
			if d < nd:
				nd = d
				nearest = fp
		var inward := Vector3(nearest.x - wp.x, 0.0, nearest.z - wp.z)
		if inward.length() < 0.01:
			inward = Vector3(0.0, 0.0, 1.0)
		inward = inward.normalized()
		# 朝向:本地 +Z(伸出臂)指向室内;scale 100(原生)
		var xc := Vector3.UP.cross(inward).normalized()
		var b := Basis(xc * 100.0, Vector3.UP * 100.0, inward * 100.0)
		var pos := wp + inward * 0.35 + Vector3(0.0, TORCH_HEIGHT, 0.0)
		var torch := ps.instantiate() as Node3D
		torch.transform = Transform3D(b, pos)
		holder.add_child(torch)
		# 火光
		var lt := OmniLight3D.new()
		lt.light_color = Color(1.0, 0.6, 0.28)
		lt.light_energy = 3.0
		lt.omni_range = 8.5
		lt.omni_attenuation = 1.5
		lt.shadow_enabled = false   # 关阴影:几十盏灯也不卡
		lt.position = pos + inward * 0.45 + Vector3(0.0, 0.35, 0.0)
		holder.add_child(lt)
		placed.append(wp)
	print("[level_02_art] 墙上火把:%d 个" % placed.size())

func _make_d3_env() -> Environment:
	var e := Environment.new()
	# 背景:地牢无天空,纯暗色
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.015, 0.016, 0.022)
	# 环境光:冷暗低强度
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.22, 0.24, 0.32)
	e.ambient_light_energy = 0.70
	# 色调映射:ACES 电影感。曝光统一控制全场亮度(在所有灯/火把/环境光之上)。基线1.05→1.26→1.89→再+50%=2.84。
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 2.84
	e.tonemap_white = 6.0
	# 雾:冷暗指数高度雾 + 空气透视
	e.fog_enabled = true
	e.fog_light_color = Color(0.09, 0.10, 0.14)
	e.fog_light_energy = 0.6
	e.fog_density = 0.03
	e.fog_aerial_perspective = 0.35
	e.fog_sky_affect = 0.0
	e.fog_height = -2.0
	e.fog_height_density = 0.08
	# 体积雾:火把/熔岩透出的光柱 —— D3 招牌氛围
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.02
	e.volumetric_fog_albedo = Color(0.34, 0.29, 0.25)
	e.volumetric_fog_length = 96.0
	e.volumetric_fog_gi_inject = 0.0
	# 辉光:火光泛光(只对高亮部分)
	e.glow_enabled = true
	e.glow_intensity = 0.85
	e.glow_strength = 1.0
	e.glow_bloom = 0.12
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.glow_hdr_threshold = 1.05
	# 颜色校正:提对比 + 轻去饱和
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 0.9
	return e
