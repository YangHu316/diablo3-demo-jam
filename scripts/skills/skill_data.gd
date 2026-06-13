extends Resource

# SkillData — 单个技能的数据定义,挂在 .tres 文件上,运行时由 SkillSlotManager 读取。
#
# 注:故意不使用 class_name,避免 Godot 4 在 autoload/项目结构变动后偶发的
# "Compilation failed (error 43) at line 1" 全局类解析竞态。所有引用方都用
# 弱类型 Resource + duck typing,或 const X = preload(...) 做类型化。

# 技能大类(SkillExecutor 据此分发)
enum SkillType {
	PROJECTILE = 0,  # 射击 / 投射物
	MOVEMENT = 1,    # 位移 (如冲刺、闪避)
	SUMMON = 2,      # 召唤 / 召唤物
	MELEE = 3,       # 近战
}

# ── 通用 ────────────────────────────────────────────
@export var skill_id: StringName = &""
@export var skill_name: String = ""
@export_range(0.0, 60.0, 0.05) var cooldown: float = 0.0
@export_range(0.0, 200.0, 1.0) var focus_cost: float = 0.0
@export_range(0.0, 100.0, 1.0) var focus_gain_on_hit: float = 0.0
@export_range(0.0, 10.0, 0.05) var skill_multiplier: float = 1.0
@export var element: StringName = &"physical"
@export var skill_type: int = SkillType.PROJECTILE
@export_multiline var description: String = ""

# ── 投射物专用 ──────────────────────────────────────
@export_range(1, 32, 1) var projectile_count: int = 1
@export_range(0.0, 360.0, 1.0) var projectile_spread_angle: float = 0.0  # 总扇形角度(度),5箭60°即左右各30°
@export var can_penetrate: bool = false

# ── 命中范围/状态(冰冻箭、火焰箭等)──────────────
@export_range(0.0, 30.0, 0.1) var aoe_radius: float = 0.0       # 命中后范围效果半径,0=单体
@export var status_effect: StringName = &""                       # frost / burn / shock / ""
@export_range(0.0, 30.0, 0.05) var status_duration: float = 0.0   # 状态持续秒

# ── 位移技能专用(翻滚/冲锋)─────────────────────
@export var is_movement_skill: bool = false
@export_range(0.0, 30.0, 0.1) var move_distance: float = 0.0      # 位移距离
@export_range(0.0, 5.0, 0.05) var move_duration: float = 0.0      # 位移时长
@export var grants_invuln: bool = false                            # 期间无敌帧
@export var cancels_attack_cooldowns: bool = false                 # 取消左键/右键攻击 CD

# ── 召唤技能专用(女武神/狼群等)─────────────────
@export var summon_scene: PackedScene = null
@export_range(0.0, 600.0, 0.5) var summon_duration: float = 0.0   # 召唤物存在时长
@export_range(1, 16, 1) var summon_max_count: int = 1             # 同种召唤物上限,超出移除最旧
