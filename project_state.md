# Project State

> Auto-generated. Do not edit manually.
> Last updated: 2026-06-13 12:50:03

## 概况
- 阶段: idle | 进度: 0%
- 状态: created

## 关键文件
### Scripts (6)
- res://scripts/autoload/game_manager.gd
- res://scripts/autoload/combat_manager.gd
- res://scripts/camera/topdown_camera.gd
- res://scripts/entities/arrow.gd
- res://scripts/entities/player.gd
- res://scripts/entities/enemy_zombie.gd
### Scenes (5)
- res://scenes/main.tscn
- res://scenes/projectiles/arrow.tscn
- res://scenes/player/player.tscn
- res://scenes/enemies/enemy_zombie.tscn
- res://scenes/arena/test_arena.tscn
### Assets
- 2 个资产文件

## Autoloads
- GameManager
- CombatManager

## 已实现功能
- ✅ 俯视 2.5D 相机（跟随+插值+shake/push 接口）
- ✅ WASD 8方向移动（归一化防斜向加速）
- ✅ 鼠标地面投影转向（射线 fallback 容错）
- ✅ Shift 强制站立
- ✅ 左键射箭（0.3s 冷却）+ 箭矢飞行+命中+伤害
- ✅ 敌人受伤闪白 + 死亡 scale tween
- ✅ Autoload 战斗事件总线
- ✅ 测试场地 + 5个站桩敌人 + NavigationRegion3D（agent 0.4/1.8 已烘焙）
- ✅ 暗黑风环境光照（DirectionalLight 暗黄 + 黑色天空 + SSAO + Filmic）

## 已知问题
（无）

## 上次意图
# MagicDawnAI Prompt 指南 - 战斗程序（程序①）

> 暗黑破坏神3 垂直切片 Demo / Godot 4.4 / GDScript / 3D
> 你的职责：玩家弓箭战斗、5技
