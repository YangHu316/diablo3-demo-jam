# 功能塔蓝图(可手动布置)

> 把 `TowerSpawner`(读 `数值表/tower_layout.csv` 自动布塔)里的**两种 buff 塔**复制成**可手动拖放**的蓝图资产。
> 复用原 `scenes/props/tower_trigger.tscn` + `scripts/entities/tower_trigger.gd` + `TowerBuffManager`(**原文件均未改**)。视觉换 `SM_Env_GlowingOrb_01` **发光球模型** + 新助手 `scripts/levels/tower_orb_glow.gd`。

| 蓝图 | tower_id | 效果(`tower_buffs.csv`) | 颜色 |
|---|---|---|---|
| `tower_damage.tscn` | `damage_tower` | 全局伤害 **+30%** · 持续 8s · CD 20s | 🔴 红 |
| `tower_speed.tscn` | `speed_tower` | 全局移速 **+35%** · 持续 8s · CD 20s | 🔵 蓝 |

## 用法

1. 把 `tower_damage.tscn` / `tower_speed.tscn` 拖进关卡场景(如 `level_02_play.tscn`,或 `level_02_encounters.tscn`)做实例。
2. 移动到想要的位置(Gizmo / Inspector Transform)。
3. 运行:玩家走进塔范围 → 按 **F** 激活 buff(互斥限时增益);CD 内塔变暗、提示「冷却中」。
4. 改数值:编辑 `数值表/tower_buffs.csv`(加成幅度 / 持续 / CD)——对蓝图与原 spawner 同时生效。

> **模型 = 发光球**:蓝图把原圆柱 `Body` 隐藏(`visible=false` 覆写·**未改原场景**),换上 `SM_Env_GlowingOrb_01.fbx`。`scripts/levels/tower_orb_glow.gd`(`@tool`)给球叠**彩色 + 微弱自发光**(`emission_energy≈0.45`,对齐项目 l2_markers 自发光约定)的 `material_override`,并监听 `TowerBuffManager.tower_ready` / `tower_cooldown_changed`(按 `tower_id` 过滤)**复刻互动变色**:就绪 = 塔色 / 冷却 = 暗灰。buff / CD / F 激活 仍全在原 `tower_trigger.gd`,**原塔脚本/场景零改动**。两塔不同 `ready_color` 区分(伤害 🔴 / 加速 🔵)。

## 与原 TowerSpawner 的关系(重要)

- `tower_layout.csv` **已清空** → `TowerSpawner` **不再自动布塔**(节点仍在 `level_02_play.tscn`,空表 = 布 0 座)。功能塔现全部手摆蓝图。
- 要恢复自动布塔:把塔行填回 `tower_layout.csv`(届时注意别和手摆塔重复)。
- 编辑器预览:`tower_orb_glow.gd` 是 `@tool`,**编辑器里发光球就按塔色亮**(伤害红 / 加速蓝),运行时再随激活/CD 切色。⚠ **发光球 `scale`/`y` 是估值**(headless 测不到 FBX 原生尺寸,参照立柱 ×78≈3.5m 设了 ×40),编辑器里按需微调大小/高度。
