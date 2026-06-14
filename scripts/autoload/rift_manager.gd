extends Node

# RiftManager (Autoload) — V3.0 单局大秘境进度系统.
#
# 玩法: 击杀小怪累计"进度权重", 满 GOAL 触发守门人 (切 boss_room_play.tscn).
#   权重: 白怪 +1.0 / 时间球 +3.0. 守门人 (guardian/butcher) 不计权重 —— 其死亡 = 单局通关.
#   精英 (蓝名/黄名) 击杀本身不直接加权, 改为掉"进度球", 玩家拾取后 add_progress_ball()
#     按 elites.csv「每球进度%」(5% × goal ≈ 5.3/球) 加进度 (取代旧的精英直接权重 +5/+8).
#
# 监听: CombatManager.enemy_killed(enemy, killer, overkill, dir)
#   据 enemy.get_meta("monster_id") 查权重. 每个 enemy 实例只计一次 (防重复).
# 对外: signal progress_changed(value, goal) / signal guardian_ready()
#   add_time_ball() — 供时间球拾取 (关卡C/美术后续放置) 调用.

signal progress_changed(value: float, goal: float)
signal guardian_ready()
# 守门人 (=屠夫) 死亡 = 单局通关. 携本局用时(秒) 与 击杀总数.
signal run_cleared(clear_time_sec: float, kill_count: int)
# 守门人死亡瞬间先发此信号 (而非直接 run_cleared): boss_room 据此生成 NPC, 玩家与 NPC
# 对话两轮后, 由对话流程回调 emit_run_cleared() 才真正弹结算. 携用时(秒) 与 击杀总数.
signal boss_defeated(clear_time_sec: float, kill_count: int)
# 倒计时归零且进度未满 (未触发守门人) = 任务失败. 携超时时的进度/目标/击杀数.
signal rift_failed(progress: float, goal: float, kill_count: int)

const GOAL: float = 106.0                       # 总权重目标默认值 (~6min 填满). 外部 rm.GOAL 读此常量.
const BOSS_SCENE: String = "res://scenes/levels/boss_room_play.tscn"

# 大秘境时限 (秒). 倒计时归零且进度未满 → 任务失败 (rift_failed). HUD 时间球读此作满刻度.
const RIFT_TIME_LIMIT: float = 120.0

# 运行期有效目标 (默认=GOAL). 速通模式 (--speedrun) 时被 speedrun_test.csv 覆写为 15.
# 内部进度逻辑一律用 goal; progress_changed 信号携带 goal → HUD 自动跟随.
var goal: float = GOAL

# ── 速通测试 override (数值表/测试-1分钟速通) ──────────────────
# 仅命令行带 --speedrun 时生效. 不进正式包: 不带开关 = 走正式值, 零污染.
const SPEEDRUN_CSV: String = "res://数值表/测试-1分钟速通/speedrun_test.csv"
var speedrun: bool = false
var _sr_guardian_hp: int = 0       # >0 时进场覆写守门人 current_health
var _sr_hooked: bool = false       # node_added 钩子已连标志

# monster_id -> 进度权重. 守门人/屠夫 = 0 (不计).
# 注: 精英 (elite_blue/champion_yellow) 不在此 —— 精英不靠"击杀直接加权", 改为掉进度球,
#   玩家拾取后按 elites.csv「每球进度%」经 add_progress_ball() 加进度 (取代精英直接权重).
const WEIGHTS: Dictionary = {
	&"trash": 1.0,
	&"dog": 1.0,
	&"archer": 1.0,
	&"bloated": 1.0,
	&"summoner": 1.0,
	&"skeleton_guard": 1.0,
	&"guardian": 0.0,
	&"butcher": 0.0,
}
# 击杀"不直接喂进度"的怪 (仅计 kill_count). 精英靠进度球加进度, 故击杀本身不加权;
# 不放进 WEIGHTS 是因为 _on_enemy_killed 对未知 id 默认按白怪 +1 兜底 —— 精英需显式排除.
const NO_KILL_PROGRESS: Dictionary = {
	&"elite_blue": true,
	&"champion_yellow": true,
}
const TIME_BALL_WEIGHT: float = 3.0

var progress: float = 0.0
var guardian_triggered: bool = false
# 超时失败已触发标志 (防 _process 重复发 rift_failed; 触发后冻结判定).
var run_failed: bool = false
# 守门人已死 = 已进入"通关流程"(NPC 对话 → 结算). 防 boss_defeated/run_cleared 重复触发.
var run_cleared_triggered: bool = false

