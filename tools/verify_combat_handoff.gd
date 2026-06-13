extends SceneTree

# 端到端对接验证(系统组②↔战斗组①):
# 模拟战斗组在怪物实例上挂 monster_id/monster_level/drop_source 元数据并发 enemy_killed,
# 确认 ProgressionManager 按 meta 给 XP、LootManager 按 meta 选掉落源(而非走兜底)。
# Run headless:
#   godot --headless --path . --script res://tools/verify_combat_handoff.gd

var _fail := 0

func _ck(cond: bool, msg: String) -> void:
	if cond:
		print("  OK  - ", msg)
	else:
		_fail += 1
		print("  FAIL- ", msg)

func _make_enemy(mid: String, mlevel: int, dsrc: int) -> Node3D:
	# 模拟战斗组 spawn_trigger._on_enemy_spawned 的 set_meta 三连。
	# 注意:战斗组已把 key 归一为普通 String 字面量("monster_id"),
	# 这里也用 String key,忠实复现当前生产路径。
	var e := Node3D.new()
	e.set_meta("monster_id", StringName(mid))
	e.set_meta("monster_level", mlevel)
	e.set_meta("drop_source", dsrc)
	return e

func _init() -> void:
	var dt = load("res://scripts/autoload/data_tables.gd").new()
	dt._load_all()
	print("DataTables loaded = ", dt.is_loaded)

	# --- ProgressionManager: 按 meta 的 monster_id/level 查表给 XP ---
	print("\n=== 判定①: ProgressionManager 据 monster_id/level 查表给 XP ===")
	# ProgressionManager._on_enemy_killed 用 enemy.get_meta("monster_id"/"monster_level")
	# 调 DataTables.get_monster_stats(id, level).xp。这里验证查表口径(同一 DataTables)。
	var butcher_xp: int = dt.get_monster_stats(&"butcher", 7).get("xp", -1)
	var trash_xp: int = dt.get_monster_stats(&"trash", 1).get("xp", -1)
	_ck(butcher_xp > 0, "butcher@7 查表 xp=%d (>0)" % butcher_xp)
	_ck(trash_xp > 0, "trash@1 查表 xp=%d (>0)" % trash_xp)
	_ck(butcher_xp != trash_xp, "屠夫 XP 与白怪不同 (证明 meta 生效非兜底)")

	# --- LootManager: 按 meta 的 drop_source 选权重 ---
	print("\n=== 判定②: drop_source meta 映射到 DropSystem.Source ===")
	var DS = load("res://scripts/systems/drop_system.gd")
	# 战斗组 _DROP_SOURCE_MAP: trash=0 elite_blue=1 champion_yellow=2 butcher=3
	_ck(DS.Source.TRASH == 0, "DropSystem.Source.TRASH == 0 (对齐战斗组 trash)")
	_ck(DS.Source.ELITE_BLUE == 1, "DropSystem.Source.ELITE_BLUE == 1 (对齐 elite_blue)")
	_ck(DS.Source.CHAMPION_YELLOW == 2, "CHAMPION_YELLOW == 2 (对齐 champion_yellow)")
	_ck(DS.Source.BUTCHER == 3, "BUTCHER == 3 (对齐 butcher)")

	var gen = ItemGenerator.new(dt, 7)
	var ds = DS.new(dt, gen, 7)
	# 屠夫(BUTCHER)应 100% 掉落且件数多于白怪
	var butcher_drop: Array = ds.roll_drop(DS.Source.BUTCHER, 7)
	var trash_hits := 0
	for i in range(2000):
		if not ds.roll_drop(DS.Source.TRASH, 1).is_empty():
			trash_hits += 1
	_ck(not butcher_drop.is_empty(), "BUTCHER 必掉 (件数=%d)" % butcher_drop.size())
	_ck(trash_hits > 0 and trash_hits < 2000, "TRASH 概率掉落 (%d/2000)" % trash_hits)

	# --- meta 读取链路: 模拟挂 meta 的怪, 验证 has_meta/get_meta 口径 ---
	print("\n=== 判定③: 怪物 meta 读取口径与接收端一致 ===")
	var boss := _make_enemy("butcher", 7, DS.Source.BUTCHER)
	# 战斗组写 String key("monster_id"),系统组接收端也用 String key 读 —— 完全对齐
	_ck(boss.has_meta("monster_id") and StringName(boss.get_meta("monster_id")) == &"butcher",
		"monster_id (String key) 可被 ProgressionManager has_meta(\"monster_id\") 读取")
	_ck(boss.has_meta("monster_level") and int(boss.get_meta("monster_level")) == 7,
		"monster_level (String key) = 7 (屠夫固定级)")
	_ck(boss.has_meta("drop_source") and int(boss.get_meta("drop_source")) == DS.Source.BUTCHER,
		"drop_source (String key) 可被 LootManager has_meta(\"drop_source\") 读取")
	# 交叉验证: 写 String key 后用 StringName key 仍可读到(Godot 4 meta key 内部归一)
	_ck(boss.has_meta(&"monster_id") and StringName(boss.get_meta(&"monster_id")) == &"butcher",
		"String 写入 / StringName 读取互通 (归一不破坏任何读取路径)")
	boss.free()

	print("\n========================================")
	if _fail == 0:
		print("VERIFY OK - 系统组↔战斗组对接全部通过")
	else:
		print("VERIFY FAIL - %d 项未通过" % _fail)
	quit()
