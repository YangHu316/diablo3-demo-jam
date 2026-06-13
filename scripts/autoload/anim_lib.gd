extends Node

## AnimLib — UAL 动画库 autoload(全局空间重定向版)。
##
## 把 UAL 动画(ual1/ual2_synty.glb,骨骼名已与 Synty 角色一致,但 rest pose 不同)
## 重定向到 Synty 角色骨架(Characters.fbx)的 rest 上,以 AnimationLibrary 形式分发。
##
## 重定向原理(全局空间,逐帧采样):
##   目标骨骼全局姿势 T_g = S_g · S_globalRest⁻¹ · T_globalRest
##   再按层级换算成局部轨道。这样无论两边 rest 差多少,变形结果都和源一致。
##
## 用法:
##   AnimLib.inject_library($AnimationPlayer, "ual1")
##   $AnimationPlayer.play("ual1/Idle")

const UAL1_PATH := "res://assets/animations/ual1_synty.glb"
const UAL2_PATH := "res://assets/animations/ual2_synty.glb"
# 目标角色骨架参考(16 个 Synty 角色共用此骨架的 rest)
const CHAR_REF_PATH := "res://assets/PolygonDungeon/Models/Characters/Characters.fbx"
const SYNTY_SKELETON_PATH := "Skeleton3D"
const SAMPLE_FPS := 30.0

var _libraries: Dictionary = {}
var _loaded: bool = false

# 目标骨架信息(从 Characters.fbx 提取一次)
var _t_ready: bool = false
var _t_names: PackedStringArray = []
var _t_parent: PackedInt32Array = []
var _t_grest: Array = []              # Array[Transform3D] 全局 rest
var _t_idx: Dictionary = {}           # bone name -> index

# ── 公共 API ──────────────────────────────────────────────
func get_library(name: String) -> AnimationLibrary:
	if not _loaded:
		_load_all()
	return _libraries.get(name, null) as AnimationLibrary

func get_library_names() -> PackedStringArray:
	if not _loaded:
		_load_all()
	return PackedStringArray(_libraries.keys())

func get_anim_names(lib_name: String) -> PackedStringArray:
	var lib := get_library(lib_name)
	if lib == null:
		return PackedStringArray()
	return PackedStringArray(lib.get_animation_list())

func inject_library(target: AnimationPlayer, lib_name: String) -> bool:
	var lib := get_library(lib_name)
	if lib == null:
		push_warning("AnimLib: library '%s' not found" % lib_name)
		return false
	if target.has_animation_library(lib_name):
		return true
	target.add_animation_library(lib_name, lib)
	return true

func inject_all(target: AnimationPlayer) -> void:
	for lib_name in _libraries:
		inject_library(target, lib_name)

# ── 加载 ──────────────────────────────────────────────────
func _ready() -> void:
	_load_all()

func _load_all() -> void:
	_loaded = true
	if not _ensure_target():
		push_warning("AnimLib: 目标角色骨架加载失败,跳过")
		return
	_load_glb("ual1", UAL1_PATH)
	_load_glb("ual2", UAL2_PATH)

# 提取目标角色骨架的 bone 名/父子/全局 rest
func _ensure_target() -> bool:
	if _t_ready:
		return true
	if not ResourceLoader.exists(CHAR_REF_PATH):
		return false
	var inst: Node = (load(CHAR_REF_PATH) as PackedScene).instantiate()
	add_child(inst)
	var sk: Skeleton3D = _find_skeleton_node(inst)
	if sk == null:
		inst.queue_free()
		return false
	for i in sk.get_bone_count():
		_t_names.append(sk.get_bone_name(i))
		_t_parent.append(sk.get_bone_parent(i))
		_t_grest.append(sk.get_bone_global_rest(i))
		_t_idx[sk.get_bone_name(i)] = i
	inst.queue_free()
	_t_ready = true
	return true

