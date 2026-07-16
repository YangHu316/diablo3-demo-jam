extends SceneTree

# 素材编目:实测候选 PolygonDungeon 资产的世界包围盒(post-import 已修 ×100 比例)
# → 验证V1-Fable5自主开发/tools/asset_catalog.json
# Run: Godot --headless --path . --script res://验证V1-Fable5自主开发/tools/catalog_assets.gd

const OUT := "res://验证V1-Fable5自主开发/tools/asset_catalog.json"
const BASE := "res://assets/PolygonDungeon/Models/"
const LIST := [
	"Environment/Floors/SM_Env_Tiles_01.fbx", "Environment/Floors/SM_Env_Tiles_02.fbx",
	"Environment/Floors/SM_Env_Tiles_03.fbx", "Environment/Floors/SM_Env_Tiles_04.fbx",
	"Environment/Floors/SM_Env_Tiles_05.fbx", "Environment/Floors/SM_Env_Tiles_06.fbx",
	"Environment/Floors/SM_Env_Tile_Simple_01.fbx", "Environment/Floors/SM_Env_Grate_01.fbx",
	"Environment/Walls/SM_Env_Wall_01.fbx", "Environment/Walls/SM_Env_Wall_02.fbx",
	"Environment/Walls/SM_Env_Wall_01_Alt.fbx",
	"Environment/Pillars/SM_Env_Pillar_Round_01.fbx", "Environment/Pillars/SM_Env_Pillar_Broken_01.fbx",
	"Environment/Pillars/SM_Env_Pillar_Broken_Pile_01.fbx", "Environment/Pillars/SM_Env_Obelisk_01.fbx",
	"Environment/Decor/SM_Env_Gem_Large_01.fbx", "Environment/Decor/SM_Env_Gem_Large_02.fbx",
	"Environment/Decor/SM_Env_Gem_Spike_01.fbx", "Environment/Decor/SM_Env_Gem_Spike_02.fbx",
	"Environment/Doors/SM_Env_Entrance_Crypt_01.fbx", "Environment/Doors/SM_Env_Entrance_Crypt_02.fbx",
	"Environment/Doors/SM_Env_Door_Large_Stone_01.fbx", "Environment/Doors/SM_Env_Door_Frame_01.fbx",
	"Environment/Bones/SM_Env_BonePile_01.fbx", "Environment/Bones/SM_Env_BonePile_02.fbx",
	"Environment/Bones/SM_Env_Bone_Rigcage_01.fbx", "Environment/Bones/SM_Env_Bone_Skull_01.fbx",
	"Environment/Cave_Rocks/SM_Env_Stalagmite_01.fbx", "Environment/Cave_Rocks/SM_Env_Stalagmite_03.fbx",
	"Environment/Cave_Rocks/SM_Env_CrackedRock_01.fbx", "Environment/Cave_Rocks/SM_Env_Rubble_Pebbles_01.fbx",
	"Props/Lighting/SM_Prop_Torch_Ornate_02.fbx", "Props/Lighting/SM_Prop_Brazier_01.fbx",
	"Props/Lighting/SM_Prop_Candles_01.fbx", "Props/Lighting/SM_Prop_Candle_Stand_01.fbx",
	"Props/Lighting/SM_Prop_Bonfire_01.fbx",
	"Props/Containers/SM_Prop_Barrel_01.fbx", "Props/Containers/SM_Prop_Vase_03.fbx",
	"Props/Containers/SM_Prop_Chest_01.fbx", "Props/Containers/SM_Prop_Crate_Wood_01.fbx",
	# ── v6 装饰扩充(全部实测原点/min_y,杜绝半埋)──
	"Environment/Walls/SM_Env_Brick_Rubble_01.fbx", "Environment/Walls/SM_Env_Brick_Rubble_02.fbx",
	"Environment/Walls/SM_Env_Brick_Rubble_03.fbx", "Environment/Walls/SM_Env_Brick_Rubble_04.fbx",
	"Environment/Walls/SM_Env_Brick_Rubble_05.fbx", "Environment/Walls/SM_Env_Brick_Rubble_06.fbx",
	"Environment/Bones/SM_Env_BonePile_Small_01.fbx", "Environment/Bones/SM_Env_BonePile_Small_02.fbx",
	"Environment/Bones/SM_Env_BonePile_03.fbx", "Environment/Bones/SM_Env_Bone_Skull_02.fbx",
	"Environment/Bones/SM_Env_Bone_Skull_Jaw_01.fbx", "Environment/Bones/SM_Env_Bone_Rib_01.fbx",
	"Environment/Bones/SM_Env_Bone_Ribs_01.fbx", "Environment/Bones/SM_Env_Bone_Spine_01.fbx",
	"Environment/Bones/SM_Env_Bone_Cracked_01.fbx",
	"Environment/Pillars/SM_Env_Statue_01.fbx", "Environment/Pillars/SM_Env_Statue_02.fbx",
	"Environment/Pillars/SM_Env_Statue_03.fbx", "Environment/Pillars/SM_Env_Statue_04.fbx",
	"Environment/Pillars/SM_Env_Alter_01.fbx", "Environment/Pillars/SM_Env_Pillar_Broken_02.fbx",
	"Environment/Pillars/SM_Env_Pillar_Broken_Pile_02.fbx",
	"Environment/Decor/SM_Env_Rune_Pillar_01.fbx", "Environment/Decor/SM_Env_Rune_Rounded_01.fbx",
	"Environment/Decor/SM_Env_Rune_Rounded_02.fbx", "Environment/Decor/SM_Env_Rune_Square_01.fbx",
	"Environment/Walls/SM_Env_Stone_Fountain_01.fbx", "Environment/Walls/SM_Env_Stone_Lantern_01.fbx",
	"Environment/Walls/SM_Env_Stone_Vessel_01.fbx",
	"Props/Furniture/SM_Prop_Coffin_01.fbx", "Props/Furniture/SM_Prop_StoneTable_Broken_01.fbx",
	"Props/Furniture/SM_Prop_Bench_01.fbx", "Props/Furniture/SM_Prop_Bookcase_01.fbx",
	"Props/Furniture/SM_Prop_Bookcase_02.fbx", "Props/Furniture/SM_Prop_WeaponRack_01.fbx",
	"Props/Furniture/SM_Prop_Rug_01.fbx", "Props/Furniture/SM_Prop_Rug_02.fbx",
	"Props/Furniture/SM_Prop_Rug_03.fbx", "Props/Furniture/SM_Prop_Stool_01.fbx",
	"Props/Furniture/SM_Prop_Table_Round_Broken_01.fbx",
	"Props/Furniture/SM_Prop_Wall_Banner_01.fbx", "Props/Furniture/SM_Prop_Wall_Banner_02.fbx",
	"Props/Furniture/SM_Prop_Wall_Banner_03.fbx", "Props/Furniture/SM_Prop_Wall_Banner_05.fbx",
	"Props/Furniture/SM_Prop_Bricks_01.fbx", "Props/Furniture/SM_Prop_Bricks_02.fbx",
	"Props/Creatures/SM_Prop_Skeleton_01.fbx", "Props/Creatures/SM_Prop_Skeleton_Slave_Lying_01.fbx",
	"Props/Creatures/SM_Prop_Skeleton_Slave_Shackles_01.fbx", "Props/Creatures/SM_Prop_Skeleton_Knight_Throne_01.fbx",
	"Props/Containers/SM_Prop_Barrel_02.fbx", "Props/Containers/SM_Prop_Barrel_03.fbx",
	"Props/Containers/SM_Prop_Barrel_Broken_01.fbx", "Props/Containers/SM_Prop_Barrel_Large_01.fbx",
	"Props/Containers/SM_Prop_Crate_Wood_02.fbx", "Props/Containers/SM_Prop_Crate_Wood_03.fbx",
	"Props/Containers/SM_Prop_Crate_Ornate_01.fbx", "Props/Containers/SM_Prop_Vase_01.fbx",
	"Props/Containers/SM_Prop_Vase_02.fbx", "Props/Containers/SM_Prop_Vase_05.fbx",
	"Props/Containers/SM_Prop_Vase_Group_01.fbx", "Props/Containers/SM_Prop_Vase_Broken_01.fbx",
	"Props/Containers/SM_Prop_Vase_Shard_01.fbx", "Props/Containers/SM_Prop_Chest_02.fbx",
	"Props/Lighting/SM_Prop_Cauldron_01.fbx", "Props/Lighting/SM_Prop_Candles_02.fbx",
	"Props/Lighting/SM_Prop_Candles_03.fbx", "Props/Lighting/SM_Prop_Candle_02.fbx",
	"Props/Lighting/SM_Prop_TorchStick_01.fbx",
	"Props/Torture/SM_Prop_Toture_Cage_01.fbx", "Props/Torture/SM_Prop_Toture_Stocks_01.fbx",
	"Props/Torture/SM_Prop_Toture_IronMaiden_01.fbx",
]

