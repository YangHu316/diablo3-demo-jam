# Gameplay + Technical Requirements

> 项目: 暗黑破坏神3风格 ARPG 垂直切片 Demo (3C 大框架)
> 引擎: Godot 4.4 / GDScript / 3D
> 目标: 跑通 3C 大框架（角色/相机/控制），后续叠加技能/AI/Boss/Juice

---

## Part A — Gameplay Design

### 1. Core Vision
- **类型**: 3D ARPG (Diablo 3 风格俯视视角)
- **核心体验**: 玩家用弓箭在俯视战场上射杀敌人，鼠标控制朝向，键盘移动
- **本阶段范围**: 仅 3C 骨架 + 基础射击 + 站桩敌人（不含技能/AI/Boss）

### 2. Core Mechanics
| 能力 | 输入 | 效果 |
|------|------|------|
| 移动 | WASD | 8方向移动，speed=7.0 m/s |
| 转向 | 鼠标 | 角色始终面朝鼠标地面投影点 |
| 强制站立 | 左 Shift | 按住时不响应移动，仍可转向 |
| 基础射击 | 鼠标左键 | 在玩家前方0.5m 生成箭矢，飞行30m/s，最大40m |
| 技能槽位预留 | 数字键 1/2/3 | 仅占位 input action，本阶段不实现 |

### 3. Scene Descriptions
- **主测试场地 (test_arena)**: 20×20m 灰色平面地板 + NavigationRegion3D（agent_radius=0.4, agent_height=1.8）+ 5个红色站桩敌人散布
- **环境氛围**: DirectionalLight3D 暗色调，WorldEnvironment 纯黑天空 + 轻微 SSAO，暗黑风低饱和

### 4. Game Flow
启动 → 加载 `main.tscn`(包含 `test_arena`) → 玩家出生在场地中心 → 自由移动+射击 → 敌人血量归0后 scale tween→0 → queue_free

### 5. Controller
| Input Action | Key |
|--------------|-----|
| move_up | W |
| move_down | S |
| move_left | A |
| move_right | D |
| attack_primary | 鼠标左键 |
| attack_secondary | 鼠标右键 |
| skill_1 | 1 |
| skill_2 | 2 |
| skill_3 | 3 |
| force_stand | Left Shift |

### 6. Level Design
- 1个测试关卡（test_arena），无失败/通关条件
- 5个站桩敌人分布在 (±5, 0, ±5)~(0, 0, 0) 范围内
- 验收标准:
  1. 俯视相机看到地板+绿色玩家+5个红色靶子
  2. WASD 流畅移动，角色面朝鼠标
  3. 左键射出箭矢飞向远处
  4. 命中敌人 → 闪白 → 多次命中后消失
  5. Shift 按住时不动但可转向射击

---

## Part B — Technical Specification

### B1. Script List (分层目录)
```
res://scripts/
├── autoload/
│   ├── game_manager.gd          # 全局游戏状态（占位）
│   └── combat_manager.gd        # 战斗事件总线（信号转发）
├── entities/
│   ├── player.gd                # 玩家控制：移动+转向+射击
│   ├── arrow.gd                 # 箭矢飞行+命中+伤害
│   └── enemy_zombie.gd          # 站桩敌人：生命+受伤+死亡
└── camera/
	└── topdown_camera.gd        # 俯视相机：跟随+插值+shake/push 接口
```

### B2. Node Structure (精确到叶子节点)

**main.tscn** (Node3D 根)
```
Main (Node3D)
├── TestArena (Node3D, instance test_arena.tscn)
├── Player (instance player.tscn)
└── Camera3D (TopdownCamera, script: topdown_camera.gd)
```

**test_arena.tscn** (Node3D 根)
```
TestArena (Node3D)
├── Floor (StaticBody3D, layer=4)
│   ├── MeshInstance3D (PlaneMesh 20×20, 灰色 StandardMaterial3D)
│   └── CollisionShape3D (BoxShape3D 20×0.1×20)
├── NavigationRegion3D (覆盖地板, agent_radius=0.4, agent_height=1.8)
├── DirectionalLight3D (energy=0.6, 偏黄暗调)
├── WorldEnvironment (Environment: 黑色天空 + SSAO + tonemap)
└── Enemies (Node3D)
	├── EnemyZombie1 (instance enemy_zombie.tscn) @(5, 0, 5)
	├── EnemyZombie2 @(-5, 0, 5)
	├── EnemyZombie3 @(5, 0, -5)
	├── EnemyZombie4 @(-5, 0, -5)
	└── EnemyZombie5 @(0, 0, 7)
```

