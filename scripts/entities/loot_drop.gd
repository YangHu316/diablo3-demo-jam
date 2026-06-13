extends Area3D

# LootDrop: 地面掉落物 (任务3). 品质着色名牌 + 橙光柱, 手动拾取 (DUI-02/05).
# 由 LootManager 在击杀位置 spawn, setup(item) 注入物品.
#
# 碰撞: layer=16 (掉落物专用), mask=1 (检测玩家). 不与敌人/箭矢/地面互扰.
# 拾取: 玩家进入范围 -> 提示 -> 按 interact(F) -> Inventory.add_item -> 成功销毁.

signal picked_up(item)

@export var bob_height: float = 0.15
@export var bob_speed: float = 2.0
@export var spin_speed: float = 1.2

var item: ItemInstance = null
var _player_in_range: bool = false
var _player: Node3D = null
var _base_y: float = 0.0
var _t: float = 0.0

@onready var nameplate: Label3D = $Nameplate
@onready var beam: MeshInstance3D = $Beam

func _ready() -> void:
	add_to_group("loot")
	collision_layer = 16
	collision_mask = 1
	monitoring = true
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_base_y = global_position.y
	if item != null:
		_apply_visuals()

# 由 LootManager 在 add_child 之后调用注入物品.
func setup(loot_item: ItemInstance) -> void:
	item = loot_item
	if is_node_ready():
		_apply_visuals()

func _apply_visuals() -> void:
	var color: Color = ItemInstance.QUALITY_COLORS.get(item.quality, Color.WHITE)
	# 名牌文本: 品质着色; 弓附 DPS 数字 (DUI-02).
	var label: String = item.display_name
	if item.slot == EquipSlots.Slot.BOW:
		label += "  DPS %d" % _weapon_dps()
	nameplate.text = label
	nameplate.modulate = color
	# 光柱仅传奇可见 (表现分级稀缺, §1 红线3).
	beam.visible = item.is_legendary()
	if beam.visible:
		var mat := beam.get_active_material(0)
		if mat is StandardMaterial3D:
			var dup: StandardMaterial3D = (mat as StandardMaterial3D).duplicate()
			dup.albedo_color = color
			dup.emission = color
			beam.set_surface_override_material(0, dup)

# 弓 DPS 估算 = 该物品武器伤害词缀总和 (无则按 Tier 上沿近似).
func _weapon_dps() -> int:
	var dmg: float = 0.0
	for a in item.affixes:
		if int(a["stat_kind"]) == AffixDef.StatKind.WEAPON_DAMAGE:
			dmg += float(a["value"])
	return int(round(dmg))

func _process(delta: float) -> void:
	_t += delta
	# 漂浮 + 自转, 让地面物有"可拾取"的活感.
	global_position.y = _base_y + sin(_t * bob_speed) * bob_height
	rotate_y(spin_speed * delta)
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_try_pickup()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_player = body as Node3D
		nameplate.outline_size = 12   # 进范围加描边高亮

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		_player = null
		nameplate.outline_size = 0

func _try_pickup() -> void:
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv == null:
		return
	if inv.add_item(item):
		picked_up.emit(item)
		queue_free()
	# 满包: 留在地面 (add_item 返回 false), 不销毁.
