extends Area3D

# TowerTrigger: 功能塔交互节点 (重切方案 §2.5 / §2.5.1).
# 玩家进入范围 → 提示 → 按 interact(F) → TowerBuffManager.activate(tower_id).
# CD 内塔变暗、提示"冷却中"; CD 结束自动点亮.
#
# 复用 loot_drop 的交互范式: Area3D(layer/mask) + body_entered/exited + _process 检测按键.
# tower_id 对应 数值表/tower_buffs.csv 的行 id (damage_tower / speed_tower).

@export var tower_id: StringName = &"damage_tower"
# 激活态/冷却态塔身颜色 (伤害塔红 / 加速塔蓝 由外部或 _ready 推断).
@export var ready_color: Color = Color(1.0, 0.25, 0.25)
@export var cooldown_color: Color = Color(0.35, 0.35, 0.4)

var _player_in_range: bool = false
var _on_cd: bool = false

@onready var _nameplate: Label3D = get_node_or_null("Nameplate")
@onready var _body_mesh: MeshInstance3D = get_node_or_null("Body")

func _ready() -> void:
	add_to_group("tower")
	collision_layer = 16   # 与掉落物同层 (互动物专用), 不与敌人/箭矢互扰
	collision_mask = 1     # 检测玩家
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# 加速塔默认蓝.
	if String(tower_id) == "speed_tower":
		ready_color = Color(0.25, 0.6, 1.0)
	if TowerBuffManager != null:
		TowerBuffManager.tower_ready.connect(_on_tower_ready)
		TowerBuffManager.tower_cooldown_changed.connect(_on_cd_changed)
	_refresh_visual()

func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_try_activate()

func _try_activate() -> void:
	if TowerBuffManager == null:
		return
	if not TowerBuffManager.activate(tower_id):
		# CD 中或未知 id: 不激活.
		return
	_refresh_prompt()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_refresh_prompt()

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		if _nameplate != null:
			_nameplate.text = ""

func _on_tower_ready(tid: StringName) -> void:
	if tid != tower_id:
		return
	_on_cd = false
	_refresh_visual()
	_refresh_prompt()

func _on_cd_changed(tid: StringName, cd_remaining: float, _cd_total: float) -> void:
	if tid != tower_id:
		return
	_on_cd = cd_remaining > 0.0
	_refresh_visual()
	if _player_in_range:
		_refresh_prompt()

func _refresh_visual() -> void:
	if _body_mesh == null:
		return
	var col: Color = cooldown_color if _on_cd else ready_color
	var mat := _body_mesh.get_active_material(0)
	if mat is StandardMaterial3D:
		var dup: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
		dup.albedo_color = col
		dup.emission_enabled = true
		dup.emission = col
		_body_mesh.set_surface_override_material(0, dup)

func _refresh_prompt() -> void:
	if _nameplate == null or not _player_in_range:
		return
	if _on_cd and TowerBuffManager != null:
		var cd: float = TowerBuffManager.cooldown_remaining(tower_id)
		_nameplate.text = "冷却中 %.0fs" % ceil(cd)
	else:
		_nameplate.text = "按 F 激活"