**player.tscn** (CharacterBody3D 根, layer=1, mask=4)
```
Player (CharacterBody3D, group="player", script: player.gd)
├── BodyMesh (MeshInstance3D, CapsuleMesh h=1.8 r=0.3, 绿色)
├── ForwardCone (MeshInstance3D, CylinderMesh top=0 bottom=0.1 h=0.3, 朝-Z, 黄色)
├── CollisionShape3D (CapsuleShape3D h=1.8 r=0.3)
└── ArrowSpawnPoint (Marker3D, position=(0, 1.0, -0.5))
```

**enemy_zombie.tscn** (CharacterBody3D 根, layer=2, mask=4, group="enemies")
```
EnemyZombie (CharacterBody3D, group="enemies", script: enemy_zombie.gd)
├── BodyMesh (MeshInstance3D, CapsuleMesh h=1.8 r=0.3, 红色 StandardMaterial3D, 唯一材质)
└── CollisionShape3D (CapsuleShape3D h=1.8 r=0.3)
```

**arrow.tscn** (Area3D 根, layer=8, mask=2)
```
Arrow (Area3D, script: arrow.gd)
├── MeshInstance3D (CylinderMesh h=0.4 r=0.04, 黄色, 朝-Z)
└── CollisionShape3D (CapsuleShape3D h=0.4 r=0.05)
```

### B3. Collision Layer Table
| Layer | Bit Value | 名称 | 用途 |
|-------|-----------|------|------|
| 1 | 1 | Player | 玩家身体 |
| 2 | 2 | Enemy | 敌人身体 |
| 3 | 4 | World | 地板/墙体 |
| 4 | 8 | PlayerProjectile | 玩家箭矢 |

| 节点 | collision_layer | collision_mask | mask 解释 |
|------|----------------|----------------|-----------|
| Player (CharacterBody3D) | 1 | 4 | 与世界碰撞 |
| EnemyZombie (CharacterBody3D) | 2 | 4 | 与世界碰撞 |
| Floor (StaticBody3D) | 4 | 0 | 被动碰撞 |
| Arrow (Area3D) | 8 | 2 | 检测敌人 |

### B4. Input Actions
见 Part A §5。`project.godot` 中通过 `input/<action>={"events": [...]}` 块写入。

### B5. Autoloads
| 名称 | 路径 | 职责 |
|------|------|------|
| GameManager | res://scripts/autoload/game_manager.gd | 全局状态占位 |
| CombatManager | res://scripts/autoload/combat_manager.gd | 战斗事件总线 |

### B6. Signals
**CombatManager (全局)**:
- `hit_landed(attacker, target, damage: int, is_crit: bool, element: String, hit_position: Vector3, hit_direction: Vector3)`
- `enemy_killed(enemy, killer, overkill_damage: int, kill_direction: Vector3)`
- `player_damaged(amount: int, source)`

**Player**:
- `health_changed(current: int, max: int)`
- `player_died()`

**EnemyZombie**:
- `died(enemy)`

### B7. State Flags (Player)
| 标记 | 类型 | 默认 | 说明 |
|------|------|------|------|
| is_moving | bool | false | 当前帧有移动输入 |
| is_attacking | bool | false | 攻击冷却中 |
| is_invulnerable | bool | false | 无敌帧 |
| is_frozen | bool | false | 被冻结（占位） |

### B8. Boundaries & Robustness
| 实体/数值 | 最小值 | 最大值 | 越界行为 |
|----------|--------|--------|----------|
| Player.current_health | 0 | 200 | clamp |
| Enemy.current_health | 0 | 80 | clamp，0时死亡 |
| Arrow 飞行距离 | 0 | 40m | 超过 queue_free |
| 攻击冷却 | 0.3s | - | 冷却中忽略左键 |

**健壮性检查清单**:
- [ ] 鼠标射线 fallback：射线无碰撞时使用上一帧朝向
- [ ] 移动向量归一化（防斜向加速）
- [ ] 箭矢命中回调用 `is_instance_valid` 检查目标
- [ ] 敌人受伤前检查 `current_health > 0` 防重复死亡
- [ ] 敌人死亡 tween 完成前禁止再次 take_damage
- [ ] 全局信号连接使用 `CONNECT_DEFERRED` 或在 `_ready()` 中连接

### B9. Viewport Config
- `viewport_width` × `viewport_height` = **1152 × 648** (Godot 4 默认)
- `display/window/stretch/mode = "canvas_items"`
- `display/window/stretch/aspect = "expand"`
- `rendering/renderer/rendering_method = "forward_plus"`
