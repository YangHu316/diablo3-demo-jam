extends Node

# 游玩场景截图工具:非 headless 运行,加载可玩场景 → 等待就绪截一张 →
# (可选)瞬移玩家到指定点等相机跟随/迷雾更新后再截一张 → 退出。
# 用于小地图/迷雾/遮挡透视等"必须实机渲染"效果的图像自检。
# Run: Godot --path . res://tools/capture_play.tscn -- --scene <res> --out <png> [--px X --pz Z --out2 <png>]

const DEFAULT_SCENE := "res://验证V1-Fable5自主开发/scenes/level_03_dh_play.tscn"

func _ready() -> void:
	var scene_path := DEFAULT_SCENE
	var out1 := "res://tools/_capture/play_shot1.png"
	var out2 := ""
	var px := INF
	var pz := INF
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--scene" and i + 1 < args.size():
			scene_path = args[i + 1]
		elif args[i] == "--out" and i + 1 < args.size():
			out1 = args[i + 1]
		elif args[i] == "--out2" and i + 1 < args.size():
			out2 = args[i + 1]
		elif args[i] == "--px" and i + 1 < args.size():
			px = float(args[i + 1])
		elif args[i] == "--pz" and i + 1 < args.size():
			pz = float(args[i + 1])

	var boss_mode := args.has("--boss")

	var ps: PackedScene = load(scene_path)
	if ps == null:
		printerr("[capture_play] 场景加载失败: ", scene_path)
		get_tree().quit(1)
		return
	add_child(ps.instantiate())

	await get_tree().create_timer(2.5).timeout   # 等玩家/HUD/小地图/迷雾首采样就绪
	await RenderingServer.frame_post_draw
	_save_shot(out1)

	if boss_mode:
		# 强制进度满 → 守门人原地降临流程;拍降临与战斗两个时刻
		var rm: Node = get_node_or_null("/root/RiftManager")
		if rm != null:
			rm._add_progress(999.0)
		await get_tree().create_timer(1.1).timeout   # 法阵/光柱可见窗口
		await RenderingServer.frame_post_draw
		_save_shot(out1.get_basename() + "_portal.png")
		await get_tree().create_timer(1.4).timeout   # 屠夫落地完成
		await RenderingServer.frame_post_draw
		_save_shot(out1.get_basename() + "_boss.png")
		await get_tree().create_timer(6.5).timeout   # 战斗中(技能/特效)
		await RenderingServer.frame_post_draw
		_save_shot(out1.get_basename() + "_fight.png")
	elif out2 != "" and px != INF and pz != INF:
		var players := get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			(players[0] as Node3D).global_position = Vector3(px, 0.2, pz)
		await get_tree().create_timer(1.8).timeout   # 等相机跟随到位 + 迷雾记录新圆
		await RenderingServer.frame_post_draw
		_save_shot(out2)

	get_tree().quit(0)

func _save_shot(out_path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path.get_base_dir()))
	var err := img.save_png(ProjectSettings.globalize_path(out_path))
	print("[capture_play] ", "已保存 " + out_path if err == OK else "保存失败 err=%d" % err,
			" 分辨率=", img.get_size())
