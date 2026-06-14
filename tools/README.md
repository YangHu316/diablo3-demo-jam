# tools/ — 工具脚本与校验套件

> 本目录脚本均为**非运行时**工具:数据生成器 + headless 校验工具。
> 没有统一 runner —— 每个工具**独立按需运行**。本文件是它们的**唯一索引**(注册表)。
>
> Godot 4.6.3 可执行文件(本机未入 PATH):
> `C:\Users\leooosliu\Downloads\Godot_v4.6.3-stable_win64_console.exe`(headless 用控制台版,stdout 可捕获)。
> 下文 `<godot>` 即指它。

## 运行方式(两类)

| 类别 | 形态 | 运行命令 | 说明 |
|------|------|----------|------|
| **unit** | `extends SceneTree`,`_init()` 里手搓依赖 | `<godot> --headless --path . --script res://tools/<file>.gd` | autoload **不生效**,脚本内自行 `new()` 被测类。隔离单测。 |
| **integration** | `.tscn` 场景 + `.gd` 驱动 | `<godot> --headless --path . res://tools/<file>.tscn` | **走 `.tscn`(非 `--script`)**,autoload **全活**。真实信号接线/UI 渲染。 |
| **generator** | `extends SceneTree` | `<godot> --headless --path . --script res://tools/<file>.gd` | 生成资源/导出清单,非测试。 |

判定结果看 stdout 的 `OK/FAIL` 行与结尾 `N/N 判定通过`,以及进程 exit code(0=全过)。
退出时的 `ObjectDB instances leaked` / `DamageNumberPool: no current_scene` 是 headless 拆卸噪音,非失败。

---

## 校验工具 · unit(`--script`)

| 脚本 | 域 | 通过数 | 校验内容 |
|------|----|:----:|----------|
| `verify_data_tables.gd` | 数值表/数据加载 | — | 断言白怪@8 生命265/攻45/经验107、屠夫@7 生命11000、骸骨卫士@5 生命189/经验53 与 CSV 锁定值一致 |
| `verify_item_gen.gd` | ItemGenerator 装备生成 | — | 蓝1-2/黄3-4/史诗4-5 词缀、史诗200件首条保送顶值、靴子无暴伤词缀、品质权重 白>蓝>黄 |
| `verify_progression.gd` | 等级/经验/属性成长 | — | 击杀给XP、800XP 跨级到L3、升级属性成长+解锁载荷、满级封顶、无meta 兜底按 trash@L1 给XP |
| `verify_drop_system.gd` | 掉落系统+背包 | — | 普通怪~18%掉落、精英必出且5档品质、首橙白名单、硬保底强制橙、前4传奇不重复、满包拒收 |
| `verify_inventory_equip.gd` | 背包+装备+属性聚合 | — | 满40拒入、卸下发信号、属性聚合、换装净占用不变、双戒自动选槽 |
| `verify_knockback_death.gd` | 击退/死亡(回归) | — | 本体 queue_free 且 scale 归零(det≈0)时击退自动 cancel,不再调 move_and_slide |
| `verify_inventory_key.gd` | 输入/背包(回归) | — | 加载 main.tscn 注入按键,toggle_inventory 仅绑 B 键、按B开关面板、旧键E失效 |
| `verify_combat_handoff.gd` | 战斗①对接 | — | monster_id/level 查表给XP 且屠夫≠白怪、drop_source 映射 DropSystem.Source、String 写 meta 可读 |
| `verify_combat_equip_link.gd` | 装备聚合→伤害计算联通 | — | 武器均伤/敏捷暴击暴伤聚合/换装被动不丢/随从伤害/换强弓变强/利箭L8 锚点83 |
| `verify_level02.gd` | L2 关卡 | — | L2 加载、navmesh 多边形/光源/刚体数、7条导航路径连通、临界步行与通关时长估算 |
| `verify_l2_boot.gd` | L2 启动/L1 退役 | 3/3 | level_02_play.tscn 可加载并实例化,确认 L1 场景文件已删除 |
| `verify_boss.gd` | Boss 房导航 | — | boss_room.tscn 加载、navmesh 面数/StaticBody3D 数、南北/东西导航末端距<2 |
| `verify_boss_drop.gd` | Boss 掉落 | — | CSV 爆14件(2套装绿)、全 LEGENDARY、套装绿/普件橙、双戒落9/10槽、小怪零掉守门人爆14 |
| `verify_fixed_panel.gd` | 装备固定面板/中期档 | ⚠ 2/4 | loadout 解析敏捷150、面板含10属性、6项关键数值取自 loadout、多次取值恒定不随换装变 **(当前 2/4 红,见文末状态)** |
| `verify_settlement.gd` | 结算面板 | 5/5 | RiftManager 有 run_cleared/计数累加、守门人死触发结算不喂进度、面板解析、boss 掉落14件 |
| `verify_speedrun.gd` | 速通 override | 8/8 | 默认 goal106 零污染、启用后 goal15/守门人HP4000、启用=0 忽略、缺字段回落、喂15白怪触发 guardian |
| `verify_tower_buff.gd` | 功能塔状态机/乘区 | 6/6 | CSV 加载伤害/加速塔(+30%/+35%)、激活注入乘区1.30、互斥替换、CD内拒激活、到期清除、CD后重激活 |
| `verify_rift_progress.gd` | 大秘境进度 | 6/6 | 白怪+1·精英击杀不直接加权(§7.18)、同怪防重、守门人不计、时间球+3、满 GOAL 触发 guardian 并锁定 |
| `verify_rift_fail.gd` | 大秘境超时失败(语义) | 6/6 | 超时未满发 rift_failed 恰一次、_process 只触发一次、满进度不发、失败后冻结、reset 可重触发、未超时不发 |
| `verify_rift_timeout_durations.gd` | 大秘境超时(计时边界) | 9/9 | 剩余<=0 判负/子秒余量不误判/回拨钳上界/溢出钳0/守门人与失败先后两序/reset 回满 |
| `verify_elite_progress_ball.gd` | 精英进度球(§7.18) | 8/8 | 蓝球数1/黄球数2/每球%=0.05/非精英=0、add_progress_ball(0.05)≈5.3、蓝1球≈5.3/黄2球≈10.6、精英击杀不加权(progress0·kill2) |

