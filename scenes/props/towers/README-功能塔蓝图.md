# 功能塔蓝图(可手动布置)

> 把 `TowerSpawner`(读 `数值表/tower_layout.csv` 自动布塔)里的**两种 buff 塔**复制成**可手动拖放**的蓝图资产。
> 复用原 `scenes/props/tower_trigger.tscn` + `scripts/entities/tower_trigger.gd` + `TowerBuffManager`(**原文件均未改**)。

| 蓝图 | tower_id | 效果(`tower_buffs.csv`) | 颜色 |
|---|---|---|---|
| `tower_damage.tscn` | `damage_tower` | 全局伤害 **+30%** · 持续 8s · CD 20s | 🔴 红 |
| `tower_speed.tscn` | `speed_tower` | 全局移速 **+35%** · 持续 8s · CD 20s | 🔵 蓝 |

## 用法

1. 把 `tower_damage.tscn` / `tower_speed.tscn` 拖进关卡场景(如 `level_02_play.tscn`,或 `level_02_encounters.tscn`)做实例。
2. 移动到想要的位置(Gizmo / Inspector Transform)。
3. 运行:玩家走进塔范围 → 按 **F** 激活 buff(互斥限时增益);CD 内塔变暗、提示「冷却中」。
4. 改数值:编辑 `数值表/tower_buffs.csv`(加成幅度 / 持续 / CD)——对蓝图与原 spawner 同时生效。

> 蓝图本身**零新代码**:只是 `tower_trigger.tscn` 的实例 + 预设 `tower_id` / `ready_color`。交互、buff、CD、上色全在原 `tower_trigger.gd` / `TowerBuffManager`。

## 与原 TowerSpawner 的关系(重要)

- 原 `TowerSpawner` 节点(在 `level_02_play.tscn`)仍会读 `tower_layout.csv` **自动布 2 座塔**(伤害塔 @出生点右、加速塔 @出生点左)。
- **若改用手动蓝图**:删掉 `level_02_play.tscn` 里的 `TowerSpawner` 节点 **或** 清空 `tower_layout.csv`,避免和手摆的塔**重复**。
  > 这两处属「原文件」,按你要求**未改动**——是否切换由你决定(删 TowerSpawner 节点 / 清 CSV 二选一)。
- 编辑器预览:`tower_trigger.gd` 非 `@tool`,编辑器里两座都显示默认**红柱**;**运行时**才按 `ready_color` 上色(伤害红 / 加速蓝)。位置以节点 gizmo 为准。
