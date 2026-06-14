extends Node3D

# 集成测试驱动 (作为普通场景运行, autoload 全活): 真实场景树跑功能塔交互全链路.
# 运行: godot --headless --path . res://tools/itest_tower_ingame.tscn
#
# autoload (DataTables/TowerBuffManager) 正常运行时已就绪, tower_trigger.gd 的
# 全局标识符 TowerBuffManager 可解析. 本节点实例化真实 player + 两座真实塔, 用物理帧
# 驱动 Area3D body_entered, 调真实 _try_activate(), 断言伤害乘区 / 真实玩家移速乘区 / 互斥 / CD.

const DamageCalculator = preload("res://scripts/skills/damage_calculator.gd")

var _player: CharacterBody3D
var _dmg_tower: Area3D
var _spd_tower: Area3D
var _tbm: Node
var _step: int = 0
var _phase: int = 0
var _fails: int = 0
var _checks: int = 0

func _ready() -> void:
	_tbm = get_node_or_null("/root/TowerBuffManager")
	var dt: Node = get_node_or_null("/root/DataTables")
	if _tbm == null or dt == null:
		push_error("FAIL: autoload 未就绪 (TowerBuffManager/DataTables)")
		get_tree().quit(1)
		return

	_player = load("res://scenes/player/player.tscn").instantiate()
	add_child(_player)
	_player.global_position = Vector3(-83, 0.5, -7)

	# 经真实 TowerSpawner 读布点表 CSV 实例化两座塔 (验证蓝图布置全链路, 非手摆).
	_checks += 1
	var layout: Array = dt.get_tower_layout()
	if layout.size() < 2:
		_fail("⓪布点表加载: get_tower_layout 行数=%d (期望≥2)" % layout.size())
	else:
		print("OK⓪ tower_layout.csv 加载 %d 座塔" % layout.size())
	var spawner = load("res://scripts/levels/tower_spawner.gd").new()
	add_child(spawner)
	# spawner 用 call_deferred 布塔; 这里同步直接调以便本帧就绪.
	spawner._spawn_from_layout()
	for c in get_children():
		if c.is_in_group("tower"):
			if String(c.tower_id) == "damage_tower":
				_dmg_tower = c
			elif String(c.tower_id) == "speed_tower":
				_spd_tower = c
	_checks += 1
	if _dmg_tower == null or _spd_tower == null:
		_fail("⓪TowerSpawner 未实例化出 damage/speed 两座塔")
	elif _dmg_tower.global_position.distance_to(Vector3(-80, 0, -7)) > 0.01 or _spd_tower.global_position.distance_to(Vector3(-86, 0, -7)) > 0.01:
		_fail("⓪塔坐标与 CSV 不符 dmg=%s spd=%s" % [_dmg_tower.global_position, _spd_tower.global_position])
	else:
		print("OK⓪ TowerSpawner 按 CSV 坐标实例化两座塔 (dmg@-80 / spd@-86)")

	DamageCalculator.tower_dmg_mult = 1.0
	_player.speed_buff_mult = 1.0
	print("itest: 场景搭建完成(经布点表+Spawner), 开始物理步进...")

func _physics_process(_delta: float) -> void:
	_step += 1
	match _phase:
		0:
			_player.global_position = Vector3(-80, 0.5, -7)
			if _step > 8:
				_check_in_range(_dmg_tower, "伤害塔")
				_phase = 1
		1:
			_dmg_tower._try_activate()
			_checks += 1
			if abs(DamageCalculator.tower_dmg_mult - 1.30) > 0.001 or _tbm.active_tower_id() != &"damage_tower":
				_fail("②激活伤害塔: tower_dmg_mult=%.3f id=%s" % [DamageCalculator.tower_dmg_mult, _tbm.active_tower_id()])
			else:
				print("OK② 进伤害塔按F → tower_dmg_mult=1.30 (真实链路)")
			_phase = 2
			_step = 0
		2:
			_player.global_position = Vector3(-83, 0.5, -7)
			if _step > 8:
				_checks += 1
				if _dmg_tower._player_in_range:
					_fail("③离开伤害塔后 _player_in_range 仍 true")
				else:
					print("OK③ 离开伤害塔 → 退出范围, 提示清空")
				_phase = 3
				_step = 0
		3:
			_player.global_position = Vector3(-86, 0.5, -7)
			if _step > 8:
				_check_in_range(_spd_tower, "加速塔")
				_phase = 4
		4:
			_spd_tower._try_activate()
			_checks += 1
			var dmg_ok: bool = abs(DamageCalculator.tower_dmg_mult - 1.0) < 0.001
			var spd_ok: bool = abs(_player.speed_buff_mult - 1.35) < 0.001
			var id_ok: bool = _tbm.active_tower_id() == &"speed_tower"
			if not (dmg_ok and spd_ok and id_ok):
				_fail("④加速塔: dmg_mult=%.3f player.speed_buff_mult=%.3f id=%s" % [DamageCalculator.tower_dmg_mult, _player.speed_buff_mult, _tbm.active_tower_id()])
			else:
				print("OK④ 进加速塔按F → 互斥还原伤害=1.0 且真实玩家 speed_buff_mult=1.35")
			_phase = 5
		5:
			_checks += 1
			if _spd_tower._try_activate() or _tbm.activate(&"speed_tower"):
				_fail("⑤加速塔 CD 内仍可再激活")
			else:
				print("OK⑤ 加速塔 CD 内再激活被拒")
			_finish()

func _check_in_range(tower: Area3D, label: String) -> void:
	_checks += 1
	if not tower._player_in_range:
		_fail("①进%s后 body_entered 未触发 (_player_in_range=false)" % label)
	elif tower._nameplate != null and tower._nameplate.text != "按 F 激活":
		_fail("①进%s后提示文本异常: '%s'" % [label, tower._nameplate.text])
	else:
		print("OK① 进%s → body_entered 触发, 提示'按 F 激活'" % label)

func _fail(msg: String) -> void:
	push_error("FAIL: " + msg)
	_fails += 1

func _finish() -> void:
	print("\n==== itest_tower_ingame: %d/%d 判定通过 ====" % [_checks - _fails, _checks])
	get_tree().quit(1 if _fails > 0 else 0)