func _load_glb(lib_name: String, glb_path: String) -> void:
	if not ResourceLoader.exists(glb_path):
		push_warning("AnimLib: GLB not found at %s" % glb_path)
		return
	var inst: Node = (load(glb_path) as PackedScene).instantiate()
	add_child(inst)
	var ap: AnimationPlayer = _find_animation_player(inst)
	var ssk: Skeleton3D = _find_skeleton_node(inst)
	if ap == null or ssk == null:
		push_warning("AnimLib: %s 缺 AnimationPlayer 或 Skeleton3D" % glb_path)
		inst.queue_free()
		return

	# 源骨架(UAL)的全局 rest + 名字索引
	var s_idx: Dictionary = {}
	var s_grest: Array = []
	for i in ssk.get_bone_count():
		s_idx[ssk.get_bone_name(i)] = i
		s_grest.append(ssk.get_bone_global_rest(i))

	var merged := AnimationLibrary.new()
	for ln in ap.get_animation_library_list():
		var src_lib: AnimationLibrary = ap.get_animation_library(ln)
		if src_lib == null:
			continue
		for anim_name in src_lib.get_animation_list():
			var play_name: String = anim_name if ln == "" else "%s/%s" % [ln, anim_name]
			var baked := _rebake(ap, ssk, s_idx, s_grest, play_name, src_lib.get_animation(anim_name))
			var final_name := anim_name
			var n := 1
			while merged.has_animation(final_name):
				final_name = "%s_%d" % [anim_name, n]
				n += 1
			merged.add_animation(final_name, baked)

	_libraries[lib_name] = merged
	inst.queue_free()
	print("AnimLib: 重定向 %d 个动画 -> %s" % [merged.get_animation_list().size(), lib_name])

# 采样式全局重定向:把源动画烤成目标骨架可用的局部轨道
func _rebake(ap: AnimationPlayer, ssk: Skeleton3D, s_idx: Dictionary, s_grest: Array,
		play_name: String, src: Animation) -> Animation:
	var out := Animation.new()
	out.length = src.length
	out.loop_mode = src.loop_mode

	# 为每个"目标有 & 源也有"的骨骼建 旋转+位移 轨道
	var rot_track: Dictionary = {}   # t_idx -> track id
	var pos_track: Dictionary = {}
	for ti in _t_names.size():
		var bn: String = _t_names[ti]
		if s_idx.has(bn):
			var rt := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(rt, "%s:%s" % [SYNTY_SKELETON_PATH, bn])
			rot_track[ti] = rt
			var pt := out.add_track(Animation.TYPE_POSITION_3D)
			out.track_set_path(pt, "%s:%s" % [SYNTY_SKELETON_PATH, bn])
			pos_track[ti] = pt

	var n_samples: int = clampi(int(ceil(src.length * SAMPLE_FPS)) + 1, 2, 240)
	ap.play(play_name)
	for k in n_samples:
		var t: float = src.length * float(k) / float(n_samples - 1)
		ap.seek(t, true)
		var tg: Dictionary = {}   # t_idx -> Transform3D(目标全局姿势)
		for ti in _t_names.size():
			if not rot_track.has(ti):
				continue
			var bn: String = _t_names[ti]
			var si: int = s_idx[bn]
			var s_g: Transform3D = ssk.get_bone_global_pose(si)
			var t_global: Transform3D = s_g * (s_grest[si] as Transform3D).affine_inverse() * (_t_grest[ti] as Transform3D)
			tg[ti] = t_global
			var par: int = _t_parent[ti]
			var t_local: Transform3D
			if par >= 0 and tg.has(par):
				t_local = (tg[par] as Transform3D).affine_inverse() * t_global
			else:
				t_local = t_global
			out.track_insert_key(rot_track[ti], t, t_local.basis.get_rotation_quaternion())
			out.track_insert_key(pos_track[ti], t, t_local.origin)
	return out

# ── 工具 ──────────────────────────────────────────────────
func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_animation_player(c)
		if r != null:
			return r
	return null

func _find_skeleton_node(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skeleton_node(c)
		if r != null:
			return r
	return null