# 本局计时起点 (ms) 与 击杀总数 (供结算面板).
var run_start_ms: int = 0
var kill_count: int = 0

# 计时冻结: 进入守门人(=切 boss 关)时, 把"本局已用时(秒)"快照到此并停止计时.
# <0 = 未冻结(计时进行中). >=0 = 已冻结, get_clear_time/get_time_remaining 返回此快照对应值.
var _frozen_clear_sec: float = -1.0

# 已计数的 enemy 实例 id (防同一只怪重复加权).
var _counted: Dictionary = {}

func _ready() -> void:
	run_start_ms = Time.get_ticks_msec()
	_load_speedrun_overrides()
	var cm: Node = get_node_or_null("/root/CombatManager")
	if cm != null and cm.has_signal("enemy_killed"):
		cm.enemy_killed.connect(_on_enemy_killed)

# 重置 (重开一局时调用).
func reset_rift() -> void:
	progress = 0.0
	guardian_triggered = false
	run_failed = false
	run_cleared_triggered = false
	_counted.clear()
	run_start_ms = Time.get_ticks_msec()
	kill_count = 0
	_frozen_clear_sec = -1.0
	progress_changed.emit(progress, goal)

# 每帧检测超时: 倒计时归零 且 进度未满 (未触发守门人) → 任务失败.
# 守门人已触发 (通关路径) 或已失败 → 不再判定. 玩家死亡走 HUD 死亡演出, 与此独立.
func _process(_delta: float) -> void:
	if guardian_triggered or run_failed:
		return
	if get_time_remaining() <= 0.0:
		_trigger_fail()

func _trigger_fail() -> void:
	if run_failed or guardian_triggered:
		return
	run_failed = true
	rift_failed.emit(progress, goal, kill_count)

func _on_enemy_killed(enemy, _killer, _overkill: int, _dir) -> void:
	if enemy == null:
		return
	# 防重复: 同一实例只计一次.
	var key: int = enemy.get_instance_id()
	if _counted.has(key):
		return
	_counted[key] = true
	kill_count += 1   # 击杀总数 (含小怪/精英/守门人)

	var mid: StringName = &"trash"
	if enemy.has_meta("monster_id"):
		mid = StringName(enemy.get_meta("monster_id"))
	# 守门人 (屠夫) 死亡 = 单局通关: 先发 boss_defeated (触发 NPC 对话演出),
	# 不立即结算. 对话两轮结束后由 emit_run_cleared() 才真正弹结算页.
	if mid == &"butcher" or mid == &"guardian":
		if not run_cleared_triggered:
			run_cleared_triggered = true
			boss_defeated.emit(get_clear_time(), kill_count)
		return
	# 精英: 击杀本身不加权 (靠掉落的进度球加进度). 仅计 kill_count (上面已 +1).
	if NO_KILL_PROGRESS.has(mid):
		return
	var w: float = float(WEIGHTS.get(mid, 1.0))   # 未知 id 当白怪 (兜底, 不漏喂进度)
	if w <= 0.0:
		return   # 兜底: 其它零权重 id 不计
	_add_progress(w)

# 时间球拾取 +3.0 (供拾取实体调用).
func add_time_ball() -> void:
	_add_progress(TIME_BALL_WEIGHT)

# 精英进度球拾取: 按"每球进度%"(小数, 5%->0.05) 换算成权重加进度.
# 口径: pct × goal (5% × 106 ≈ 5.3). 供 progress_ball 实体进范围自动吸取时调用.
func add_progress_ball(pct: float) -> void:
	if pct <= 0.0:
		return
	_add_progress(pct * goal)

func _add_progress(amount: float) -> void:
	if guardian_triggered or run_failed:
		return
	progress = minf(progress + amount, goal)
	progress_changed.emit(progress, goal)
	if progress >= goal:
		_trigger_guardian()

func _trigger_guardian() -> void:
	if guardian_triggered:
		return
	guardian_triggered = true
	# 进入守门人 = 切 boss 关: 立即冻结计时 (快照本局已用时), 此后 get_time_remaining 返回定值.
	_frozen_clear_sec = float(Time.get_ticks_msec() - run_start_ms) / 1000.0
	guardian_ready.emit()
	# 满进度 → 切守门人房 (八边形房复用). 延一帧避免在信号回调中切场.
	call_deferred("_go_boss")

