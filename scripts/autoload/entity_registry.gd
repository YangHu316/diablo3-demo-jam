extends Node

# EntityRegistry — 全局敌人注册表。
# 替代所有 get_tree().get_nodes_in_group("enemies")，避免每次调用 O(n) 全树遍历。
# 敌人在 _ready() 调用 EntityRegistry.register_enemy(self)
# 敌人在 _exit_tree() 调用 EntityRegistry.unregister_enemy(self)

var enemies: Array = []

func register_enemy(e: Node) -> void:
	if not enemies.has(e):
		enemies.append(e)

func unregister_enemy(e: Node) -> void:
	enemies.erase(e)
