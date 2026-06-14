extends SceneTree

# Headless 验证: V3.0 大秘境守门人固定爆装 + 小怪零掉 (boss_drop_list.csv).
# 运行: godot --headless --path . --script res://tools/verify_boss_drop.gd

func _init() -> void:
	var fails: int = 0
	var checks: int = 0

	# 直接解析 boss_drop_list.csv (与 DataTables._load_boss_drops 同口径), 避免依赖 autoload 树.
	var rows: Array = _read_boss_csv("res://数值表/boss_drop_list.csv")

	# 判定①: 解析出 14 件 (12 橙 + 2 绿), 末行"约束"已跳过.
	checks += 1
	if rows.size() != 14:
		push_error("FAIL①: 期望 14 件爆装, 实得 %d" % rows.size()); fails += 1
	else:
		print("OK① 爆装件数 = 14")

	# 判定②: is_set=true 恰 2 件 (群龙猎手·肩铠/护腕).
	checks += 1
	var set_count: int = 0
	for r in rows:
		if bool(r["is_set"]):
			set_count += 1
	if set_count != 2:
		push_error("FAIL②: 期望 2 件套装绿, 实得 %d" % set_count); fails += 1
	else:
		print("OK② 套装绿 = 2")

	# 判定③: 通过 DataTables 构造 ItemInstance, quality 全 = LEGENDARY (严禁橙/绿外品质).
	checks += 1
	var dt = load("res://scripts/autoload/data_tables.gd").new()
	dt._load_legendaries()       # 部分内部用, 安全空载
	dt._load_boss_drops()
	var items: Array = dt.get_boss_drop_items()
	var bad_q: int = 0
	for it in items:
		if it.quality != 4:   # ItemInstance.Quality.LEGENDARY = 4
			bad_q += 1
	if items.size() != 14 or bad_q != 0:
		push_error("FAIL③: items=%d, 非LEGENDARY=%d" % [items.size(), bad_q]); fails += 1
	else:
		print("OK③ 14 件 quality 全 LEGENDARY")

	# 判定④: is_set 旁路 display_color 返回绿; 普通橙件返回橙.
	checks += 1
	var ok4: bool = true
	for it in items:
		var c: Color = it.display_color()
		if it.is_set and not _approx(c, Color(0.13, 0.85, 0.18)):
			ok4 = false
		if not it.is_set and not _approx(c, Color(1.0, 0.55, 0.0)):
			ok4 = false
	if not ok4:
		push_error("FAIL④: display_color 绿/橙旁路不符"); fails += 1
	else:
		print("OK④ 绿件显示绿/橙件显示橙")

	# 判定⑤: 两枚戒指落不同槽 (RING_1=9, RING_2=10).
	checks += 1
	var ring_slots: Array = []
	for it in items:
		if it.slot == 9 or it.slot == 10:
			ring_slots.append(it.slot)
	ring_slots.sort()
	if ring_slots != [9, 10]:
		push_error("FAIL⑤: 戒指槽位 %s, 期望 [9,10]" % str(ring_slots)); fails += 1
	else:
		print("OK⑤ 两戒分落 RING_1/RING_2")

	# 判定⑥: DropSystem 小怪源全部零掉; 守门人(BUTCHER)爆 14 件.
	checks += 1
	var gen = load("res://scripts/systems/item_generator.gd").new(dt)
	var ds = load("res://scripts/systems/drop_system.gd").new(dt, gen, 1)
	var trash_total: int = 0
	for i in range(500):
		trash_total += ds.roll_drop(0, 1).size()   # Source.TRASH=0
		trash_total += ds.roll_drop(1, 1).size()   # ELITE_BLUE=1
		trash_total += ds.roll_drop(2, 1).size()   # CHAMPION_YELLOW=2
	var boss_items: Array = ds.roll_drop(3, 1)      # BUTCHER=3
	if trash_total != 0:
		push_error("FAIL⑥: 小怪应零掉, 实掉 %d" % trash_total); fails += 1
	elif boss_items.size() != 14:
		push_error("FAIL⑥: 守门人应爆 14 件, 实得 %d" % boss_items.size()); fails += 1
	else:
		print("OK⑥ 小怪零掉(500×3源=0) / 守门人爆 14 件")

	print("\n==== verify_boss_drop: %d/%d 判定通过 ====" % [checks - fails, checks])
	quit(1 if fails > 0 else 0)

func _read_boss_csv(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var headers: PackedStringArray = f.get_csv_line()
	while not f.eof_reached():
		var cols: PackedStringArray = f.get_csv_line()
		if cols.size() <= 1 and (cols.is_empty() or cols[0] == ""):
			continue
		var row: Dictionary = {}
		for i in headers.size():
			row[String(headers[i]).strip_edges()] = String(cols[i]).strip_edges() if i < cols.size() else ""
		if not String(row.get("序号", "")).is_valid_int():
			continue
		out.append({
			"name": String(row.get("名称", "")),
			"is_set": String(row.get("is_set", "false")).to_lower() == "true",
		})
	f.close()
	return out

func _approx(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02
