extends SceneTree

# 平面图描迹:读 关卡/level.png → 阈值掩码 → 连通域清理 → 轮廓环提取(外环+洞环)
#   → Douglas-Peucker 简化 → 输出 level_trace.json + 调试图(掩码/轮廓叠加)。
# Run: Godot --headless --path . --script res://tools/plan2csg/plan_trace.gd
# 规则:
#   floor 像素 = 亮度>=lum_min 且 饱和度<=sat_max(白/浅灰石地+白描边;排除黑底/网格线/彩色图标)
#   封闭非 floor 区域: 近黑(亮度<hole_keep_lum_max 且低饱和)=真洞/内墙 → 保留;
#                      其余(图标:格栅/岩石/水晶/传送门)= 填平为 floor(按要求忽略图标)
#   fill_holes_at_px / keep_holes_at_px 可按像素点强制覆盖分类。

const CFG_PATH := "res://tools/plan2csg/plan_config.json"

func _init() -> void:
	var cfg: Dictionary = _load_json(CFG_PATH)
	if cfg.is_empty():
		printerr("FAIL: 配置读取失败 ", CFG_PATH); quit(1); return
	var img := Image.load_from_file(ProjectSettings.globalize_path(String(cfg["image"])))
	if img == null:
		printerr("FAIL: 图像读取失败 ", cfg["image"]); quit(1); return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("[trace] 图像 ", w, "x", h)

	# ── 1) 阈值掩码(0=非floor / 1=floor / 2=彩色待定) ──
	var lum_min := float(cfg["lum_min"])
	var chroma_sat := float(cfg.get("chroma_sat_min", 0.35))
	var chroma_lum := float(cfg.get("chroma_lum_min", 0.15))
	var mask := PackedByteArray()
	mask.resize(w * h)
	var unknown := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var lum := c.get_luminance()
			var sat := _sat(c)
			if sat >= chroma_sat and lum >= chroma_lum:
				mask[y * w + x] = 2   # 彩色图标像素(水晶/传送门/药瓶):稍后按最近邻类别归并
				unknown += 1
			elif lum >= lum_min:
				mask[y * w + x] = 1
	# 彩色像素多源 BFS:继承最近的非彩色类别 → 图标不在地面轮廓上咬缺口
	var q: Array[int] = []
	for i in w * h:
		if mask[i] != 2:
			var x3 := i % w
			var y3 := i / w
			if (x3 > 0 and mask[i - 1] == 2) or (x3 < w - 1 and mask[i + 1] == 2) \
					or (y3 > 0 and mask[i - w] == 2) or (y3 < h - 1 and mask[i + w] == 2):
				q.append(i)
	var qi := 0
	while qi < q.size():
		var i4: int = q[qi]
		qi += 1
		var x4 := i4 % w
		var y4 := i4 / w
		for n4: int in [i4 - 1, i4 + 1, i4 - w, i4 + w]:
			if n4 < 0 or n4 >= w * h: continue
			if absi((n4 % w) - x4) > 1: continue
			if mask[n4] == 2:
				mask[n4] = mask[i4]
				q.append(n4)
	for i in w * h:
		if mask[i] == 2:
			mask[i] = 0
	print("[trace] 阈值后 floor 像素 = ", _count(mask), " (彩色重分类 ", unknown, " px)")

	# ── 2) floor 连通域:去小杂斑(标题文字/箭头等) ──
	var min_floor := int(cfg["min_floor_area_px"])
	var labels := PackedInt32Array()
	labels.resize(w * h)
	var comp_area: Array[int] = [0]   # label 0 = 未标
	var next_label := 1
	for i in w * h:
		if mask[i] == 1 and labels[i] == 0:
			var area := _flood_label(mask, labels, w, h, i, next_label)
			comp_area.append(area)
			next_label += 1
	for i in w * h:
		if mask[i] == 1 and comp_area[labels[i]] < min_floor:
			mask[i] = 0
	print("[trace] floor 连通域 ", next_label - 1, " 个;保留 ≥", min_floor, "px² 后像素 = ", _count(mask))

	# ── 3) 封闭区域分类:外部背景 flood,其余空区=洞候选 ──
	var outside := PackedByteArray()
	outside.resize(w * h)
	var stack: Array[int] = []
	for x in w:
		if mask[x] == 0: stack.append(x)
		var b := (h - 1) * w + x
		if mask[b] == 0: stack.append(b)
	for y in h:
		var l := y * w
		if mask[l] == 0: stack.append(l)
		var r := y * w + w - 1
		if mask[r] == 0: stack.append(r)
	while not stack.is_empty():
		var i: int = stack.pop_back()
		if outside[i] == 1 or mask[i] == 1:
			continue
		outside[i] = 1
		var x := i % w
		var y := i / w
		if x > 0: stack.append(i - 1)
		if x < w - 1: stack.append(i + 1)
		if y > 0: stack.append(i - w)
		if y < h - 1: stack.append(i + w)

	var hole_lum := float(cfg["hole_keep_lum_max"])
	var hole_sat := float(cfg["hole_keep_sat_max"])
	var min_hole := int(cfg["min_hole_area_px"])
	var fill_pts: Array = cfg["fill_holes_at_px"]
	var keep_pts: Array = cfg["keep_holes_at_px"]
	var hvisit := PackedByteArray()
	hvisit.resize(w * h)
	var kept := 0
	var filled := 0
	for i in w * h:
		if mask[i] == 0 and outside[i] == 0 and hvisit[i] == 0:
			# 收集一个封闭空区
			var region: Array[int] = []
			var st: Array[int] = [i]
			hvisit[i] = 1
			while not st.is_empty():
				var j: int = st.pop_back()
				region.append(j)
				var xx := j % w
				var yy := j / w
				for n: int in [j - 1, j + 1, j - w, j + w]:
					if n < 0 or n >= w * h: continue
					var nx: int = n % w
					if absi(nx - xx) > 1: continue
					if mask[n] == 0 and outside[n] == 0 and hvisit[n] == 0:
						hvisit[n] = 1
						st.append(n)
			# 区域统计
			var lsum := 0.0
			var ssum := 0.0
			var cx := 0.0
			var cz := 0.0
			var rx0 := w; var rx1 := 0; var ry0 := h; var ry1 := 0
			for j in region:
				var c2 := img.get_pixel(j % w, j / w)
				lsum += c2.get_luminance()
				ssum += _sat(c2)
				var jx := j % w
				var jy := j / w
				cx += jx
				cz += jy
				rx0 = mini(rx0, jx); rx1 = maxi(rx1, jx)
				ry0 = mini(ry0, jy); ry1 = maxi(ry1, jy)
			var n2 := float(region.size())
			var mlum := lsum / n2
			var msat := ssum / n2
			cx /= n2
			cz /= n2
			# 细缝过滤:描边与地面填充间的内阴影线会形成贴边细长伪洞 → 按"面积/最大边长"估厚度
			var thick := n2 / maxf(float(rx1 - rx0 + 1), float(ry1 - ry0 + 1))
			var min_thick := float(cfg.get("hole_min_thickness_px", 8.0))
			var keep := region.size() >= min_hole and mlum < hole_lum and msat < hole_sat and thick >= min_thick
			if _near_pt(keep_pts, cx, cz): keep = true
			if _near_pt(fill_pts, cx, cz): keep = false
			if keep:
				kept += 1
			else:
				filled += 1
				for j in region:
					mask[j] = 1   # 填平为 floor(图标)
			if region.size() >= 200:
				print("  封闭区 中心(%d,%d) 面积=%d 亮度=%.2f 饱和=%.2f → %s" % [int(cx), int(cz), region.size(), mlum, msat, "保留(洞/墙)" if keep else "填平(图标)"])
	print("[trace] 封闭区: 保留 ", kept, " 填平 ", filled)

	# ── 3.5) 消除 2x2 对角夹点(对角连通补一格)→ 轮廓环必为简单多边形 ──
	var pinch := 0
	var changed := true
	while changed:
		changed = false
		for y in h - 1:
			for x in w - 1:
				var i00 := y * w + x
				var i10 := i00 + 1
				var i01 := i00 + w
				var i11 := i01 + 1
				if mask[i00] == 1 and mask[i11] == 1 and mask[i10] == 0 and mask[i01] == 0:
					mask[i10] = 1; pinch += 1; changed = true
				elif mask[i10] == 1 and mask[i01] == 1 and mask[i00] == 0 and mask[i11] == 0:
					mask[i00] = 1; pinch += 1; changed = true
	print("[trace] 对角夹点修补 ", pinch, " 处")

	# ── 4) 轮廓环提取(晶格边;floor 在行进方向左侧) ──
	var loops := _extract_loops(mask, w, h)
	print("[trace] 轮廓环 ", loops.size(), " 条")

	# ── 5) DP 简化 + 世界坐标 ──
	var eps := float(cfg["dp_epsilon_px"])
	# 内容包围盒
	var bx0 := w; var bx1 := 0; var by0 := h; var by1 := 0
	for i in w * h:
		if mask[i] == 1:
			var x2 := i % w
			var y2 := i / w
			bx0 = mini(bx0, x2); bx1 = maxi(bx1, x2)
			by0 = mini(by0, y2); by1 = maxi(by1, y2)
	var wpp := float(cfg["world_width"]) / float(bx1 - bx0 + 1)
	var ox := (bx0 + bx1) * 0.5
	var oz := (by0 + by1) * 0.5
	print("[trace] 内容包围盒 px(%d..%d, %d..%d) → wpp=%.4f 世界 %.1f x %.1f" % [bx0, bx1, by0, by1, wpp, (bx1 - bx0 + 1) * wpp, (by1 - by0 + 1) * wpp])

	var out_loops: Array = []
	var total_pts := 0
	var kept_loops := 0
	for lp in loops:
		var simp: PackedVector2Array = _dedupe(_dp_closed(lp["pts"], eps))
		# 简单性验证(CSGPolygon 不接受自交):失败则减小 eps 重试,最后回退原始晶格环
		var try_eps := eps
		while simp.size() >= 3 and Geometry2D.triangulate_polygon(simp).is_empty() and try_eps > 0.2:
			try_eps *= 0.5
			simp = _dedupe(_dp_closed(lp["pts"], try_eps))
		if simp.size() >= 3 and Geometry2D.triangulate_polygon(simp).is_empty():
			simp = _dedupe(lp["pts"])
			if Geometry2D.triangulate_polygon(simp).is_empty():
				print("  ⚠ 环无法简单化(", (lp["pts"] as PackedVector2Array).size(), " 点),跳过")
				continue
			print("  ⚠ 环回退原始晶格(", simp.size(), " 点)")
		elif try_eps != eps:
			print("  环 eps 降至 ", try_eps, " 通过验证 (", simp.size(), " 点)")
		if simp.size() < 4:
			continue
		# 过小的环丢弃(噪声)
		if absf(_area(simp)) < 25.0:
			continue
		kept_loops += 1
		var world_pts: Array = []
		for p in simp:
			world_pts.append([snappedf((p.x - ox) * wpp, 0.01), snappedf((p.y - oz) * wpp, 0.01)])
		total_pts += simp.size()
		out_loops.append({"hole": lp["hole"], "pts": world_pts})
	print("[trace] 简化后 ", kept_loops, " 环 / 共 ", total_pts, " 顶点 (eps=", eps, "px)")

	# ── 6) 输出 JSON ──
	var ent: Array = cfg["entrance_px"]
	var spn: Array = cfg["spawn_px"]
	var out := {
		"src": String(cfg["image"]), "px_w": w, "px_h": h,
		"wpp": wpp, "origin_px": [ox, oz],
		"entrance_world": [snappedf((float(ent[0]) - ox) * wpp, 0.01), snappedf((float(ent[1]) - oz) * wpp, 0.01)],
		"spawn_world": [snappedf((float(spn[0]) - ox) * wpp, 0.01), snappedf((float(spn[1]) - oz) * wpp, 0.01)],
		"loops": out_loops,
	}
	var f := FileAccess.open(ProjectSettings.globalize_path(String(cfg["trace_json"])), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("[trace] 已写 ", cfg["trace_json"])

	# ── 7) 调试图:掩码 + 轮廓叠加 ──
	var dbg := Image.create(w, h, false, Image.FORMAT_RGB8)
	for y in h:
		for x in w:
			dbg.set_pixel(x, y, Color.WHITE if mask[y * w + x] == 1 else Color.BLACK)
	dbg.save_png(ProjectSettings.globalize_path("res://tools/_capture/plan_mask.png"))
	var ov := img.duplicate()
	ov.convert(Image.FORMAT_RGB8)
	for lp in out_loops:
		var col := Color(1, 0.1, 0.1) if not lp["hole"] else Color(0.1, 1, 0.3)
		var pts: Array = lp["pts"]
		for k in pts.size():
			var a: Array = pts[k]
			var b: Array = pts[(k + 1) % pts.size()]
			_draw_line(ov, Vector2(a[0] / wpp + ox, a[1] / wpp + oz), Vector2(b[0] / wpp + ox, b[1] / wpp + oz), col)
	ov.save_png(ProjectSettings.globalize_path("res://tools/_capture/plan_contours.png"))
	print("[trace] 调试图已存 tools/_capture/plan_mask.png / plan_contours.png")
	quit(0)

# ---------------------------------------------------------------------------
func _sat(c: Color) -> float:
	var mx := maxf(c.r, maxf(c.g, c.b))
	var mn := minf(c.r, minf(c.g, c.b))
	return 0.0 if mx <= 0.001 else (mx - mn) / mx

func _count(m: PackedByteArray) -> int:
	var n := 0
	for v in m:
		if v == 1: n += 1
	return n

func _near_pt(pts: Array, cx: float, cz: float) -> bool:
	for p in pts:
		if Vector2(p[0], p[1]).distance_to(Vector2(cx, cz)) < 25.0:
			return true
	return false

func _flood_label(mask: PackedByteArray, labels: PackedInt32Array, w: int, h: int, start: int, lab: int) -> int:
	var st: Array[int] = [start]
	labels[start] = lab
	var area := 0
	while not st.is_empty():
		var i: int = st.pop_back()
		area += 1
		var x := i % w
		var y := i / w
		if x > 0 and mask[i - 1] == 1 and labels[i - 1] == 0: labels[i - 1] = lab; st.append(i - 1)
		if x < w - 1 and mask[i + 1] == 1 and labels[i + 1] == 0: labels[i + 1] = lab; st.append(i + 1)
		if y > 0 and mask[i - w] == 1 and labels[i - w] == 0: labels[i - w] = lab; st.append(i - w)
		if y < h - 1 and mask[i + w] == 1 and labels[i + w] == 0: labels[i + w] = lab; st.append(i + w)
	return area

# 晶格边提取:每条 floor/非floor 边界边为有向线段(floor 在左);按起点索引链接成闭环。
func _extract_loops(mask: PackedByteArray, w: int, h: int) -> Array:
	var edges := {}   # 起点key → Array[终点key](分叉时多值)
	var W1 := w + 1
	for y in h:
		for x in w:
			if mask[y * w + x] != 1:
				continue
			var up := (y == 0) or (mask[(y - 1) * w + x] == 0)
			var dn := (y == h - 1) or (mask[(y + 1) * w + x] == 0)
			var lf := (x == 0) or (mask[y * w + x - 1] == 0)
			var rt := (x == w - 1) or (mask[y * w + x + 1] == 0)
			if up: _add_edge(edges, (x + 1) + y * W1, x + y * W1)                 # 上边界:向 -x
			if dn: _add_edge(edges, x + (y + 1) * W1, (x + 1) + (y + 1) * W1)     # 下边界:向 +x
			if lf: _add_edge(edges, x + y * W1, x + (y + 1) * W1)                 # 左边界:向 +z
			if rt: _add_edge(edges, (x + 1) + (y + 1) * W1, (x + 1) + y * W1)     # 右边界:向 -z
	var loops: Array = []
	var keys := edges.keys()
	for k0 in keys:
		while edges.has(k0) and not (edges[k0] as Array).is_empty():
			var loop_pts := PackedVector2Array()
			var cur: int = k0
			var prev_dir := Vector2.ZERO
			var guard := 0
			while guard < 4000000:
				guard += 1
				var outs: Array = edges.get(cur, [])
				if outs.is_empty():
					break
				var pick := 0
				if outs.size() > 1 and prev_dir != Vector2.ZERO:
					# 分叉:优先最左转,保持环简单
					var best := -10.0
					for oi in outs.size():
						var d := _dir(cur, outs[oi], W1)
						var s := prev_dir.cross(d) - prev_dir.dot(d) * 0.001
						if s > best:
							best = s
							pick = oi
				var nxt: int = outs.pop_at(pick)
				if outs.is_empty():
					edges.erase(cur)
				loop_pts.append(Vector2(cur % W1, cur / W1))
				prev_dir = _dir(cur, nxt, W1)
				cur = nxt
				if cur == k0:
					break
			if loop_pts.size() >= 4 and cur == k0:
				# 有向边约定 floor 在左 → 外环/洞环由绕向区分(屏幕坐标下外环为顺时针,面积符号判定)
				loops.append({"pts": loop_pts, "hole": _area(loop_pts) > 0.0})
	return loops

func _add_edge(edges: Dictionary, a: int, b: int) -> void:
	if not edges.has(a):
		edges[a] = []
	(edges[a] as Array).append(b)

func _dir(a: int, b: int, W1: int) -> Vector2:
	return (Vector2(b % W1, b / W1) - Vector2(a % W1, a / W1)).normalized()

func _area(pts: PackedVector2Array) -> float:
	var s := 0.0
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		s += a.x * b.y - b.x * a.y
	return s * 0.5

# 闭环 DP:从相距最远两点切开成两条折线分别简化
func _dp_closed(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 8:
		return pts
	var i0 := 0
	var far := 0
	var best := -1.0
	for i in pts.size():
		var d := pts[i].distance_squared_to(pts[0])
		if d > best:
			best = d
			far = i
	var a_half := PackedVector2Array()
	var b_half := PackedVector2Array()
	for i in range(i0, far + 1):
		a_half.append(pts[i])
	for i in range(far, pts.size()):
		b_half.append(pts[i])
	b_half.append(pts[0])
	var ra := _dp_line(a_half, eps)
	var rb := _dp_line(b_half, eps)
	var out := PackedVector2Array()
	for i in ra.size() - 1:
		out.append(ra[i])
	for i in rb.size() - 1:
		out.append(rb[i])
	return out

func _dp_line(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var keep := PackedByteArray()
	keep.resize(pts.size())
	keep[0] = 1
	keep[pts.size() - 1] = 1
	var stack: Array = [[0, pts.size() - 1]]
	while not stack.is_empty():
		var seg: Array = stack.pop_back()
		var s: int = seg[0]
		var e: int = seg[1]
		if e - s < 2:
			continue
		var a := pts[s]
		var b := pts[e]
		var ab := b - a
		var ab_len := ab.length()
		var far := -1
		var fd := eps
		for i in range(s + 1, e):
			var d: float
			if ab_len < 0.0001:
				d = pts[i].distance_to(a)
			else:
				d = absf(ab.cross(pts[i] - a)) / ab_len
			if d > fd:
				fd = d
				far = i
		if far >= 0:
			keep[far] = 1
			stack.append([s, far])
			stack.append([far, e])
	var out := PackedVector2Array()
	for i in pts.size():
		if keep[i] == 1:
			out.append(pts[i])
	return out

func _dedupe(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(p) > 0.0001:
			out.append(p)
	while out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) < 0.0001:
		out.remove_at(out.size() - 1)
	return out

func _draw_line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var n := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		var x := int(p.x)
		var y := int(p.y)
		if x >= 0 and x < img.get_width() and y >= 0 and y < img.get_height():
			img.set_pixel(x, y, col)

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(ProjectSettings.globalize_path(path), FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	return d if d is Dictionary else {}
