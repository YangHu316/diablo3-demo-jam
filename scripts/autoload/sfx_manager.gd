extends Node

# sfx_manager.gd — 全局 SFX 路由器(Autoload "Sfx")。
# 用法:Sfx.play("hit_flesh", world_pos)  / Sfx.play("arrow_shoot")
# - 3D 调用(带 pos)= AudioStreamPlayer3D 临时节点,自销毁
# - 2D 调用(无 pos)= AudioStreamPlayer 一次性
# 池化避免每次 new node 卡顿(短音效 < 1s 不影响)
#
# 维护:把新增 SFX 加到 SOUND_TABLE,调用方用 key 不直接读路径

const SOUND_TABLE: Dictionary = {
	# ── 战斗 / 命中 (Battle_SFX) ──
	"slash":            "res://assets/SFX/Battle_SFX/22_Slash_04.wav",
	"claw":             "res://assets/SFX/Battle_SFX/03_Claw_03.wav",
	"bite":             "res://assets/SFX/Battle_SFX/08_Bite_04.wav",
	"impact_flesh":     "res://assets/SFX/Battle_SFX/15_Impact_flesh_02.wav",
	"flesh_alt":        "res://assets/SFX/Battle_SFX/77_flesh_02.wav",
	"block":            "res://assets/SFX/Battle_SFX/39_Block_03.wav",
	"evade":            "res://assets/SFX/Battle_SFX/35_Miss_Evade_02.wav",
	"flee":             "res://assets/SFX/Battle_SFX/51_Flee_02.wav",
	"encounter":        "res://assets/SFX/Battle_SFX/55_Encounter_02.wav",
	"enemy_death":      "res://assets/SFX/Battle_SFX/69_Enemy_death_01.wav",
	"arrow_hit":        "res://assets/SFX/Battle_SFX/15_Impact_flesh_02.wav",  # 兼容旧 key
	"arrow_hit_alt":    "res://assets/SFX/Battle_SFX/77_flesh_02.wav",         # 兼容旧 key
	"dodge":            "res://assets/SFX/Battle_SFX/35_Miss_Evade_02.wav",    # 兼容旧 key
	# ── 元素 / 魔法 (Atk_Magic_SFX) ──
	"fire_explode":     "res://assets/SFX/Atk_Magic_SFX/04_Fire_explosion_04_medium.wav",
	"frost_explode":    "res://assets/SFX/Atk_Magic_SFX/13_Ice_explosion_01.wav",
	"thunder":          "res://assets/SFX/Atk_Magic_SFX/18_Thunder_02.wav",
	"water":            "res://assets/SFX/Atk_Magic_SFX/22_Water_02.wav",
	"wind":             "res://assets/SFX/Atk_Magic_SFX/25_Wind_01.wav",
	"earth":            "res://assets/SFX/Atk_Magic_SFX/30_Earth_02.wav",
	"poison":           "res://assets/SFX/Atk_Magic_SFX/46_Poison_01.wav",
	"channel_charge":   "res://assets/SFX/Atk_Magic_SFX/45_Charge_05.wav",
	"explode":          "res://assets/SFX/Atk_Magic_SFX/04_Fire_explosion_04_medium.wav",
	# ── 增益 / 治疗 (Buffs_Heals_SFX) ──
	"heal":             "res://assets/SFX/Buffs_Heals_SFX/02_Heal_02.wav",
	"buff_atk":         "res://assets/SFX/Buffs_Heals_SFX/16_Atk_buff_04.wav",
	"buff_def":         "res://assets/SFX/Buffs_Heals_SFX/17_Def_buff_01.wav",
	"debuff":           "res://assets/SFX/Buffs_Heals_SFX/21_Debuff_01.wav",
	"revive":           "res://assets/SFX/Buffs_Heals_SFX/30_Revive_03.wav",
	"absorb":           "res://assets/SFX/Buffs_Heals_SFX/39_Absorb_04.wav",
	"sleep":            "res://assets/SFX/Buffs_Heals_SFX/44_Sleep_01.wav",
	"speed_up":         "res://assets/SFX/Buffs_Heals_SFX/48_Speed_up_02.wav",
	# ── 玩家移动 / 动作 (Player_Movement_SFX) ──
	"step_grass":       "res://assets/SFX/Player_Movement_SFX/03_Step_grass_03.wav",
	"step_rock":        "res://assets/SFX/Player_Movement_SFX/08_Step_rock_02.wav",
	"step_wood":        "res://assets/SFX/Player_Movement_SFX/12_Step_wood_03.wav",
	"step_water":       "res://assets/SFX/Player_Movement_SFX/14_Step_water_02.wav",
	"swim":             "res://assets/SFX/Player_Movement_SFX/26_Swim_Submerged_02.wav",
	"jump":             "res://assets/SFX/Player_Movement_SFX/30_Jump_03.wav",
	"climb":            "res://assets/SFX/Player_Movement_SFX/42_Cling_climb_03.wav",
	"landing":          "res://assets/SFX/Player_Movement_SFX/45_Landing_01.wav",
	"dive":             "res://assets/SFX/Player_Movement_SFX/52_Dive_02.wav",
	"attack_swing":     "res://assets/SFX/Player_Movement_SFX/56_Attack_03.wav",
	"arrow_shoot":      "res://assets/SFX/Player_Movement_SFX/56_Attack_03.wav",
	"player_hurt":      "res://assets/SFX/Player_Movement_SFX/61_Hit_03.wav",
	"player_death":     "res://assets/SFX/Buffs_Heals_SFX/21_Debuff_01.wav",
	"teleport":         "res://assets/SFX/Player_Movement_SFX/88_Teleport_02.wav",
	# ── UI (UI_Menu_SFX) ──
	"ui_hover":         "res://assets/SFX/UI_Menu_SFX/001_Hover_01.wav",
	"ui_confirm":       "res://assets/SFX/UI_Menu_SFX/013_Confirm_03.wav",
	"ui_decline":       "res://assets/SFX/UI_Menu_SFX/029_Decline_09.wav",
	"ui_denied":        "res://assets/SFX/UI_Menu_SFX/033_Denied_03.wav",
	"ui_use_item":      "res://assets/SFX/UI_Menu_SFX/051_use_item_01.wav",
	"ui_equip":         "res://assets/SFX/UI_Menu_SFX/070_Equip_10.wav",
	"ui_unequip":       "res://assets/SFX/UI_Menu_SFX/071_Unequip_01.wav",
	"ui_buy_sell":      "res://assets/SFX/UI_Menu_SFX/079_Buy_sell_01.wav",
	"ui_pause":         "res://assets/SFX/UI_Menu_SFX/092_Pause_04.wav",
	"ui_unpause":       "res://assets/SFX/UI_Menu_SFX/098_Unpause_04.wav",
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
