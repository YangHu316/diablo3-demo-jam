extends Node

# 一次性验收:① 血瓶(键1)回血+冷却 ② reset_rift 后 boss 可再次降临。
# Run: Godot --path . res://tools/test_potion_restart.tscn --log-file <log>

const PLAY := "res://验证V1-Fable5自主开发/scenes/level_03_dh_play.tscn"

func _ready() -> void:
	add_child((load(PLAY) as PackedScene).instantiate())
	await get_tree().create_timer(2.0).timeout
	var player: Node = get_tree().get_first_node_in_group("player")
	var rm: Node = get_node_or_null("/root/RiftManager")

	# ① 血瓶
	player.take_damage(900, null)
	var hp_before: int = player.current_health
	Input.action_press("potion")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("potion")
	await get_tree().create_timer(0.4).timeout
	var hp_after: int = player.current_health
	print("[test] 血瓶回血: %d -> %d  %s" % [hp_before, hp_after,
			"PASS" if hp_after > hp_before else "FAIL"])
	await RenderingServer.frame_post_draw
	_shot("tools/_capture/potion_heal.png")
	# 冷却期再按:血量不应变化
	var hp_cd: int = player.current_health
	Input.action_press("potion")
	await get_tree().process_frame
	await get_tree().process_frame
	Input.action_release("potion")
	await get_tree().create_timer(0.3).timeout
	print("[test] 血瓶冷却拒绝: %s" % ("PASS" if player.current_health == hp_cd else "FAIL"))

	# ② boss 降临 → reset → 再降临
	rm._add_progress(999.0)
	await get_tree().create_timer(1.6).timeout
	var n1: int = get_tree().get_nodes_in_group("boss").size()
	print("[test] 首次降临 boss 数=%d %s" % [n1, "PASS" if n1 >= 1 else "FAIL"])
	rm.reset_rift()
	print("[test] reset 后 progress=%.1f guardian_triggered=%s %s" % [rm.progress, str(rm.guardian_triggered),
			"PASS" if rm.progress == 0.0 and not rm.guardian_triggered else "FAIL"])
	rm._add_progress(999.0)
	await get_tree().create_timer(1.6).timeout
	var n2: int = get_tree().get_nodes_in_group("boss").size()
	print("[test] 重置后再降临 boss 数=%d %s" % [n2, "PASS" if n2 >= 2 else "FAIL"])
	get_tree().quit(0)

func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	img.save_png(ProjectSettings.globalize_path(path))