func _go_boss() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	if not ResourceLoader.exists(BOSS_SCENE):
		push_warning("RiftManager: missing %s" % BOSS_SCENE)
		return
	tree.change_scene_to_file(BOSS_SCENE)

# ── 结算访问器 ────────────────────────────────────────────────
# NPC 对话两轮结束后调用: 真正发 run_cleared → 结算面板弹出.
# 用冻结的用时快照 (boss 进场已冻结), 故对话期间用时不再增长.
func emit_run_cleared() -> void:
	run_cleared.emit(get_clear_time(), kill_count)

func get_kill_count() -> int:
	return kill_count

func get_clear_time() -> float:
	# 已冻结 (进 boss 关后) → 返回快照值, 计时静止; 否则按实时流逝.
	if _frozen_clear_sec >= 0.0:
		return _frozen_clear_sec
	return float(Time.get_ticks_msec() - run_start_ms) / 1000.0

# 大秘境时限总长 (秒). HUD 时间球读此作满刻度.
func get_time_limit() -> float:
	return RIFT_TIME_LIMIT

# 剩余时间 (秒, clamp 到 [0, RIFT_TIME_LIMIT]). 守门人触发后冻结在触发时刻的剩余.
func get_time_remaining() -> float:
	return clampf(RIFT_TIME_LIMIT - get_clear_time(), 0.0, RIFT_TIME_LIMIT)

# ── 速通 override (仅 --speedrun) ─────────────────────────────
# 读 speedrun_test.csv → 套用差量到运行期值. 不带开关 = 不读 = 正式值.
func _load_speedrun_overrides() -> void:
	if not OS.get_cmdline_user_args().has("--speedrun"):
		return
	if not FileAccess.file_exists(SPEEDRUN_CSV):
		push_warning("RiftManager: 速通开关已开但缺 %s" % SPEEDRUN_CSV)
		return
	var f: FileAccess = FileAccess.open(SPEEDRUN_CSV, FileAccess.READ)
	if f == null:
		return
	var ov: Dictionary = {}
	f.get_line()   # 跳表头
	while not f.eof_reached():
		var cols: PackedStringArray = f.get_line().split(",")
		if cols.size() >= 2 and not cols[0].is_empty():
			ov[cols[0]] = cols[1]
	f.close()
	_apply_overrides(ov)

# 纯套用逻辑 (抽出供 verify 直接测, 不依赖 cmdline/文件).
func _apply_overrides(ov: Dictionary) -> void:
	if String(ov.get("启用", "0")) != "1":
		return   # 表内启用=0 → 视为不开
	speedrun = true
	goal = float(ov.get("进度条目标", goal))
	_sr_guardian_hp = int(ov.get("守门人HP", 0))
	# 守门人 HP/ATK 属战斗① (butcher.gd const). 系统② 不改 const, 进场后 set 实例 current_health.
	# ATK 留正式 90 (README 明示可选); 时间条 120s 当前无限时机制 (N/A).
	if _sr_guardian_hp > 0 and not _sr_hooked and is_inside_tree():
		_sr_hooked = true
		get_tree().node_added.connect(_on_node_added)
	print("[RiftManager] 速通模式生效: goal=%.0f 守门人HP=%d (ATK留正式90/无限时)" % [goal, _sr_guardian_hp])

# 守门人进场即把 current_health 压到速通值. 口径=monster_id meta (与击杀判定同源).
# node_added 早于子节点 _ready (meta 在 butcher.gd _ready 才 set) → 延一帧再查.
func _on_node_added(n: Node) -> void:
	if _sr_guardian_hp <= 0 or n == null:
		return
	call_deferred("_try_apply_guardian_hp", n)

func _try_apply_guardian_hp(n: Node) -> void:
	if _sr_guardian_hp <= 0 or not is_instance_valid(n):
		return
	if not n.has_meta("monster_id"):
		return
	var mid: StringName = StringName(n.get_meta("monster_id"))
	if mid != &"butcher" and mid != &"guardian":
		return
	if n.get_meta("_sr_hp_applied", false):
		return
	if "current_health" in n:
		n.current_health = _sr_guardian_hp
		n.set_meta("_sr_hp_applied", true)
