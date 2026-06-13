extends OmniLight3D

# 火把光焰闪烁:多个不同频率正弦叠加,模拟火焰跳动。
@export var base_energy: float = 3.0
@export var flicker: float = 0.7
@export var speed: float = 11.0

var _t: float = 0.0

func _ready() -> void:
	_t = randf() * 10.0  # 错开相位,多个火把不同步

func _process(delta: float) -> void:
	_t += delta * speed
	var f := sin(_t) * 0.5 + sin(_t * 2.3 + 1.3) * 0.3 + sin(_t * 5.7) * 0.2
	light_energy = maxf(0.2, base_energy + f * flicker)