## 集成校验 · integration(`.tscn`,autoload 全活)

| 脚本(`.tscn`) | 域 | 通过数 | 校验内容 |
|------|----|:----:|----------|
| `settlement_ui_harness.tscn` | 结算面板真实树 | ⚠ 13/16 | 真实树发 RiftManager.run_cleared,断言面板显示、02:05/37 文案、14行掉落上色含绿套、重发幂等 **(掉落名/上色3项当前红,见文末状态)** |
| `verify_boss_scene_settlement.tscn` | boss 房端到端 | VERIFY OK | 实例化 boss 房断言挂 HUD/InventoryPanel/SettlementPanel,emit run_cleared 后面板显示+14行、用时03:32/击杀53 |
| `itest_tower_ingame.tscn` | 功能塔交互全链路 | 8/8 | 布点表+Spawner 实例化双塔,物理步进断言伤害×1.30/移速×1.35、互斥还原、CD拒绝 |
| `itest_time_orb.tscn` | 时间球 HUD | ⚠ 5/7 | 时限120s、剩余初满与递减、HUD 时间球 fill.anchor_top=1-比例、MM:SS 文字、reset 回满 **(HUD 时间球节点2项当前红,见文末状态)** |

## 生成器 · generator(非测试)

| 脚本 | 用途 |
|------|------|
| `gen_data_tables.gd` | 按策划案数值生成 7 个 `data/*.tres`(词缀/基底/史诗/传奇/怪物/经验/Tier),换表时重跑 |
| `list_characters.gd` | 枚举 Characters.fbx 节点树、顶层子节点 AABB、动画清单及 Skeleton3D 骨骼名(标记手臂骨) |
| `slice_sheets.gd` | 按网格切 15 个 UI 图集为 AtlasTexture `.tres`,抽样 alpha<0.03 判空格跳过 |

---

## 当前套件状态(2026-06-14 全量重跑)

本表通过数为**本次实跑结果**(非历史声明值)。重跑发现 3 个工具当前为红 —— 均**与大秘境超时无关**(rift 系列 6/6+9/9 全绿),属各自域的回归,记录待修:

| 工具 | 现状 | 失败项 | 疑似原因 |
|------|------|--------|----------|
| `verify_fixed_panel.gd` | 2/4(原 4/4) | 4 项中 2 项 | 装备固定面板/中期档数值校验,需查 loadout 解析或面板属性源 |
| `settlement_ui_harness.tscn` | 13/16(原 16/16) | 14行掉落「物品名/品质色/绿套色」全 0 | 结算页 `_fill_loot` 掉落渲染未取到 item 名/色(可能 boss 掉落数据源或 `display_color()` 链路变动) |
| `itest_time_orb.tscn` | 5/7(原 11/11) | `_time_orb_fill`/`_time_orb_label` 节点未找到 | HUD 时间球节点结构/命名变更,harness 取节点失效 |

> 维护约定:**新增校验工具时在上表追加一行**(域 / 通过数 / 一句话校验内容);通过数留空 = 该工具未打印 `N/N` 总账。改动某域后请重跑对应工具并更新此「当前状态」表。
