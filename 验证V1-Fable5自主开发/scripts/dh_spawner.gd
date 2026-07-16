@tool
extends Node3D

# 验证V1 · 敌人生成器(重新设计版)
# 与旧 spawn_trigger 蓝图的区别:
#   1. 生成点逐个经 WalkableArea(描迹轮廓)验证 —— 可走 + 距墙面/洞缘 ≥ MIN_CLEAR,
#      不合法自动向圆心收缩重采样 → 生成范围**不可能越出地图墙面边界**;
#   2. 敌人类型经内置注册表选择(场景+数值+精英染色+monster_id 元数据一体化);
#   3. 预生成(IDLE 待机,玩家进 aggro_range 才追击,D3 口径),无触发器;
#   4. 编辑器内显示半透明圆盘预览(按类型着色),便于手摆调整。
# 确定性:随机种子取自自身位置哈希 → 同一摆位每次生成结果一致。

const WalkableArea := preload("res://验证V1-Fable5自主开发/scripts/walkable_area.gd")
const ELITE_TINT := "res://scripts/levels/elite_tint.gd"
const MIN_CLEAR := 0.8   # 生成点距边界最小距离(米)

const REGISTRY := {
	"rotwalker": {
		"scene": "res://scenes/enemies/enemy_zombie.tscn",
		"data": "res://验证V1-Fable5自主开发/scripts/enemy_data/dh_rotwalker.tres",
		"monster_id": "trash", "tint": null, "preview": Color(0.45, 0.5, 0.33, 0.5),
	},
	"crypthound": {
		"scene": "res://scenes/enemies/enemy_ghost_01.tscn",
		"data": "res://验证V1-Fable5自主开发/scripts/enemy_data/dh_crypthound.tres",
		"monster_id": "trash", "tint": null, "preview": Color(0.5, 0.75, 0.95, 0.5),
	},
	"marrow_archer": {
		"scene": "res://scenes/enemies/enemy_archer.tscn",
		"data": "res://验证V1-Fable5自主开发/scripts/enemy_data/dh_marrow_archer.tres",
		"monster_id": "trash", "tint": null, "preview": Color(0.85, 0.8, 0.6, 0.5),
	},
	"blightbloat": {
		"scene": "res://scenes/enemies/enemy_bloated.tscn",
		"data": "res://验证V1-Fable5自主开发/scripts/enemy_data/dh_blightbloat.tres",
		"monster_id": "trash", "tint": null, "preview": Color(0.65, 0.75, 0.3, 0.5),
	},
	"crypt_warden": {
		"scene": "res://scenes/enemies/enemy_skeleton_knight.tscn",
		"data": "res://验证V1-Fable5自主开发/scripts/enemy_data/dh_crypt_warden.tres",
		"monster_id": "elite_blue", "tint": Color(0.25, 0.45, 1.0), "preview": Color(0.25, 0.45, 1.0, 0.6),
	},
	"crystal_colossus": {
		"scene": "res://scenes/enemies/enemy_rock_golem.tscn",
		"data": "res://验证V1-Fable5自主开发/scripts/enemy_data/dh_crystal_colossus.tres",
		"monster_id": "champion_yellow", "tint": Color(1.0, 0.85, 0.3), "preview": Color(1.0, 0.85, 0.3, 0.6),
	},
}

@export_enum("rotwalker", "crypthound", "marrow_archer", "blightbloat", "crypt_warden", "crystal_colossus")
var enemy_type: String = "rotwalker":
	set(v):
		enemy_type = v
		_refresh_preview()
@export_range(1, 20) var count: int = 5
@export_range(0.0, 8.0, 0.5) var radius: float = 4.0:
	set(v):
		radius = v
		_refresh_preview()

var _preview: MeshInstance3D = null

func _ready() -> void:
	if Engine.is_editor_hint():
		_refresh_preview()
		return
	call_deferred("_spawn_all")

func _spawn_all() -> void:
	var cfg: Dictionary = REGISTRY.get(enemy_type, {})
	if cfg.is_empty():
		push_error("dh_spawner: 未知敌人类型 " + enemy_type)
		return
	var scene: PackedScene = load(cfg["scene"])
	var data: Resource = load(cfg["data"])
	if scene == null or data == null:
		push_error("dh_spawner: 资源加载失败 " + enemy_type)
		return
	var center := Vector2(global_position.x, global_position.z)
	if not WalkableArea.is_walkable(center):
		push_warning("dh_spawner[%s] 生成器自身位于不可走区 (%.1f, %.1f),已跳过" % [name, center.x, center.y])
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(int(center.x * 10.0), int(center.y * 10.0)))
	for i in count:
		var p := WalkableArea.sample_in_disc(rng, center, radius, MIN_CLEAR)
		var e := scene.instantiate()
		if "data" in e:
			e.set("data", data)
		e.set_meta("monster_id", StringName(String(cfg["monster_id"])))
		e.set_meta("monster_level", 1)
		add_child(e)
		if e is Node3D:
			(e as Node3D).global_position = Vector3(p.x, 0.0, p.y)
		if cfg["tint"] != null:
			var t := Node3D.new()
			t.name = "EliteTint"
			t.set_script(load(ELITE_TINT))
			t.set("tint_color", cfg["tint"])
			t.set("monster_id", StringName(String(cfg["monster_id"])))
			e.add_child(t)
	print("[dh_spawner] %s: %s x%d @(%.1f,%.1f) 生成完毕" % [name, enemy_type, count, center.x, center.y])

# ── 编辑器预览圆盘 ──
func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if _preview == null or not is_instance_valid(_preview):
		_preview = MeshInstance3D.new()
		add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	var cm := CylinderMesh.new()
	cm.top_radius = maxf(radius, 0.5)
	cm.bottom_radius = maxf(radius, 0.5)
	cm.height = 0.15
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var cfg: Dictionary = REGISTRY.get(enemy_type, {})
	m.albedo_color = cfg.get("preview", Color(1, 0, 1, 0.5))
	cm.material = m
	_preview.mesh = cm
	_preview.position = Vector3(0, 0.1, 0)
