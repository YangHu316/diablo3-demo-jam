extends Node

# 监听 SkillSlotManager.skill_activated,按 SkillData.skill_type 分发执行。
# 挂在 Player 子节点。需要 player 是 Node3D,且有 ArrowSpawnPoint 子节点。

const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")

const ARROW_SCENE_PATH: String = "res://scenes/projectiles/arrow.tscn"

# SkillType 枚举值(与 skill_data.gd 中 SkillType 保持同步)
const TYPE_PROJECTILE: int = 0
const TYPE_MOVEMENT: int = 1
const TYPE_SUMMON: int = 2
const TYPE_MELEE: int = 3

@export var slot_manager_path: NodePath = NodePath("../SkillSlotManager")
@export var arrow_spawn_point_path: NodePath = NodePath("../ArrowSpawnPoint")

var _arrow_scene: PackedScene = null
var _player: Node3D = null
var _spawn_point: Node3D = null
var _slot_manager: Node = null

func _ready() -> void:
	_arrow_scene = load(ARROW_SCENE_PATH)
	var p: Node = get_parent()
	if p is Node3D:
		_player = p
	else:
		push_error("SkillExecutor: parent is not Node3D")
	_spawn_point = get_node_or_null(arrow_spawn_point_path) as Node3D
	_slot_manager = get_node_or_null(slot_manager_path)
	if _slot_manager != null:
		_slot_manager.skill_activated.connect(_on_skill_activated)
	else:
		push_error("SkillExecutor: SkillSlotManager not found at %s" % slot_manager_path)

# sd 期望是 SkillData 资源
func _on_skill_activated(slot_index: int, sd: Resource) -> void:
	if sd == null:
		return
	var stype: int = int(sd.skill_type)
	match stype:
		TYPE_PROJECTILE:
			_execute_projectile(sd)
		TYPE_MOVEMENT:
			_execute_movement(sd)
		TYPE_SUMMON:
			_execute_summon(sd)
		TYPE_MELEE:
			_execute_melee(sd)
		_:
			push_warning("SkillExecutor: unhandled skill_type %s for %s" % [stype, sd.skill_id])

# ── 射击类 ─────────────────────────────────────────────
func _execute_projectile(sd: Resource) -> void:
	if _arrow_scene == null or _player == null:
		return
	var fwd: Vector3 = -_player.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	fwd = fwd.normalized()

	var spawn_pos: Vector3
	if _spawn_point != null and is_instance_valid(_spawn_point):
		spawn_pos = _spawn_point.global_position
	else:
		spawn_pos = _player.global_position + Vector3(0, 1.0, 0)

	var count: int = max(1, int(sd.projectile_count))
	var spread: float = float(sd.projectile_spread_angle)
	var scene_root: Node = get_tree().current_scene

	for i in range(count):
		# 每发箭独立计算伤害(各自暴击/不暴击)
		var dmg_info: Dictionary = DamageCalculator.compute(sd)
		var dir: Vector3 = fwd
		if count > 1 and spread > 0.0:
			# 均匀分布 [-spread/2, +spread/2]
			var t: float = float(i) / float(count - 1)
			var angle_deg: float = lerp(-spread * 0.5, spread * 0.5, t)
			dir = fwd.rotated(Vector3.UP, deg_to_rad(angle_deg))
		var arrow: Node = _arrow_scene.instantiate()
		if arrow == null:
			continue
		scene_root.add_child(arrow)
		if arrow is Node3D:
			(arrow as Node3D).global_position = spawn_pos
			(arrow as Node3D).look_at(spawn_pos + dir, Vector3.UP)
		if arrow.has_method("set_direction"):
			arrow.set_direction(dir)
		if arrow.has_method("configure_from_skill"):
			arrow.configure_from_skill(sd, dmg_info)

# ── 位移类(翻滚) ─────────────────────────────────────
func _execute_movement(sd: Resource) -> void:
	if _player == null:
		return
	# 拿位移方向:优先 WASD 输入,无输入则用 player 当前面前方向
	var direction: Vector3 = Vector3.ZERO
	if _player.has_method("get_movement_input_direction"):
		direction = _player.get_movement_input_direction()
	if direction.length() < 0.001 and _player.has_method("get_forward"):
		direction = _player.get_forward()
	direction.y = 0.0
	if direction.length() < 0.001:
		return

	var distance: float = float(sd.move_distance) if "move_distance" in sd else 4.0
	var duration: float = float(sd.move_duration) if "move_duration" in sd else 0.4
	if not _player.has_method("dodge"):
		push_warning("SkillExecutor: player.dodge() missing")
		return
	var ok: bool = _player.dodge(direction, distance, duration)
	if not ok:
		return
	# 取消攻击 CD(让翻滚立即可接射击)
	var cancels: bool = bool(sd.cancels_attack_cooldowns) if "cancels_attack_cooldowns" in sd else false
	if cancels and _slot_manager != null and _slot_manager.has_method("cancel_cooldown"):
		_slot_manager.cancel_cooldown(0)  # LMB 利箭
		_slot_manager.cancel_cooldown(1)  # RMB 多重射击

# ── 召唤类(女武神) ───────────────────────────────────
const SUMMON_GROUP_PREFIX: String = "summon_"

func _execute_summon(sd: Resource) -> void:
	if _player == null:
		return
	var summon_scene: PackedScene = sd.summon_scene if "summon_scene" in sd else null
	if summon_scene == null:
		push_warning("SkillExecutor: summon_scene missing on %s" % sd.skill_id)
		return
	var max_count: int = int(sd.summon_max_count) if "summon_max_count" in sd else 1
	var duration: float = float(sd.summon_duration) if "summon_duration" in sd else 0.0
	var group_name: String = SUMMON_GROUP_PREFIX + String(sd.skill_id)

	# 检查同种召唤物上限,超出移除最旧的(get_nodes_in_group 返回顺序≈添加顺序)
	var existing: Array = get_tree().get_nodes_in_group(group_name)
	while existing.size() >= max_count and not existing.is_empty():
		var oldest: Node = existing[0]
		if is_instance_valid(oldest):
			if oldest.has_method("dismiss"):
				oldest.dismiss()
			else:
				oldest.queue_free()
		existing.remove_at(0)

	# 实例化召唤物
	var summon: Node = summon_scene.instantiate()
	if summon == null:
		return
	# 生命周期注入(在 add_child 之前设,_ready 时已就绪)
	if duration > 0.0 and "lifetime" in summon:
		summon.lifetime = duration
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	scene_root.add_child(summon)
	# 生成位置:玩家面前 1.5m,稍偏左
	if summon is Node3D:
		var fwd: Vector3 = -_player.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length() > 0.001:
			fwd = fwd.normalized()
		else:
			fwd = Vector3.FORWARD
		var right: Vector3 = fwd.cross(Vector3.UP).normalized()
		(summon as Node3D).global_position = _player.global_position + fwd * 1.5 + right * 0.4
		# 朝玩家面向方向
		(summon as Node3D).look_at((summon as Node3D).global_position + fwd, Vector3.UP)
	summon.add_to_group(group_name)

# ── 近战类(预留) ───────────────────────────────────────
func _execute_melee(sd: Resource) -> void:
	# TODO: 近战 hitbox。
	push_warning("SkillExecutor: melee skill not implemented yet (%s)" % sd.skill_id)
