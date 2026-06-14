extends Node3D

# 集成测试 (作为普通场景运行, autoload 全活): 真实场景树 + 物理跑「精英进度球」全链路.
# 运行: <godot> --headless --path . res://tools/itest_elite_progress_ball.tscn
#   (按场景路径跑, 非 --script, 故 CombatManager/LootManager/RiftManager/DataTables 等 autoload 全部在线)
#
# 覆盖两大机制:
#   (A) 生成数量: CombatManager.enemy_killed 携带挂 monster_id 的假 Node3D ->
#       LootManager._maybe_spawn_progress_balls 查 DataTables.get_elite_ball_count ->
#       res://scenes/loot/progress_ball.tscn 实例化挂到 current_scene (=本测试根).
#       断言精确球数: elite_blue=1 / champion_yellow=2 / trash(非精英)=0.
#   (B) 吸取: 真实 player.tscn 走到球上 -> Area3D body_entered -> ProgressBall._absorb ->
#       RiftManager.add_progress_ball(pct=0.05) -> progress += 0.05*goal(106)=5.3, 球 queue_free;
#       _picked 防重: 同一球停留多帧只计一次.
#
# 关键 headless 注意:
#   - body_entered 需双方都在树内 + 层/掩码重叠 (球 layer16 mask1, 玩家 layer1) + 等几个物理帧.
#   - LootManager._attach_to_world 把球加到 get_tree().current_scene = 本测试节点; 经 group 'loot' 找球.
#     但 LootDrop(装备) 同样在 'loot' 组, 故按脚本路径 progress_ball.gd 过滤, 只数进度球.
#   - 每个生成用例之间清空残留球, 保证计数独立.

const PLAYER_SCENE: String = "res://scenes/player/player.tscn"
const BALL_SCRIPT_HINT: String = "progress_ball.gd"

var _cm: Node
var _lm: Node
var _rm: Node
var _dt: Node
var _player: CharacterBody3D

var _step: int = 0
var _phase: int = 0
var _fails: int = 0
var _checks: int = 0

# 吸取阶段用: 当前关注的那颗球 + 吸取前的 progress 基准.
var _absorb_ball: Area3D = null
var _progress_before: float = 0.0

func _ready() -> void:
	_cm = get_node_or_null("/root/CombatManager")
	_lm = get_node_or_null("/root/LootManager")
	_rm = get_node_or_null("/root/RiftManager")
	_dt = get_node_or_null("/root/DataTables")
	if _cm == null or _lm == null or _rm == null or _dt == null:
		push_error("FAIL: autoload 未就绪 (CombatManager/LootManager/RiftManager/DataTables)")
		get_tree().quit(1)
		return

	# ⓪ 前置数据校验: 数值表口径与下游断言一致 (1/2/0.05).
	_checks += 1
	var c_blue: int = _dt.get_elite_ball_count("elite_blue")
	var c_yellow: int = _dt.get_elite_ball_count("champion_yellow")
	var c_trash: int = _dt.get_elite_ball_count("trash")
	var pct_blue: float = _dt.get_elite_per_ball_pct("elite_blue")
	if c_blue != 1 or c_yellow != 2 or c_trash != 0 or abs(pct_blue - 0.05) > 0.0001:
		_fail("⓪ DataTables 口径异常 blue=%d yellow=%d trash=%d pct=%.3f (期望 1/2/0/0.05)" % [c_blue, c_yellow, c_trash, pct_blue])
	else:
		print("OK⓪ DataTables 口径: elite_blue=1 球 / champion_yellow=2 球 / trash=0 球 / 每球5%%")

	# 真实玩家进树, 放到原点附近 (layer=1 供球 mask=1 检测).
	_player = load(PLAYER_SCENE).instantiate()
	add_child(_player)
	_player.global_position = Vector3(50, 0.5, 50)   # 先停在远处, 避免误吸生成阶段的球

	# 干净起点: 重置秘境进度 (kill_count/_counted/progress 归零).
	_rm.reset_rift()
	print("itest: 场景搭建完成, 开始物理步进...")

