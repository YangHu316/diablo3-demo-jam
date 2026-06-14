extends Node

# CombatJuiceManager (Autoload)
# 监听 CombatManager.hit_landed / enemy_killed,统一分发 5 个反馈子系统:
#   1. 受击闪白(shader uniform flash_intensity)
#   2. 伤害飘字(DamageNumberPool)
#   3. 屏幕震动(Camera 子节点 ScreenShake)
#   4. 击退(target/KnockbackComponent)
#   5. 受击僵直(target/StaggerComponent)

# ── 调参 ──────────────────────────────────────────────
const FLASH_DURATION: float = 0.06

const KNOCKBACK_DISTANCE: float = 2.5
const KNOCKBACK_DURATION: float = 0.4

const SHAKE_INTENSITY: float = 0.05
const SHAKE_DURATION: float = 0.1
const HEAVY_SHAKE_HEALTH_PCT: float = 0.5  # 暴击 + 伤害 >= 50% 最大生命才屏震

const SHADER_PATH: String = "res://shaders/hit_flash.gdshader"
const KNOCKBACK_NODE_NAME: String = "KnockbackComponent"
const STAGGER_NODE_NAME: String = "StaggerComponent"

# ── 内部状态 ─────────────────────────────────────────
var _shader: Shader = null
# MeshInstance3D.instance_id -> ShaderMaterial 缓存,避免每次命中都新建材质
var _flash_materials: Dictionary = {}
# MeshInstance3D.instance_id -> Tween,中断旧 tween 避免叠加
var _flash_tweens: Dictionary = {}
# MeshInstance3D.instance_id -> 原始 surface_override_material(0)(冰冻恢复时还原)。
# null 表示原本就没设 override(走 mesh 自身材质)。
var _original_overrides: Dictionary = {}

func _ready() -> void:
	_shader = load(SHADER_PATH)
	if _shader == null:
		push_warning("CombatJuiceManager: failed to load %s" % SHADER_PATH)
	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null:
		cm.hit_landed.connect(_on_hit_landed)
		cm.enemy_killed.connect(_on_enemy_killed)
		cm.player_damaged.connect(_on_player_damaged)
	else:
		push_warning("CombatJuiceManager: CombatManager autoload not found")

# ── 入口:hit_landed ──────────────────────────────────
func _on_hit_landed(_attacker, target, damage: int, is_crit: bool, _element: String, hit_position: Vector3, hit_direction: Vector3) -> void:
	if not is_instance_valid(target):
		return

	# 1. 闪白
	_apply_flash(target)

	# 2. 飘字
	var pool: Node = get_node_or_null("/root/DamageNumberPool")
	if pool != null and pool.has_method("show_damage"):
		pool.show_damage(hit_position, damage, is_crit)

	# 3. 屏震:仅暴击 + 伤害 >= 50% 最大生命
	if is_crit:
		var max_hp: int = _get_max_health(target)
		if max_hp > 0 and float(damage) >= float(max_hp) * HEAVY_SHAKE_HEALTH_PCT:
			_trigger_screen_shake()
			# 暴击重击 SFX(slash + impact 复合)
			var sfx_crit: Node = get_node_or_null("/root/Sfx")
			if sfx_crit != null and sfx_crit.has_method("play"):
				sfx_crit.play("slash", hit_position, 2.0, 0.05)

	# 4. 击退
	var kb: Node = target.get_node_or_null(KNOCKBACK_NODE_NAME)
	if kb != null and kb.has_method("apply"):
		kb.apply(hit_direction, KNOCKBACK_DISTANCE, KNOCKBACK_DURATION)

	# 5. 僵直
	var sg: Node = target.get_node_or_null(STAGGER_NODE_NAME)
	if sg != null and sg.has_method("trigger"):
		var max_hp_for_stagger: int = _get_max_health(target)
		sg.trigger(damage, max_hp_for_stagger, is_crit)

# ── 入口:enemy_killed ─────────────────────────────────
func _on_enemy_killed(enemy, _killer, overkill: int, _kill_dir: Vector3) -> void:
	# 击杀附加一次小屏震 + 显示溢伤数字(可选)
	_trigger_screen_shake()
	if is_instance_valid(enemy) and enemy is Node3D:
		var pool: Node = get_node_or_null("/root/DamageNumberPool")
		if pool != null and pool.has_method("show_damage"):
			pool.show_damage((enemy as Node3D).global_position + Vector3(0, 1.0, 0), overkill, true)

