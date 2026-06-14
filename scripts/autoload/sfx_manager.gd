extends Node

# sfx_manager.gd — 全局 SFX 路由器(Autoload "Sfx")。
# 用法:Sfx.play("hit_flesh", world_pos)  / Sfx.play("arrow_shoot")
# - 3D 调用(带 pos)= AudioStreamPlayer3D 临时节点,自销毁
# - 2D 调用(无 pos)= AudioStreamPlayer 一次性
# 池化避免每次 new node 卡顿(短音效 < 1s 不影响)
#
# 维护:把新增 SFX 加到 SOUND_TABLE,调用方用 key 不直接读路径

const SOUND_TABLE: Dictionary = {
	# 战斗
	"arrow_shoot":      "res://assets/SFX/Player_Movement_SFX/56_Attack_03.wav",
	"arrow_hit":        "res://assets/SFX/Battle_SFX/15_Impact_flesh_02.wav",
	"arrow_hit_alt":    "res://assets/SFX/Battle_SFX/77_flesh_02.wav",
	"slash":            "res://assets/SFX/Battle_SFX/22_Slash_04.wav",
	"enemy_death":      "res://assets/SFX/Battle_SFX/69_Enemy_death_01.wav",
	"player_hurt":      "res://assets/SFX/Player_Movement_SFX/61_Hit_03.wav",
	# 元素 / 技能
	"frost_explode":    "res://assets/SFX/Atk_Magic_SFX/13_Ice_explosion_01.wav",
	"fire_explode":     "res://assets/SFX/Atk_Magic_SFX/04_Fire_explosion_04_medium.wav",
	"channel_charge":   "res://assets/SFX/Atk_Magic_SFX/45_Charge_05.wav",
	# 自爆
	"explode":          "res://assets/SFX/Atk_Magic_SFX/04_Fire_explosion_04_medium.wav",
	# 玩家
	"dodge":            "res://assets/SFX/Battle_SFX/35_Miss_Evade_02.wav",
}

# StringName -> AudioStream 缓存(免运行时反复 load)
var _cache: Dictionary = {}

# ── 公共 API ─────────────────────────────────────────────
# 3D 位置音效:在 world_pos spawn 一个 AudioStreamPlayer3D,播完自销毁
func play(key: String, world_pos = null, volume_db: float = 0.0, pitch_jitter: float = 0.05) -> void:
	var stream: AudioStream = _get_stream(key)
	if stream == null:
		return
	if world_pos == null:
		_play_2d(stream, volume_db, pitch_jitter)
		return
	if not (world_pos is Vector3):
		_play_2d(stream, volume_db, pitch_jitter)
		return
	_play_3d(stream, world_pos, volume_db, pitch_jitter)

func _get_stream(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key] as AudioStream
	if not SOUND_TABLE.has(key):
		push_warning("Sfx: unknown key '%s'" % key)
		return null
	var path: String = String(SOUND_TABLE[key])
	if not ResourceLoader.exists(path):
		push_warning("Sfx: file missing %s" % path)
		return null
	var s: AudioStream = load(path)
	if s != null:
		_cache[key] = s
	return s

func _play_3d(stream: AudioStream, pos: Vector3, volume_db: float, pitch_jitter: float) -> void:
	var sp: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	sp.stream = stream
	sp.volume_db = volume_db
	sp.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	sp.unit_size = 8.0  # 听到的衰减半径
	sp.max_distance = 40.0
	sp.bus = "Master"
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		queue_free_player_later(sp)
		return
	scene_root.add_child(sp)
	sp.global_position = pos
	sp.play()
	sp.finished.connect(sp.queue_free)

func _play_2d(stream: AudioStream, volume_db: float, pitch_jitter: float) -> void:
	var sp: AudioStreamPlayer = AudioStreamPlayer.new()
	sp.stream = stream
	sp.volume_db = volume_db
	sp.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	sp.bus = "Master"
	add_child(sp)
	sp.play()
	sp.finished.connect(sp.queue_free)

func queue_free_player_later(sp: AudioStreamPlayer3D) -> void:
	add_child(sp)
	sp.play()
	sp.finished.connect(sp.queue_free)
