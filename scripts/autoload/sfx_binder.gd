extends Node

# sfx_binder.gd — SFX 事件绑定器 (Autoload "SfxBind")。
# 纯监听层:连到各系统/节点的信号上调用 Sfx.play(key),不改任何系统逻辑。
#   - 全局 autoload 信号:_ready 时直接连 (CombatManager / Inventory / ProgressionManager / RiftManager)
#   - 运行时生成的节点 (player / templar / enemy / arrow):用 SceneTree.node_added 动态钩
#   - 脚步:每帧看玩家是否在地面移动, 按间隔播 step
# 维护:要改某事件的音, 改下面对应 _on_* 里的 key (key 定义见 sfx_manager.SOUND_TABLE)。

const STEP_INTERVAL: float = 0.34       # 脚步间隔 (秒)
const STEP_SPEED_MIN: float = 1.5       # 平面速度超此值才算"在走"
const SHOOT_DEBOUNCE: float = 0.08      # 连发(多重射击)只出一次射击音

var _player: Node = null
var _step_t: float = 0.0
var _last_shoot_t: float = -1.0

func _ready() -> void:
	# ── 全局 autoload 信号 ──
	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null:
		_try(cm, "hit_landed", _on_hit)
		_try(cm, "enemy_killed", _on_enemy_killed)
		_try(cm, "player_damaged", _on_player_damaged)
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv != null:
		_try(inv, "item_picked_up", _on_pickup)
		_try(inv, "item_equipped", _on_equip)
		_try(inv, "item_unequipped", _on_unequip)
	var pm: Node = get_node_or_null("/root/ProgressionManager")
	if pm != null:
		_try(pm, "level_up", _on_level_up)
	var rm: Node = get_node_or_null("/root/RiftManager")
	if rm != null:
		_try(rm, "guardian_ready", _on_guardian_ready)
		_try(rm, "run_cleared", _on_run_cleared)

	# ── 运行时节点 ──
	get_tree().node_added.connect(_on_node_added)
	# 兜底:连接器晚于已存在的节点时, 扫一遍当前场景树.
	call_deferred("_hook_existing")

func _try(obj: Object, sig: String, cb: Callable) -> void:
	if obj.has_signal(sig) and not obj.is_connected(sig, cb):
		obj.connect(sig, cb)

# ── 动态节点识别 (靠信号特征, 不依赖分组先后) ─────────────────
func _on_node_added(n: Node) -> void:
	if n == null:
		return
	if n.has_signal("dodge_started") and n.has_signal("player_died"):
		_hook_player(n)
	elif n.has_signal("heal_pulsed"):
		_hook_templar(n)
	elif n.has_signal("state_changed") and n.has_signal("died"):
		_hook_enemy(n)
	else:
		var scr: Script = n.get_script()
		if scr != null and String(scr.resource_path).ends_with("/arrow.gd"):
			_on_arrow_spawned(n)

func _hook_existing() -> void:
	var root: Node = get_tree().root
	if root != null:
		_scan(root)

func _scan(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_scan(c)

# ── 玩家 ──────────────────────────────────────────────────────
func _hook_player(p: Node) -> void:
	_player = p
	_try(p, "player_died", _on_player_died)
	_try(p, "dodge_started", _on_dodge)

func _on_player_died() -> void:
	Sfx.play("player_death")

func _on_dodge(_dir: Vector3, _dur: float) -> void:
	Sfx.play("dodge")

# ── 随从 (templar) ───────────────────────────────────────────
func _hook_templar(t: Node) -> void:
	_try(t, "heal_pulsed", _on_heal)

func _on_heal(_amount: int) -> void:
	Sfx.play("heal")

# ── 敌人 ──────────────────────────────────────────────────────
func _hook_enemy(e: Node) -> void:
	if not e.state_changed.is_connected(_on_enemy_state):
		e.state_changed.connect(_on_enemy_state.bind(e))

# enemy_base.State.ATTACK = 2 → 近战挥击 (爪/咬随机)
func _on_enemy_state(_old_state: int, new_state: int, e: Node) -> void:
	if new_state == 2 and is_instance_valid(e) and e is Node3D:
		var key: String = "claw" if randf() < 0.5 else "bite"
		Sfx.play(key, (e as Node3D).global_position)

# ── 箭矢 / 技能释放 ──────────────────────────────────────────
func _on_arrow_spawned(_n: Node) -> void:
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	if _last_shoot_t >= 0.0 and t - _last_shoot_t < SHOOT_DEBOUNCE:
		return   # 多重射击/连发合并成一次射击音
	_last_shoot_t = t
	Sfx.play("arrow_shoot")

# ── 战斗命中 (CombatManager.hit_landed) ──────────────────────
func _on_hit(_attacker, _target, _damage: int, is_crit: bool, element: String, hit_position: Vector3, _hit_dir: Vector3) -> void:
	var key: String = "impact_flesh"
	match element:
		"frost", "ice", "cold":
			key = "frost_explode"
		"fire":
			key = "fire_explode"
		"poison":
			key = "poison"
		"lightning", "thunder":
			key = "thunder"
		_:
			key = "slash" if is_crit else "impact_flesh"
	Sfx.play(key, hit_position)

func _on_enemy_killed(enemy, _killer, _overkill: int, _kill_dir: Vector3) -> void:
	var pos = null
	if is_instance_valid(enemy) and enemy is Node3D:
		pos = (enemy as Node3D).global_position
	Sfx.play("enemy_death", pos)

func _on_player_damaged(_amount: int, _source) -> void:
	Sfx.play("player_hurt")

# ── 背包 / UI ────────────────────────────────────────────────
func _on_pickup(_item) -> void:
	Sfx.play("ui_use_item")

func _on_equip(_slot: int, _item) -> void:
	Sfx.play("ui_equip")

func _on_unequip(_slot: int, _item) -> void:
	Sfx.play("ui_unequip")

# ── 进度 / 秘境 ──────────────────────────────────────────────
func _on_level_up(_new_level: int, _unlocked: Array) -> void:
	Sfx.play("buff_atk")

func _on_guardian_ready() -> void:
	Sfx.play("encounter")

func _on_run_cleared(_clear_time_sec: float, _kill_count: int) -> void:
	Sfx.play("revive")

# ── 脚步 ──────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player) or not (_player is CharacterBody3D):
		return
	var cb := _player as CharacterBody3D
	var planar: float = Vector2(cb.velocity.x, cb.velocity.z).length()
	var grounded: bool = cb.is_on_floor()
	if planar > STEP_SPEED_MIN and grounded:
		_step_t -= delta
		if _step_t <= 0.0:
			_step_t = STEP_INTERVAL
			Sfx.play("step_rock", cb.global_position, -6.0)
	else:
		_step_t = 0.0
