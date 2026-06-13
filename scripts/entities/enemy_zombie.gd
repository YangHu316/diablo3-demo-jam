extends "res://scripts/entities/enemy_base.gd"

# EnemyZombie — 缓行走尸。
# 全部 AI 行为继承自 enemy_base.gd,本脚本只负责:
#   - 在 _ready 里加载默认 EnemyData (如果 inspector 没填)
#   - 预留僵尸专属的扩展点(例如肿胀走尸子类可以 override _die 实现死亡爆炸)

const DEFAULT_DATA_PATH: String = "res://scripts/entities/data/walking_corpse.tres"

func _ready() -> void:
	# 没设置 data 就用默认走尸数值
	if data == null and ResourceLoader.exists(DEFAULT_DATA_PATH):
		data = load(DEFAULT_DATA_PATH)
	super._ready()
