extends SceneTree
# UI 图集自动切图工具(网格模式)
# 用法: 在下面 CONFIG 里加 { "sheet": 图集res路径, "cell": Vector2i(格宽,格高) },然后:
#   "D:\Godot\Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script res://tools/slice_sheets.gd
# 它会按格子切,自动跳过全透明的空格,为每个非空格生成一个 AtlasTexture (.tres),
# 输出到 res://assets/ui/sliced/<图集名>/。.tres 可直接拖到 TextureRect / Button / Sprite2D 上当单个图标用。

const OUT_ROOT := "res://assets/ui/sliced/"
const ALPHA_THRESHOLD := 0.03   # 透明度低于此的格子视为空,跳过

var CONFIG := [
	# —— 物品图标(覆盖弓手掉落部位)——
	{"sheet": "res://assets/ui/inventory/2DInventoryBows.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryQuivers.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryChestArmor.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryHelms.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryGloves.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryBoots.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryBelts.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryShoulders.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryPants.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryBracers.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryRings.png", "cell": Vector2i(128, 128)},
	{"sheet": "res://assets/ui/inventory/2DInventoryAmulet.png", "cell": Vector2i(128, 64)},
	{"sheet": "res://assets/ui/inventory/2DInventoryGemsIcons.png", "cell": Vector2i(128, 128)},
	# —— 技能图标(弓手 = 恶魔猎手)——
	{"sheet": "res://assets/ui/skills/2DUI_Skills_DemonHunter.png", "cell": Vector2i(128, 128)},
	# —— 状态/Buff 图标 ——
	{"sheet": "res://assets/ui/hud/2DUIBuffIcons.png", "cell": Vector2i(128, 128)},
]

func _initialize():
	var total := 0
	for item in CONFIG:
		total += _slice(item["sheet"], item["cell"])
	print("=== 完成,共生成 ", total, " 个图标 AtlasTexture ===")
	quit()

func _slice(sheet_path: String, cell: Vector2i) -> int:
	if not ResourceLoader.exists(sheet_path):
		print("跳过(不存在): ", sheet_path)
		return 0
	var tex: Texture2D = load(sheet_path)
	var img: Image = tex.get_image()
	if img.is_compressed():
		img.decompress()
	var sw := img.get_width()
	var sh := img.get_height()
	var cols := sw / cell.x
	var rows := sh / cell.y
	var sheet_name := sheet_path.get_file().get_basename()
	var outdir := OUT_ROOT + sheet_name + "/"
	DirAccess.make_dir_recursive_absolute(outdir)
	var n := 0
	for r in rows:
		for c in cols:
			var rect := Rect2i(c * cell.x, r * cell.y, cell.x, cell.y)
			if _is_empty(img, rect):
				continue
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(rect)
			var idx := r * cols + c
			var err := ResourceSaver.save(at, outdir + "%s_%02d.tres" % [sheet_name, idx])
			if err == OK:
				n += 1
	print(sheet_name, " (", cols, "x", rows, " 格): ", n, " 个非空图标")
	return n

func _is_empty(img: Image, rect: Rect2i) -> bool:
	# 每隔 4 像素抽样检查 alpha,任一不透明则非空
	var y := rect.position.y
	while y < rect.position.y + rect.size.y:
		var x := rect.position.x
		while x < rect.position.x + rect.size.x:
			if img.get_pixel(x, y).a > ALPHA_THRESHOLD:
				return false
			x += 4
		y += 4
	return true