func _init() -> void:
	var out := {}
	for rel in LIST:
		var path: String = BASE + rel
		var ps: PackedScene = load(path)
		if ps == null:
			print("MISS ", rel)
			continue
		var inst := ps.instantiate()
		var merged: Variant = null
		var stack: Array[Node] = [inst]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
				var mi := n as MeshInstance3D
				var xf := Transform3D.IDENTITY
				var p: Node = mi
				while p != null:
					if p is Node3D:
						xf = (p as Node3D).transform * xf
					p = p.get_parent()
				var box: AABB = xf * mi.mesh.get_aabb()
				merged = box if merged == null else (merged as AABB).merge(box)
			for c in n.get_children():
				stack.append(c)
		inst.free()
		if merged == null:
			print("NOMESH ", rel)
			continue
		var b: AABB = merged
		out[rel] = {
			"size": [snappedf(b.size.x, 0.01), snappedf(b.size.y, 0.01), snappedf(b.size.z, 0.01)],
			"min_y": snappedf(b.position.y, 0.01),
			"center_xz": [snappedf(b.position.x + b.size.x * 0.5, 0.01), snappedf(b.position.z + b.size.z * 0.5, 0.01)],
		}
		print("%-56s size=%.2f x %.2f x %.2f  min_y=%.2f" % [rel, b.size.x, b.size.y, b.size.z, b.position.y])
	var f := FileAccess.open(ProjectSettings.globalize_path(OUT), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("[catalog] 已写 ", OUT, " (", out.size(), " 条)")
	quit(0)