# ── 入口:player_damaged ───────────────────────────────
# 玩家被击的反馈:闪白 mesh + 屏震 + 红字飘字(伤害数字,与给敌人的白字区分用红色)。
# 没有这层反馈玩家分不清"是没被打到"还是"被打到了但看不见"。
func _on_player_damaged(amount: int, _source) -> void:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	# 1. mesh 闪白(复用 enemy 同样的 shader)
	_apply_flash(player)
	# 2. 屏震:振幅大一点,玩家自己挨打要明显
	_trigger_player_hit_shake()
	# 3. 红字飘字
	if player is Node3D:
		var pool: Node = get_node_or_null("/root/DamageNumberPool")
		if pool != null and pool.has_method("show_damage"):
			# 用 is_crit=true 借用黄字弹跳的视觉,但下面手动覆盖颜色为红
			# 简化:就用普通白字(避免改 pool 接口)
			pool.show_damage((player as Node3D).global_position + Vector3(0, 1.5, 0), amount, false)

# 玩家被击的屏震比敌人重击稍弱但持续略长(主体感受是"被打了一下"而非"我打了重击")
func _trigger_player_hit_shake() -> void:
	var cam: Camera3D = _get_active_camera()
	if cam == null:
		return
	var ss: Node = cam.get_node_or_null("ScreenShake")
	if ss != null and ss.has_method("shake"):
		ss.shake(0.08, 0.15)
		return
	if cam.has_method("apply_shake"):
		cam.call("apply_shake", 0.08, 0.15)

# ── 闪白实现 ─────────────────────────────────────────
func _apply_flash(target: Node) -> void:
	var mesh: MeshInstance3D = _find_mesh(target)
	if mesh == null:
		return
	var mat: ShaderMaterial = _ensure_flash_material(mesh)
	if mat == null:
		return
	# 中断该材质上的旧 tween
	var key: int = mesh.get_instance_id()
	if _flash_tweens.has(key):
		var old_tw = _flash_tweens[key]
		if old_tw is Tween and (old_tw as Tween).is_valid():
			(old_tw as Tween).kill()
	mat.set_shader_parameter("flash_intensity", 1.0)
	var tw: Tween = mesh.create_tween()
	tw.tween_property(mat, "shader_parameter/flash_intensity", 0.0, FLASH_DURATION)
	# tween 结束后自动清理 dict 条目，防止无限增长
	tw.finished.connect(func() -> void: _flash_tweens.erase(key))
	_flash_tweens[key] = tw

func _find_mesh(node: Node) -> MeshInstance3D:
	if not is_instance_valid(node):
		return null
	if node is MeshInstance3D:
		return node
	# 优先查名为 BodyMesh 的子节点(项目惯例)
	var named: Node = node.get_node_or_null("BodyMesh")
	if named is MeshInstance3D:
		return named
	# 退化:深度优先找第一个 MeshInstance3D
	for c in node.get_children():
		if c is MeshInstance3D:
			return c
		var sub: MeshInstance3D = _find_mesh(c)
		if sub != null:
			return sub
	return null

