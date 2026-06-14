extends Node3D

# 集成测试驱动 (作为普通场景运行, autoload 全活): 真实场景树 + 物理跑「精英进度球」全链路.
# 运行: godot --headless --path . res://tools/itest_elite_progress_ball.tscn
#
# 不是单元数学 (那已由 tools/verify_elite_progress_ball.gd 8/8 覆盖). 本测经真实链路:
#   CombatManager.enemy_killed -> LootManager._on_enemy_killed -> _maybe_spawn_progress_balls
#   -> 查 DataTables.get_elite_ball_count/per_ball_pct -> 实例化 progress_ball.tscn 挂进
#   current_scene(=本测根) -> 玩家走进 Area3D body_entered -> progress_ball._absorb
#   -> RiftManager.add_progress_ball(pct=0.05) -> progress += 0.05*goal(106)=5.3 -> 球 queue_free.
#
# 关键 headless 处理:
#   - Area3D body_entered 需若干物理帧 + 双方在树内且 layer/mask 重叠 -> 移玩家后等 >8 帧再断言.
#   - _attach_to_world 把球加进 current_scene (=本测根) -> 经 get_nodes_in_group("loot") 找球.
#   - 每相 reset_rift() 再读 progress 断言 DELTA, 口径 pct*goal = 0.05*106 = 5.3/球.

const PROGRESS_PER_BALL: float = 5.3        # 0.05 (per_ball_pct) * 106 (goal)
const EPS: float = 0.01

var _player: CharacterBody3D
var _rm: Node                                # /root/RiftManager
var _lm: Node                                # /root/LootManager
var _dt: Node                                # /root/DataTables
var _cm: Node                                # /root/CombatManager

var _step: int = 0
var _phase: int = 0
var _fails: int = 0
var _checks: int = 0

# 当前相聚焦的一组球 (spawn 后缓存, 供逐个吸取 + 全清断言).
var _balls: Array = []
var _target_ball: Node3D = null
var _progress_before: float = 0.0