# 玩家 global_position 在 _ready 里赋的 (50,50) 要到下一物理帧才提交到物理空间;
# 若第 1 帧就 spawn 球, 球的 Area3D 会和"仍停在原点"的玩家碰撞体重叠 -> 被误吸.
# 故先空跑几帧让玩家碰撞体落位, 再进入 phase 0.
var _warmup: int = 4

func _physics_process(_delta: float) -> void:
	if _warmup > 0:
		_warmup -= 1
		return
	_step += 1
	match _phase:
		# ── 机制A: 生成数量 ──────────────────────────────
		0:
			# 杀 elite_blue -> 期望恰好 1 颗进度球.
			_clear_balls()
			_emit_kill("elite_blue", Vector3(0, 0, 0))
			_phase = 1
			_step = 0
		1:
			if _step > 2:
				_assert_ball_count("elite_blue", 1, "①")
				_phase = 2
				_step = 0
		2:
			# 杀 champion_yellow -> 期望恰好 2 颗.
			_clear_balls()
			_emit_kill("champion_yellow", Vector3(0, 0, 0))
			_phase = 3
			_step = 0
		3:
			if _step > 2:
				_assert_ball_count("champion_yellow", 2, "②")
				_phase = 4
				_step = 0
		4:
			# 杀 trash (非精英) -> 期望 0 颗球 (白怪靠击杀直接 +1 权重, 不掉球).
			_clear_balls()
			_emit_kill("trash", Vector3(0, 0, 0))
			_phase = 5
			_step = 0
		5:
			if _step > 2:
				_assert_ball_count("trash", 0, "③")
				_phase = 6
				_step = 0
		6:
			# 重复击杀同一假怪 (相同实例) 不应再叠球: 用同一实例触发两次, 仍只产出 ball_count 球?
			# 注: LootManager 不去重 (每次 enemy_killed 都生成); RiftManager 才去重权重.
			# 故此用例验证 RiftManager 防重计数, 见机制B-④. 这里直接进入吸取机制.
			_clear_balls()
			_phase = 7
			_step = 0
		# ── 机制B: 吸取 ────────────────────────────────
		7:
			# 在玩家正下方坐标生成一颗 elite_blue 球, 准备走过去吸取.
			_emit_kill("elite_blue", Vector3(0, 0.5, 0))
			_phase = 8
			_step = 0
		8:
			if _step > 2:
				var balls: Array = _find_balls()
				_checks += 1
				if balls.size() != 1:
					_fail("④ 吸取前应有 1 颗球, 实际 %d" % balls.size())
					_phase = 11   # 跳到收尾
					_step = 0
				else:
					_absorb_ball = balls[0]
					_progress_before = _rm.progress
					print("OK④ 吸取前: 1 颗球就位, progress 基准=%.2f" % _progress_before)
					_phase = 9
					_step = 0
		9:
			# 把玩家移到球的 xz 上 (球 mask 检测玩家 layer1), 等物理帧让 body_entered 触发.
			if _absorb_ball != null and is_instance_valid(_absorb_ball):
				_player.global_position = Vector3(0, 0.5, 0)
			if _step > 10:
				_checks += 1
				var delta_p: float = _rm.progress - _progress_before
				var ball_gone: bool = (_absorb_ball == null) or (not is_instance_valid(_absorb_ball)) or _absorb_ball.is_queued_for_deletion()
				# 0.05 * 106 = 5.3
				if abs(delta_p - 5.3) > 0.01:
					_fail("⑤ 吸取后 progress 增量=%.3f (期望 5.30 = 0.05*106)" % delta_p)
				elif not ball_gone:
					_fail("⑤ 吸取后球未销毁 (queue_free 未触发)")
				else:
					print("OK⑤ 玩家走上球 → body_entered 吸取 → progress +5.30 且球 queue_free")
				_phase = 10
				_step = 0
		10:
			# 防重: 玩家继续停在原位多帧, progress 不应再涨 (_picked 守卫).
			_player.global_position = Vector3(0, 0.5, 0)
			if _step > 10:
				_checks += 1
				var total_delta: float = _rm.progress - _progress_before
				if abs(total_delta - 5.3) > 0.01:
					_fail("⑥ 防重失败: 停留多帧后总增量=%.3f (期望仍为 5.30)" % total_delta)
				else:
					print("OK⑥ _picked 防重: 玩家停留多帧 progress 不再叠加 (总增 5.30)")
				_phase = 11
				_step = 0
		11:
			# ⑦ RiftManager 同实例击杀去重: 同一假怪实例 enemy_killed 两次, kill_count 只 +1.
			_checks += 1
			var fake: Node3D = _make_fake_enemy("trash", Vector3(0, 0, 0))
			var kc_before: int = _rm.kill_count
			_cm.enemy_killed.emit(fake, null, 0, Vector3.ZERO)
			_cm.enemy_killed.emit(fake, null, 0, Vector3.ZERO)   # 同实例第二次
			var kc_delta: int = _rm.kill_count - kc_before
			fake.free()
			if kc_delta != 1:
				_fail("⑦ 同实例击杀两次 kill_count 增量=%d (期望 1, RiftManager._counted 去重)" % kc_delta)
			else:
				print("OK⑦ RiftManager 同实例击杀去重: 两次 emit → kill_count 只 +1")
			_clear_balls()
			_finish()