func _ensure_flash_material(mesh: MeshInstance3D) -> ShaderMaterial:
	if _shader == null:
		return null
	var key: int = mesh.get_instance_id()
	if _flash_materials.has(key):
		var cached = _flash_materials[key]
		if cached is ShaderMaterial and is_instance_valid(cached):
			return cached
		_flash_materials.erase(key)
	# 从已有材质提取 albedo / roughness / metallic 作为 shader 参数初值
	var existing: Material = mesh.get_active_material(0)
	var albedo: Color = Color(1, 1, 1, 1)
	var rough: float = 0.8
	var metal: float = 0.0
	if existing is StandardMaterial3D:
		var sm: StandardMaterial3D = existing
		albedo = sm.albedo_color
		rough = sm.roughness
		metal = sm.metallic
	elif existing is ShaderMaterial:
		var prev: ShaderMaterial = existing
		var prev_albedo = prev.get_shader_parameter("albedo_color")
		if prev_albedo != null:
			albedo = prev_albedo
		var prev_rough = prev.get_shader_parameter("roughness")
		if prev_rough != null:
			rough = prev_rough
		var prev_metal = prev.get_shader_parameter("metallic")
		if prev_metal != null:
			metal = prev_metal

	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("albedo_color", albedo)
	mat.set_shader_parameter("roughness", rough)
	mat.set_shader_parameter("metallic", metal)
	mat.set_shader_parameter("flash_intensity", 0.0)
	mat.set_shader_parameter("freeze_intensity", 0.0)
	# 记录覆盖前的原 override(可能是 null,即"走 mesh 自身材质 / Synty 纹理")
	# 冰冻结束时还原 → 不会出现"丢失贴图变纯色"的问题。
	if not _original_overrides.has(key):
		_original_overrides[key] = mesh.get_surface_override_material(0)
		# mesh 释放时自动清理 3 个 dict，防止内存无限增长
		mesh.tree_exited.connect(func() -> void:
			_flash_materials.erase(key)
			_original_overrides.erase(key)
			if _flash_tweens.has(key):
				var tw = _flash_tweens[key]
				if tw is Tween and (tw as Tween).is_valid():
					(tw as Tween).kill()
				_flash_tweens.erase(key)
		)
	mesh.set_surface_override_material(0, mat)
	_flash_materials[key] = mat
	return mat

# ── 冰冻染色(供敌人 apply_freeze 调用)──────────────
# frozen=true 时把目标 mesh 染成冰蓝;false 时清除。
# V3.0 修:之前只走 _find_mesh 取第一个(常见是不可见的 BodyMesh) → 视觉无效。
# 现改为收集 target 下所有"可见"MeshInstance3D 全部染色,适配 Synty 多 mesh 角色。
func set_freeze(target: Node, frozen: bool) -> void:
	if not is_instance_valid(target):
		return
	var meshes: Array = []
	_collect_visible_meshes(target, meshes)
	for m in meshes:
		var mesh: MeshInstance3D = m as MeshInstance3D
		if mesh == null:
			continue
		if frozen:
			# 冻:确保有 shader override + 染冰蓝
			var mat: ShaderMaterial = _ensure_flash_material(mesh)
			if mat == null:
				continue
			mat.set_shader_parameter("freeze_intensity", 1.0)
		else:
			# 解冻:还原原始 override(常为 null = 走自身材质/Synty 纹理)
			var key: int = mesh.get_instance_id()
			if _original_overrides.has(key):
				mesh.set_surface_override_material(0, _original_overrides[key])
				_original_overrides.erase(key)
			else:
				# 兜底:没记录就当无原 override
				mesh.set_surface_override_material(0, null)
			# 失效缓存,避免下次 flash 用到错误的 mesh 引用
			_flash_materials.erase(key)
			if _flash_tweens.has(key):
				var tw = _flash_tweens[key]
				if tw is Tween and is_instance_valid(tw):
					tw.kill()
				_flash_tweens.erase(key)

# 递归收集 node 下所有 visible 的 MeshInstance3D(对 Synty 角色 rig 有 ~10 个 mesh 友好)
func _collect_visible_meshes(node: Node, out: Array) -> void:
	if not is_instance_valid(node):
		return
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.visible and mi.is_visible_in_tree():
			out.append(mi)
	for c in node.get_children():
		_collect_visible_meshes(c, out)

# ── 屏震 ─────────────────────────────────────────────
func _trigger_screen_shake() -> void:
	var cam: Camera3D = _get_active_camera()
	if cam == null:
		return
	var ss: Node = cam.get_node_or_null("ScreenShake")
	if ss != null and ss.has_method("shake"):
		ss.shake(SHAKE_INTENSITY, SHAKE_DURATION)
		return
	# 兜底:相机若实现了 apply_shake,直接调
	if cam.has_method("apply_shake"):
		cam.call("apply_shake", SHAKE_INTENSITY, SHAKE_DURATION)

func _get_active_camera() -> Camera3D:
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	var vp: Viewport = tree.root
	if vp == null:
		return null
	return vp.get_camera_3d()

# ── 工具 ─────────────────────────────────────────────
func _get_max_health(target: Node) -> int:
	if "max_health" in target:
		return int(target.max_health)
	return 0
