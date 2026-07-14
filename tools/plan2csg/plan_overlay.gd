extends SceneTree

# 重叠对比:描迹轮廓(level_trace.json)栅格化 vs 引擎俯拍(capture png + bounds sidecar)
#   → IoU 重合度 + 红绿重叠图(红=仅原图 / 绿=仅引擎 / 白=重合)。
# Run: Godot --headless --path . --script res://tools/plan2csg/plan_overlay.gd

const CFG_PATH := "res://tools/plan2csg/plan_config.json"
const CAP_PNG := "res://tools/_capture/level_03_csg_topdown.png"
const OUT_PNG := "res://tools/_capture/plan_overlay.png"
const CELL := 0.15   # 世界单位/格

func _init() -> void:
	var cfg: Dictionary = _load_json(CFG_PATH)
	var tr: Dictionary = _load_json(String(cfg["trace_json"]))
	var cap_bounds: Dictionary = _load_json(CAP_PNG + ".bounds.json")
	var cap := Image.load_from_file(ProjectSettings.globalize_path(CAP_PNG))
	if tr.is_empty() or cap_bounds.is_empty() or cap == null:
		printerr("FAIL: 缺输入(trace json / capture png / bounds sidecar)"); quit(1); return
	cap.convert(Image.FORMAT_RGBA8)
	var loops: Array = tr["loops"]

	# 世界包围盒(以描迹为准,外扩 2)
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for lp in loops:
		for p in lp["pts"]:
			mn = mn.min(Vector2(p[0], p[1]))
			mx = mx.max(Vector2(p[0], p[1]))
	mn -= Vector2(2, 2)
	mx += Vector2(2, 2)
	var gw := int((mx.x - mn.x) / CELL) + 1
	var gh := int((mx.y - mn.y) / CELL) + 1

	# 描迹掩码:逐行扫描线奇偶填充(外环+洞环统一取奇偶)
	var ref_mask := PackedByteArray()
	ref_mask.resize(gw * gh)
	for gy in gh:
		var zc := mn.y + (gy + 0.5) * CELL
		var xs: Array[float] = []
		for lp in loops:
			var pts: Array = lp["pts"]
			for k in pts.size():
				var a: Array = pts[k]
				var b: Array = pts[(k + 1) % pts.size()]
				var az := float(a[1])
				var bz := float(b[1])
				if (az <= zc) == (bz <= zc):
					continue
				xs.append(float(a[0]) + (zc - az) / (bz - az) * (float(b[0]) - float(a[0])))
		xs.sort()
		var i := 0
		while i + 1 < xs.size():
			var x0 := xs[i]
			var x1 := xs[i + 1]
			var g0 := int(ceil((x0 - mn.x) / CELL - 0.5))
			var g1 := int(floor((x1 - mn.x) / CELL - 0.5))
			for gx in range(maxi(g0, 0), mini(g1, gw - 1) + 1):
				ref_mask[gy * gw + gx] = 1
			i += 2

	# 俯拍掩码:世界→俯拍像素采样(亮=地面)
	var bx := float(cap_bounds["min_x"])
	var bz := float(cap_bounds["min_z"])
	var bw := float(cap_bounds["size_x"])
	var bh := float(cap_bounds["size_z"])
	var cap_mask := PackedByteArray()
	cap_mask.resize(gw * gh)
	for gy in gh:
		var wz := mn.y + (gy + 0.5) * CELL
		for gx in gw:
			var wx := mn.x + (gx + 0.5) * CELL
			var px := int((wx - bx) / bw * cap.get_width())
			var py := int((wz - bz) / bh * cap.get_height())
			if px < 0 or px >= cap.get_width() or py < 0 or py >= cap.get_height():
				continue
			if cap.get_pixel(px, py).get_luminance() > 0.30:
				cap_mask[gy * gw + gx] = 1

	# IoU + 重叠图
	var inter := 0
	var uni := 0
	var only_ref := 0
	var only_cap := 0
	var ov := Image.create(gw, gh, false, Image.FORMAT_RGB8)
	for i in gw * gh:
		var r := ref_mask[i] == 1
		var c := cap_mask[i] == 1
		var col := Color.BLACK
		if r and c:
			inter += 1; uni += 1; col = Color(0.92, 0.92, 0.92)
		elif r:
			only_ref += 1; uni += 1; col = Color(0.95, 0.15, 0.1)
		elif c:
			only_cap += 1; uni += 1; col = Color(0.1, 0.9, 0.25)
		ov.set_pixel(i % gw, i / gw, col)
	ov.save_png(ProjectSettings.globalize_path(OUT_PNG))
	# 诊断:把描迹轮廓按 sidecar 映射画到俯拍图上(红线),检查线是否贴合可见地面边缘
	var ann := cap.duplicate()
	ann.convert(Image.FORMAT_RGB8)
	for lp in loops:
		var pts: Array = lp["pts"]
		for k in pts.size():
			var a: Array = pts[k]
			var b: Array = pts[(k + 1) % pts.size()]
			var pa := Vector2((float(a[0]) - bx) / bw * cap.get_width(), (float(a[1]) - bz) / bh * cap.get_height())
			var pb := Vector2((float(b[0]) - bx) / bw * cap.get_width(), (float(b[1]) - bz) / bh * cap.get_height())
			var n := int(maxf(absf(pb.x - pa.x), absf(pb.y - pa.y))) + 1
			for t in n + 1:
				var p := pa.lerp(pb, float(t) / float(n))
				if p.x >= 0 and p.x < cap.get_width() and p.y >= 0 and p.y < cap.get_height():
					ann.set_pixel(int(p.x), int(p.y), Color(1, 0.1, 0.1))
	ann.save_png(ProjectSettings.globalize_path("res://tools/_capture/cap_annotated.png"))
	# 显微裁切:左上大房北/西边(世界 -78..-58, -44..-24)放大 6x
	var cw0 := int((-78.0 - bx) / bw * cap.get_width())
	var cz0 := int((-44.0 - bz) / bh * cap.get_height())
	var cw1 := int((-58.0 - bx) / bw * cap.get_width())
	var cz1 := int((-24.0 - bz) / bh * cap.get_height())
	var crop := Image.create((cw1 - cw0) * 6, (cz1 - cz0) * 6, false, Image.FORMAT_RGB8)
	for py2 in range(cz0, cz1):
		for px2 in range(cw0, cw1):
			var c3: Color = ann.get_pixel(clampi(px2, 0, ann.get_width() - 1), clampi(py2, 0, ann.get_height() - 1))
			for dy in 6:
				for dx in 6:
					crop.set_pixel((px2 - cw0) * 6 + dx, (py2 - cz0) * 6 + dy, c3)
	crop.save_png(ProjectSettings.globalize_path("res://tools/_capture/cap_zoom.png"))
	var iou := float(inter) / float(uni) if uni > 0 else 0.0
	print("[overlay] 格子 ", gw, "x", gh, "  重合=", inter, "  仅原图=", only_ref, "  仅引擎=", only_cap)
	print("[overlay] IoU = %.4f  (仅原图占比 %.2f%%  仅引擎占比 %.2f%%)" % [iou, 100.0 * only_ref / uni, 100.0 * only_cap / uni])
	print("[overlay] 重叠图 → ", OUT_PNG)
	quit(0)

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}
