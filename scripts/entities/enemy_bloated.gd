extends "res://scripts/entities/enemy_base.gd"

# EnemyBloated — 肿胀走尸(自爆)
# 行为(rift_monsters.csv §肿胀走尸):
#   - 接近玩家到 attack_range(4m) → 起引信(FUSE_DURATION=1.0s),期间不动
#   - 引信结束 / 死亡 → 引爆:AOE EXPLODE_RADIUS(4m) 内伤害 = ATK×3(=72)
#   - 引爆视觉:暖橙色冲击环 + 屏震
# 死亡和引信都走 _do_explode_aoe(去重防止双爆)

const DEFAULT_DATA_PATH: String = "res://scripts/entities/data/bloated_corpse.tres"
const FUSE_DURATION: float = 1.0
const EXPLODE_RADIUS: float = 4.0
const EXPLODE_DAMAGE_MULT: int = 3  # CSV: ATK × 3

var _is_fusing: bool = false
var _fuse_timer: float = 0.0
var _exploded: bool = false  # 防止双爆(引信和死亡同时触发)
var _orig_scale: Vector3 = Vector3.ONE

func _ready() -> void:
	if data == null and ResourceLoader.exists(DEFAULT_DATA_PATH):
		data = load(DEFAULT_DATA_PATH)
	super._ready()
	_orig_scale = scale

func _physics_process(delta: float) -> void:
	if state == State.DEATH:
		return
	# 冰冻 / 击退时暂停引信(让玩家有处理空间)
	if is_frozen:
		super._physics_process(delta)
		return
	if knockback_comp != null and knockback_comp.has_method("is_active") and knockback_comp.is_active():
		super._physics_process(delta)
		return
	if _is_fusing:
		_tick_fuse(delta)
		return
	super._physics_process(delta)

func _tick_fuse(delta: float) -> void:
	_fuse_timer -= delta
	velocity = Vector3.ZERO
	move_and_slide()
	# 视觉:线性放大到 1.4 倍 — 膨胀光球预警
	var t: float = clamp(1.0 - (_fuse_timer / FUSE_DURATION), 0.0, 1.0)
	scale = _orig_scale.lerp(_orig_scale * 1.4, t)
	if _fuse_timer <= 0.0:
		_explode()

# 进入 attack_range 立即引信(替代基类的近战 ATTACK)
func _tick_attack(_delta: float) -> void:
	if not _is_fusing and not _exploded:
		_is_fusing = true
		_fuse_timer = FUSE_DURATION

# 死亡也引爆(被击杀的瞬间)— 在 super._die 之前先炸
func _die(source, overkill: int) -> void:
	if _exploded:
		# 引信 path 已经爆过,直接走基类死亡
		super._die(source, overkill)
		return
	_exploded = true
	_do_explode_aoe()
	super._die(source, overkill)

# 引信完成的引爆 path
func _explode() -> void:
	if _exploded:
		return
	_exploded = true
	_do_explode_aoe()
	# 引爆即死(零血,走基类死亡演出)
	current_health = 0
	super._die(null, 0)

func _do_explode_aoe() -> void:
	var dmg: int = attack_damage * EXPLODE_DAMAGE_MULT  # 24×3=72
	var center: Vector3 = global_position
	# 玩家
	if _player != null and is_instance_valid(_player):
		var dist: float = center.distance_to(_player.global_position)
		if dist <= EXPLODE_RADIUS and _player.has_method("take_damage"):
			_player.take_damage(dmg, self)
	# 视觉:冲击环
	_spawn_explosion_ring(center)
	# 屏震
	var cjm: Node = get_node_or_null("/root/CombatJuiceManager")
	if cjm != null and cjm.has_method("_trigger_screen_shake"):
		cjm._trigger_screen_shake()
	# SFX 爆炸
	var sfx: Node = get_node_or_null("/root/Sfx")
	if sfx != null and sfx.has_method("play"):
		sfx.play("explode", center, 0.0, 0.05)

func _spawn_explosion_ring(center: Vector3) -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.55, 0.15, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.45, 0.10, 1.0)
	mat.emission_energy_multiplier = 6.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var torus: TorusMesh = TorusMesh.new()
	torus.inner_radius = max(0.1, EXPLODE_RADIUS - 0.3)
	torus.outer_radius = EXPLODE_RADIUS
	torus.ring_segments = 48
	torus.material = mat
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = torus
	scene_root.add_child(mi)
	mi.global_position = center + Vector3(0, 0.05, 0)
	mi.scale = Vector3.ONE * 0.2
	# 关键:tween 必须挂在 ring(mi)上,不能挂在 self(self 引爆后立即 queue_free,
	# 挂在 self 上的 tween 会被一起 kill,queue_free 回调不会跑 → 圈圈留在场景永不消失)
	var tw: Tween = mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * 1.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	tw.tween_property(mat, "emission_energy_multiplier", 0.0, 0.45)
	tw.chain().tween_callback(Callable(mi, "queue_free"))
