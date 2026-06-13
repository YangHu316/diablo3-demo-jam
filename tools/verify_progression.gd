extends SceneTree

# Verify ProgressionManager (任务5). Run headless:
#   godot --headless --path . --script res://tools/verify_progression.gd
#
# 注: --script SceneTree 下 autoload 不存在, 手动把 DataTables/ProgressionManager
# 挂到 /root 并直接调方法 (与 verify_data_tables/verify_item_gen 同套路).

var _xp_log: Array = []
var _level_log: Array = []

func _on_xp(cur: int, to_next: int, lv: int) -> void:
	_xp_log.append({ "cur": cur, "to_next": to_next, "lv": lv })

func _on_level(new_level: int, unlocked: Array) -> void:
	_level_log.append({ "lv": new_level, "unlocked": unlocked })
	print("  ★ LEVEL UP -> %d  unlocked=%s" % [new_level, str(unlocked)])

# 假怪: 带 monster_id / monster_level 元数据.
func _fake_enemy(id: StringName, lv: int) -> Node:
	var n := Node.new()
	n.set_meta("monster_id", id)
	n.set_meta("monster_level", lv)
	return n

func _init() -> void:
	# --- 装 DataTables ---
	var DataTablesScript = load("res://scripts/autoload/data_tables.gd")
	var dt = DataTablesScript.new()
	dt.name = "DataTables"
	root.add_child(dt)
	dt._load_all()
	print("DataTables loaded = ", dt.is_loaded)

	# --- 装 ProgressionManager ---
	var PMScript = load("res://scripts/autoload/progression_manager.gd")
	var pm = PMScript.new()
	pm.name = "ProgressionManager"
	pm._data_tables = dt             # 依赖注入: harness 下不走 /root autoload 查找
	root.add_child(pm)
	pm._init_stats_for_level()       # _ready 在此 harness 下不保证触发, 手动初始化
	pm.xp_gained.connect(_on_xp)
	pm.level_up.connect(_on_level)

	var c: XPCurve = dt.xp_curve

	print("\n=== 初始状态 (L1) ===")
	print("  ", pm.get_stats())
	assert(pm.level == 1, "应从 1 级起")
	assert(pm.agility == c.agility_at(1), "L1 敏捷应=%d" % c.agility_at(1))
	assert(pm.vitality == c.vitality_at(1), "L1 体能应=%d" % c.vitality_at(1))
	assert(pm.max_hp == c.max_hp_at(1), "L1 生命应=%d" % c.max_hp_at(1))

	print("\n=== 完成判定①: 击杀给 XP (trash L1, xp=%d) ===" % dt.get_monster_stats(&"trash", 1)["xp"])
	var before: int = pm.current_xp
	pm._on_enemy_killed(_fake_enemy(&"trash", 1), null, 0, Vector3.ZERO)
	print("  current_xp: %d -> %d" % [before, pm.current_xp])
	assert(pm.current_xp == before + dt.get_monster_stats(&"trash", 1)["xp"], "击杀应累计对应 XP")
	assert(_xp_log.size() >= 1, "应发出 xp_gained 信号")

	print("\n=== 完成判定②: 单次大 XP 跨多级 ===")
	# L1->2 需 300, L2->3 需 480, L3->4 需 768. 一次给 800 应到 L3 且余 20.
	pm.level = 1
	pm.current_xp = 0
	_level_log.clear()
	pm.add_xp(800)
	print("  after add_xp(800): level=%d current_xp=%d" % [pm.level, pm.current_xp])
	assert(pm.level == 3, "800 XP 应升到 L3, 实际 %d" % pm.level)
	assert(pm.current_xp == 800 - 300 - 480, "余 XP 应=20, 实际 %d" % pm.current_xp)
	assert(_level_log.size() == 2, "应触发 2 次 level_up (1->2, 2->3)")
	assert(_level_log[0]["lv"] == 2 and _level_log[1]["lv"] == 3, "升级序列应 2,3")

	print("\n=== 完成判定③: 升级带动属性成长 ===")
	print("  L3 stats = ", pm.get_stats())
	assert(pm.agility == c.agility_at(3), "L3 敏捷应=%d 实际 %d" % [c.agility_at(3), pm.agility])
	assert(pm.vitality == c.vitality_at(3), "L3 体能应=%d 实际 %d" % [c.vitality_at(3), pm.vitality])
	assert(pm.max_hp == c.max_hp_at(3), "L3 生命应=%d 实际 %d" % [c.max_hp_at(3), pm.max_hp])

	print("\n=== 完成判定④: 升级解锁钩子 (unlocked payload) ===")
	# L2 应解锁 multishot, L3 解锁 frost_arrow (来自 xp_curve.unlocks).
	assert(c.unlocks_at(2).has("skill_multishot"), "L2 应解锁 skill_multishot")
	assert(_level_log[0]["unlocked"] == c.unlocks_at(2), "level_up payload 应=曲线 unlocks_at(2)")
	assert(_level_log[1]["unlocked"] == c.unlocks_at(3), "level_up payload 应=曲线 unlocks_at(3)")
	print("  L2 unlocked = ", _level_log[0]["unlocked"])
	print("  L3 unlocked = ", _level_log[1]["unlocked"])

	print("\n=== 完成判定⑤: 满级封顶 (XP 不再溢出/不越级) ===")
	pm.level = c.max_level
	pm._init_stats_for_level()
	pm.current_xp = 0
	_level_log.clear()
	pm.add_xp(999999)
	print("  满级后 add_xp(999999): level=%d current_xp=%d" % [pm.level, pm.current_xp])
	assert(pm.level == c.max_level, "满级不应再升")
	assert(_level_log.size() == 0, "满级不应再发 level_up")
	assert(pm.current_xp == 0, "满级经验应停在 0/封顶")

	print("\n=== 缺省元数据兜底 (战斗①接入前可跑通) ===")
	pm.level = 1
	pm.current_xp = 0
	var bare := Node.new()   # 无任何 meta
	pm._on_enemy_killed(bare, null, 0, Vector3.ZERO)
	print("  无 meta 击杀 -> current_xp=%d (用默认怪+玩家等级)" % pm.current_xp)
	assert(pm.current_xp == dt.get_monster_stats(&"trash", 1)["xp"], "兜底应按 trash@L1 给 XP")
	bare.free()

	print("\nVERIFY OK")
	quit()
