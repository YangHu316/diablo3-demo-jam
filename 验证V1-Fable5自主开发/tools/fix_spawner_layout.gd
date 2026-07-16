extends SceneTree

# 生成器布点修正:对 play 场景内每个 Sp* 生成器,环形搜索最近的
# 「可走 + 净空≥TARGET_CLEAR」合法点,回写 .tscn(打印 旧→新 便于审计)。
# Run: Godot --headless --path . --script res://验证V1-Fable5自主开发/tools/fix_spawner_layout.gd

const WalkableArea := preload("res://验证V1-Fable5自主开发/scripts/walkable_area.gd")
const PLAY := "res://验证V1-Fable5自主开发/scenes/level_03_dh_play.tscn"
const TARGET_CLEAR := 2.0

func _init() -> void:
	var abs_path := ProjectSettings.globalize_path(PLAY)
	var txt := FileAccess.get_file_as_string(abs_path)
	var re := RegEx.new()
	re.compile("(\\[node name=\"(Sp[^\"]+)\"[^\\]]*\\]\\ntransform = Transform3D\\(1, 0, 0, 0, 1, 0, 0, 0, 1, )([-0-9.]+), ([-0-9.]+), ([-0-9.]+)(\\))")
	var moved := 0
	var out := txt
	for m in re.search_all(txt):
		var nm := m.get_string(2)
		var x := float(m.get_string(3))
		var z := float(m.get_string(5))
		var p := Vector2(x, z)
		if WalkableArea.is_walkable(p) and WalkableArea.clearance(p) >= TARGET_CLEAR:
			continue
		var fixed := _nearest_valid(p)
		if fixed == Vector2.INF:
			printerr("  ✗ ", nm, " 无法修正 @(", x, ",", z, ")")
			continue
		print("  ", nm, " (%.1f,%.1f) → (%.1f,%.1f) clear=%.2f" % [x, z, fixed.x, fixed.y, WalkableArea.clearance(fixed)])
		var old_seg := m.get_string(0)
		var new_seg := m.get_string(1) + ("%.2f, 0, %.2f" % [fixed.x, fixed.y]) + m.get_string(6)
		out = out.replace(old_seg, new_seg)
		moved += 1
	var f := FileAccess.open(abs_path, FileAccess.WRITE)
	f.store_string(out)
	f.close()
	print("[fix] 修正 ", moved, " 个生成器布点 → ", PLAY)
	quit(0)

func _nearest_valid(c: Vector2) -> Vector2:
	if WalkableArea.is_walkable(c) and WalkableArea.clearance(c) >= TARGET_CLEAR:
		return c
	var r := 0.5
	while r <= 14.0:
		var steps := maxi(8, int(TAU * r / 0.7))
		for i in steps:
			var a := TAU * float(i) / float(steps)
			var p := c + Vector2(cos(a), sin(a)) * r
			if WalkableArea.is_walkable(p) and WalkableArea.clearance(p) >= TARGET_CLEAR:
				return p
		r += 0.5
	return Vector2.INF