# ── 工具方法 ────────────────────────────────────────────────

# 构造一只挂 monster_id 元数据的假怪 (Node3D, 已进树后再设坐标), 供 enemy_killed 携带.
func _make_fake_enemy(monster_id: String, pos: Vector3) -> Node3D:
	var e := Node3D.new()
	e.set_meta("monster_id", monster_id)
	add_child(e)                 # 先进树, 否则 global_position 设值报 !is_inside_tree
	e.global_position = pos
	return e

# 触发一次真实击杀信号: 加假怪进树 → emit enemy_killed → 移除假怪 (球已独立挂世界).
func _emit_kill(monster_id: String, pos: Vector3) -> void:
	var fake: Node3D = _make_fake_enemy(monster_id, pos)
	_cm.enemy_killed.emit(fake, null, 0, Vector3.ZERO)
	# 球由 LootManager 加到 current_scene; 假怪已无用, 立即移除.
	fake.free()

# group 'loot' 中按脚本路径过滤出 ProgressBall (排除 LootDrop 装备).
func _find_balls() -> Array:
	var out: Array = []
	for n in get_tree().get_nodes_in_group("loot"):
		if not is_instance_valid(n):
			continue
		if n.is_queued_for_deletion():
			continue
		var scr: Script = n.get_script()
		if scr != null and String(scr.resource_path).ends_with(BALL_SCRIPT_HINT):
			out.append(n)
	return out

# 清空残留进度球 (用例间隔离). 直接 free 立即生效, 不等 queue_free.
func _clear_balls() -> void:
	for n in _find_balls():
		if is_instance_valid(n):
			n.free()

func _assert_ball_count(label: String, expect: int, tag: String) -> void:
	_checks += 1
	var balls: Array = _find_balls()
	if balls.size() != expect:
		_fail("%s 杀 %s 期望 %d 颗球, 实际 %d" % [tag, label, expect, balls.size()])
	else:
		print("OK%s 杀 %s → 恰好生成 %d 颗进度球 (真实 LootManager 链路)" % [tag, label, expect])

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	_fails += 1

func _finish() -> void:
	print("\n==== itest_elite_progress_ball: %d/%d 判定通过 ====" % [_checks - _fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)
