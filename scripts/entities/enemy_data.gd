extends Resource

# EnemyData — 怪物的数据定义。挂在 .tres 文件上,运行时由 enemy_zombie.gd 读取。
# 故意不用 class_name,避免 Godot 4 全局类解析竞态(参考 SkillData 同样处理)。
# 引用方用弱类型 Resource + duck typing。

# 怪物大类(用于策略分支:近战/远程/自爆/钻地等)
enum EnemyArchetype {
	MELEE_CHASE = 0,    # 近战追击 (缓行走尸/疯犬)
	RANGED = 1,         # 远程驻射 (骷髅弓手)
	AMBUSH = 2,         # 钻地伏击 (掘地食腐者)
	EXPLODER = 3,       # 自爆 (肿胀走尸)
	SUMMONER = 4,       # 召唤 (黑暗教团召唤者)
}

@export var enemy_id: StringName = &""
@export var enemy_name: String = ""
@export var archetype: int = EnemyArchetype.MELEE_CHASE

# ── 数值 ─────────────────────────────────────────────
@export_range(1, 10000, 1) var max_health: int = 80
@export_range(0, 1000, 1) var attack_damage: int = 12
@export_range(0.0, 30.0, 0.1) var move_speed: float = 4.2

# ── AI ───────────────────────────────────────────────
@export_range(0.0, 50.0, 0.1) var detection_range: float = 12.0  # 玩家进入此圈才进 CHASE(legacy,被 aggro_range 取代)
@export_range(0.0, 50.0, 0.1) var aggro_range: float = 14.0     # V3.0 仇恨范围:玩家进入此距离才转 CHASE(D3 经典近距激活)
@export_range(0.0, 50.0, 0.1) var lose_aggro_range: float = 18.0 # 玩家拉远到此距离才回 IDLE
@export_range(0.0, 10.0, 0.1) var attack_range: float = 2.0      # 进入此距离才进入 ATTACK
@export_range(0.0, 5.0, 0.05) var attack_windup: float = 0.8     # 攻击前摇(策划案口径)
@export_range(0.0, 5.0, 0.05) var attack_recovery: float = 0.4   # 攻击后摇 / 攻击后冷却
@export_range(0.0, 5.0, 0.05) var attack_hit_window: float = 0.2 # 命中判定持续帧

# ── 视觉(占位,后续接美术) ─────────────────────────
@export var albedo_color: Color = Color(0.827, 0.184, 0.184, 1)
