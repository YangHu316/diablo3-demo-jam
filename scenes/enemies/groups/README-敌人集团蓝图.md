# 敌人集团蓝图(可手动调整位置 + 数量)

> 取代 `level_02_depths.gd` 里 `ENCOUNTERS` 脚本刷怪(固定位置/固定数量/绑死白盒)。
> 现在怪物分布 = **场景里手动摆的蓝图实例**,策划可随意拖、改数量、增删。

## 六个分种类蓝图(`scenes/enemies/groups/`)

| 蓝图 | 集群 | 默认数量 | 阵型 | enemy_scene | enemy_data |
|---|---|---|---|---|---|
| `group_zombie_x10.tscn` | 走尸集群 | **10** | cluster | enemy_zombie | walking_corpse.tres |
| `group_dog_x5.tscn` | 墓园疯狗集群 | **5** | cluster | enemy_zombie ※ | graveyard_dog.tres |
| `group_archer_x5.tscn` | 骷髅射手集群 | **5** | line | enemy_archer | skeleton_archer.tres |
| `group_bloated_x5.tscn` | 肿胀走尸集群 | **5** | cluster | enemy_bloated | bloated_corpse.tres |
| `group_summoner_x3.tscn` | 召唤者集群 | **3** | cluster | enemy_goblin_shaman ※ | cult_summoner.tres |
| `group_skeleton_guard_x5.tscn` | 骸骨卫士集群 | **5** | line | enemy_skeleton_knight | skeleton_guard.tres |

※ 视觉占位,可由美术/战斗① 换 `enemy_scene` 成专属模型(数值/行为由 `enemy_data` 决定,与视觉解耦)。

## 怎么用(策划手动调)

1. **加一组怪**:把某个 `group_*.tscn` 拖进 `scenes/levels/level_02_encounters.tscn`(或任意关卡场景)做实例。
2. **改位置**:选中实例 → 移动(Gizmo 或 Inspector Transform)。坐标 = 世界坐标 ≈ 白盒 WALK×1.5。
3. **改数量**:选中实例 → Inspector 改 `count`(1~50)。也可直接复制整组 / 删除整组。
4. **改散布半径**:`spawn_radius`;阵型 `formation`(cluster/line/surround)。

> 每个蓝图是一个预设好的 `spawn_trigger`(战斗① 现成组件,**零新代码**),`preplaced=true`:
> 关卡加载即在该位置生成怪并 **IDLE 待机**,玩家走进怪自身 detection 范围后由 `enemy_base` 自启追击(近距激活仇恨)。
> ⚠ **编辑器里看不到怪**:`preplaced` 经 `SpawnManager`(autoload·仅运行时)生成 → 编辑器只显示 Area3D 节点本身;**运行(F5)才出怪**。摆位时看节点位置即可。

## 当前分布(起点,可改)

`scenes/levels/level_02_encounters.tscn` 已按原白盒遭遇位置摆了 12 组(西廊/枢纽/东廊/齿轮室/右环/北廊/南长廊/Boss入口/Boss厅),已被 `level_02_play.tscn` 实例化(节点 `Encounters`)。约 83 只怪。直接在此场景调即可。

## 迁移说明 / 交接

- `level_02_depths.gd` 的 `_build_encounters()` 调用**已注释停用**(脚本刷怪退役);`ENCOUNTERS`/`ENCOUNTER_ENEMY`/`ENCOUNTER_DATA` 常量保留仅供参考。需临时回退:取消该行注释。
- **战斗①**:① 召唤者(召唤缓行走尸)、骸骨卫士(正面 120° 减伤盾墙)的**特殊 AI** 暂未接 → 当前走 `enemy_base` 基础追击 + 对应 `.tres` 数值;接好后蓝图无需改(行为在敌人脚本里)。② 若 ~83 只预生成怪性能吃紧:减组数 / 调 `count` / 或给远点的组用旧 `one_shot` 触发(把 `preplaced` 关掉、留触发圈)。
- **美术**:疯狗 / 召唤者视觉为占位,可换 `enemy_scene` 成狗 / 法师模型。
- 精英(蓝名/黄名)不在此 6 组内:精英是「普通怪放大 + 辉光 + 进度球」,见 `数值表/elites.csv` 与大秘境配置 §二·B,单独摆放。
