extends SceneTree

func _initialize():
	var p = "res://assets/PolygonDungeon/Models/Characters/Characters.fbx"
	if not ResourceLoader.exists(p):
		p = "res://assets/PolygonDungeon/Models/Characters.fbx"
	var ps = load(p)
	if ps == null:
		print("NOT FOUND: ", p)
		quit()
		return
	print("PATH=", p)
	var root = ps.instantiate()
	print("ROOT=", root.name, " children=", root.get_child_count())
	var chars = 0
	var items = 0
	for c in root.get_children():
		var nm = str(c.name)
		var line = "  " + nm + " [" + c.get_class() + "]"
		if c is AnimationPlayer:
			line += " anims=" + str(c.get_animation_list().size())
		elif nm.begins_with("Character"):
			chars += 1
		elif nm.begins_with("SM_"):
			items += 1
		print(line)
	print("CHARS=", chars, " ITEMS=", items)
	quit()