func _ready() -> void:
	_rm = get_node_or_null("/root/RiftManager")
	_lm = get_node_or_null("/root/LootManager")
	_dt = get_node_or_null("/root/DataTables")
	_cm = get_node_or_null("/root/CombatManager")
	if _rm == null or _lm == null or _dt == null or _cm == null:
		push_error("FAIL: autoload 未就绪 (RiftManager/LootManager/DataTables/CombatManager)")
		get_tree().quit(1)
		return

	# 校验数值表前置条件 (口径 5.3/球 成立的根基).
	_checks += 1
	var blue_n: int = _dt.get_elite_ball_count("elite_blue")
	var yellow_n: int = _dt.get_elite_ball_count("champion_yellow")
	var pct: float = _dt.get_elite_per_ball_pct("elite_blue")
	if blue_n != 1 or yellow_n != 2 or abs(pct * float(_rm.goal) - PROGRESS_PER_BALL) > EPS:
		_fail("⓪数值表前置: blue球=%d 期1, yellow球=%d 期2, pct*goal=%.3f 期%.3f" % [blue_n, yellow_n, pct * float(_rm.goal), PROGRESS_PER_BALL])
	else:
		print("OK⓪ 数值表: elite_blue=1球 champion_yellow=2球 每球进度=5.3 (0.05*106)")

	_player = load("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.global_position = Vector3(0, 0.5, 50)        # 远离落点, 避免误吸

	_rm.reset_rift()
	print("itest: 场景搭建完成, 开始物理步进 (精英进度球全链路)...")

func _physics_process(_delta: float) -> void:
	_step += 1
	match _phase:
		# ── A1: 杀 elite_blue -> 恰好 spawn 1 个球 ──
		0:
			_kill_elite("elite_blue", Vector3(0, 0.5, 0))
			if _step > 8:
				_balls = _find_loot_balls()
				_checks += 1
				if _balls.size() != 1:
					_fail("①击杀 elite_blue 期 spawn 1 球, 实得 %d" % _balls.size())
				else:
					print("OK① 击杀 elite_blue → 真实链路 spawn 恰好 1 个进度球")
				_target_ball = _balls[0] if _balls.size() > 0 else null
				_progress_before = _rm.progress
				_phase = 1
				_step = 0
		# ── B1: 玩家走进该球 -> progress += 5.3, 球 queue_free ──
		1:
			if _target_ball != null and is_instance_valid(_target_ball):
				_player.global_position = _target_ball.global_position
			if _step > 8:
				_checks += 1
				var delta: float = _rm.progress - _progress_before
				if abs(delta - PROGRESS_PER_BALL) > EPS:
					_fail("②吸取 1 球: progress 增量=%.3f 期 %.3f" % [delta, PROGRESS_PER_BALL])
				else:
					print("OK② 玩家走进球 → body_entered 自动吸取, progress +5.3")
				_checks += 1
				if _find_loot_balls().size() != 0:
					_fail("②吸取后仍残留 %d 个 loot 球" % _find_loot_balls().size())
				else:
					print("OK② 吸取后球已 queue_free, 场景内无残留 loot 球")
				_player.global_position = Vector3(0, 0.5, 50)
				_phase = 2
				_step = 0
		# ── A2: 杀 champion_yellow -> 恰好 spawn 2 个球 ──
		2:
			_rm.reset_rift()
			_kill_elite("champion_yellow", Vector3(0, 0.5, 0))
			if _step > 3:
				_balls = _find_loot_balls()
				_checks += 1
				if _balls.size() != 2:
					_fail("③击杀 champion_yellow 期 spawn 2 球, 实得 %d" % _balls.size())
				else:
					print("OK③ 击杀 champion_yellow → 真实链路 spawn 恰好 2 个进度球")
				_progress_before = _rm.progress
				_phase = 3
				_step = 0
		# ── B2: 逐个吸取 2 球 -> progress += 10.6, 全部 queue_free ──
		3:
			# 把玩家钉在仍存活的第一个球上, 依次吸完.
			var alive: Array = _find_loot_balls()
			if alive.size() > 0:
				_player.global_position = (alive[0] as Node3D).global_position
			if _step > 16:
				_checks += 1
				var delta2: float = _rm.progress - _progress_before
				if abs(delta2 - PROGRESS_PER_BALL * 2.0) > EPS:
					_fail("④吸取 2 球: progress 增量=%.3f 期 %.3f" % [delta2, PROGRESS_PER_BALL * 2.0])
				else:
					print("OK④ 走进 2 球依次吸取, progress +10.6 (2*5.3)")
				_checks += 1
				if _find_loot_balls().size() != 0:
					_fail("④吸取后仍残留 %d 个 loot 球" % _find_loot_balls().size())
				else:
					print("OK④ 2 球全部 queue_free, 场景内无残留")
				_player.global_position = Vector3(0, 0.5, 50)
				_phase = 4
				_step = 0
		# ── 守门人: 杀普通怪 (trash) -> 不掉任何进度球 ──
		4:
			_rm.reset_rift()
			_kill_elite("trash", Vector3(0, 0.5, 0))
			if _step > 4:
				_checks += 1
				if _find_loot_balls().size() != 0:
					_fail("⑤击杀非精英 (trash) 不应掉进度球, 实得 %d" % _find_loot_balls().size())
				else:
					print("OK⑤ 击杀非精英 (trash) → 0 进度球 (仅精英掉球)")
				_phase = 5
				_step = 0
		# ── 防重复吸取: 同一球第二次 body_entered 不再加进度 (_picked 守卫) ──
		5:
			_rm.reset_rift()
			_kill_elite("elite_blue", Vector3(0, 0.5, 0))
			if _step > 3:
				_run_no_double_absorb()
				_finish()

# 真实链路造一次击杀: 实例化最小 enemy 节点, 挂 monster_id meta, 发 CombatManager.enemy_killed.
# LootManager / RiftManager 均监听此信号 -> 与正式运行完全同源.
func _kill_elite(monster_id: String, at: Vector3) -> void:
	if _step != 1:
		return        # 每相只造一次击杀 (在该相首帧)
	var enemy := Node3D.new()
	enemy.set_meta("monster_id", monster_id)
	add_child(enemy)
	enemy.global_position = at
	_cm.enemy_killed.emit(enemy, null, 0, Vector3.ZERO)
	# enemy 仅作信号载体, spawn/加权已在 emit 同步完成, 立即移除避免污染.
	enemy.queue_free()

# 防重复吸取: 取一个球, 手动触发两次 _on_body_entered(player), 断言只加一次进度.
func _run_no_double_absorb() -> void:
	var balls: Array = _find_loot_balls()
	_checks += 1
	if balls.size() != 1:
		_fail("⑥防重复: 期 spawn 1 球, 实得 %d" % balls.size())
		return
	var ball: Node = balls[0]
	var before: float = _rm.progress
	# 第一次进入 -> 吸取 (_picked=false -> true).
	ball._on_body_entered(_player)
	var after_first: float = _rm.progress
	# 第二次进入 (queue_free 前同帧重入) -> _picked=true 守卫应直接 return, 不再加.
	ball._on_body_entered(_player)
	var after_second: float = _rm.progress
	var d1: float = after_first - before
	var d2: float = after_second - after_first
	if abs(d1 - PROGRESS_PER_BALL) > EPS or abs(d2) > EPS:
		_fail("⑥防重复吸取: 首次增量=%.3f 期5.3, 二次增量=%.3f 期0" % [d1, d2])
	else:
		print("OK⑥ 同球二次 body_entered → _picked 守卫拦截, progress 不重复累加")

# current_scene(=本测根) 下所有 ProgressBall (group 'loot' + 有 pct/_picked). 未死的 (非 _picked).
func _find_loot_balls() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("loot"):
		if not is_instance_valid(n):
			continue
		if n.is_queued_for_deletion():
			continue
		# 仅进度球 (有 pct 与 _picked); loot_drop 不含这俩.
		if "pct" in n and "_picked" in n and not n._picked:
			out.append(n)
	return out

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	_fails += 1

func _finish() -> void:
	print("\n==== itest_elite_progress_ball: %d/%d 判定通过 ====" % [_checks - _fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)
