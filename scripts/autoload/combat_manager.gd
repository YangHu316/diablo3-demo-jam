extends Node

# Global combat event bus (Autoload).
# Forwards combat events for decoupled listeners (UI, audio, FX).

signal hit_landed(attacker, target, damage: int, is_crit: bool, element: String, hit_position: Vector3, hit_direction: Vector3)
signal enemy_killed(enemy, killer, overkill_damage: int, kill_direction: Vector3)
signal player_damaged(amount: int, source)

func _ready() -> void:
	pass
