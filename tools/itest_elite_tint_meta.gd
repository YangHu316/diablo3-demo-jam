extends Node3D

# 集成测试 (真实场景路径): 验「场景里直接摆的精英实例」经 elite_tint.gd 运行期补挂
# monster_id meta -> LootManager 才能识别为精英掉进度球.
#
# 背景 bug「现在的场景里似乎不会掉球」: 关卡里的精英是「直接摆的 enemy 实例 + EliteTint 染色」,
# 不走 spawn_trigger, 故没人给它挂 monster_id meta. LootManager._maybe_spawn_progress_balls
# 因 has_meta('monster_id') 失败而直接 return -> 不掉球.
# 修复: elite_tint.gd 增 @export monster_id, _ready() 运行期给父节点(精英)挂 meta.
#
# 本测实例化 4 个真实精英组蓝图, 找到其中的「Elite」节点, 断言:
#   (1) Elite 节点确实挂上了 monster_id meta;
#   (2) meta 值 = 蓝图里配的 elite id (dog=champion_yellow, 其余=elite_blue);
#   (3) 该 id 经真实 DataTables 查到 >0 的进度球数 (即 LootManager 会掉球).
#
# 运行: <godot> --headless --path . res://tools/itest_elite_tint_meta.tscn

# 精英组蓝图 -> 期望 monster_id.
const CASES := {
	"res://scenes/enemies/groups/elite/elite_group_dog.tscn": &"champion_yellow",
	"res://scenes/enemies/groups/elite/elite_group_zombie.tscn": &"elite_blue",
	"res://scenes/enemies/groups/elite/elite_group_archer.tscn": &"elite_blue",
	"res://scenes/enemies/groups/elite/elite_group_skeleton_guard.tscn": &"elite_blue",
}

var _dt: Node
var _checks: int = 0
var _fails: int = 0

func _ready() -> void:
	_dt = get_node_or_null("/root/DataTables")
	if _dt == null or not _dt.has_method("get_elite_ball_count"):
		push_error("FAIL: DataTables 未就绪")
		get_tree().quit(1)
		return

	for path in CASES.keys():
		_check_scene(String(path), CASES[path])

	print("\n==== itest_elite_tint_meta: %d/%d 判定通过 ====" % [_checks - _fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)

func _check_scene(path: String, expect_id: StringName) -> void:
	if not ResourceLoader.exists(path):
		_fail("%s: 蓝图不存在" % path)
		return
	var root: Node = load(path).instantiate()
	add_child(root)                       # 入树触发 elite_tint._ready() 补挂 meta.

	var elite: Node = _find_elite(root)
	# 断言 1: 找到 Elite 节点.
	_checks += 1
	if elite == null:
		_fail("%s: 未找到 Elite 节点" % path)
		root.queue_free()
		return
	print("OK 找到 Elite 节点: %s (%s)" % [elite.name, path.get_file()])

	# 断言 2: Elite 挂上了 monster_id meta 且值正确.
	_checks += 1
	if not elite.has_meta("monster_id"):
		_fail("%s: Elite 缺 monster_id meta (elite_tint 未补挂 -> LootManager 不掉球)" % path.get_file())
	elif StringName(elite.get_meta("monster_id")) != expect_id:
		_fail("%s: monster_id=%s (期望 %s)" % [path.get_file(), elite.get_meta("monster_id"), expect_id])
	else:
		print("OK %s: Elite.monster_id = %s ✓" % [path.get_file(), expect_id])

	# 断言 3: 该 id 经真实 DataTables 查到 >0 球数 (LootManager 会掉球).
	_checks += 1
	var bc: int = _dt.get_elite_ball_count(String(expect_id))
	if bc <= 0:
		_fail("%s: DataTables.get_elite_ball_count(%s)=%d (期望 >0)" % [path.get_file(), expect_id, bc])
	else:
		print("OK %s: DataTables 查 %s -> %d 个进度球" % [path.get_file(), expect_id, bc])

	root.queue_free()

# 在精英组里找「Elite」实例 (挂了 EliteTint 子节点的那个 enemy_base).
func _find_elite(root: Node) -> Node:
	for c in root.get_children():
		if c.name == "Elite":
			return c
		# 兜底: 任意挂了 elite_tint(有 monster_id 属性) 子节点的节点的父.
		for gc in c.get_children():
			if &"monster_id" in gc:
				return c
	return null

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	_fails += 1
