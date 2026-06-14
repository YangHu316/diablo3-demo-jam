# 1 分钟速通 · 测试数值系统

> 关卡C / 2026-06-14 · **仅测试用**(快速 QA / 联调:一把跑完整大秘境闭环 ≈1 分钟)。
> 单一文件 = [`speedrun_test.csv`](speedrun_test.csv)(`importer="keep"` · 程序 `FileAccess` 直读)。**这是一套 override**:测试模式开启时,套在正式 V3.0 数值之上;关闭则完全不影响正式值。

---

## 一、目的

正式版单局大秘境目标 **5–10 分钟**。本配置把"全程"(选层 → 入秘境割草填进度条 → 守门人战 → 击杀爆装 → 结算)压到 **≈1 分钟**,让程序/QA 反复跑闭环不必每次磨 5–10 分钟。**只改"跑多久"的几个旋钮,不改玩法结构、掉落表、键位、地图。**

## 二、旋钮表(= `speedrun_test.csv`)

| key | 测试值 | 正式值 | override 到哪 |
|---|---|---|---|
| 启用 | 1 | — | 1=本表生效;0=忽略走正式值 |
| 守门人HP | **4000** | 24000 | `rift_monsters.csv` 的 `guardian` 生命 → 约 7s 秒杀级 |
| 守门人ATK | **40** | 90 | `guardian` 攻击 → 下调防测试误死(可选) |
| 进度条目标 | **15** | ≈106 | 大秘境怪物进度条满值 → 约 15 只白怪权重即满 |
| 时间条秒 | **120** | 360 | 限时失败计时 → 给足不卡时间 |
| 刷怪密度倍率 | 1.0 | 1.0 | 可选 0.5~1.0(低进度目标已够快) |
| 玩家DPS倍率 | 1.0 | 1.0 | 玩家面板不变(已一发秒白怪);可临时 ×2 |
| 精英黄名HP倍率 | 1.0 | — | 可选 0.5(精英本就一发秒) |
| 跳过选层 | 1 | — | 1=直接进场跳过选层界面 |
| 守门人固定掉落 | 沿用 | — | `boss_drop_list.csv` 不变(照样验爆装) |

> **核心三旋钮**:守门人 HP(24000→4000)、进度条目标(≈106→15)、跳过选层。其余默认不动即可达 ~1 分钟。

## 三、时间预算(≈55s < 1min)

| 时间 | 阶段 | 依据 |
|---|---|---|
| 0:00–0:03 | 入场(跳过选层) | 跳过选层=1 |
| 0:03–0:28 | 割草填进度条(≈15 权重) | 玩家一发秒白怪·西门开场(8)+枢纽(6)≈14~16 杀 |
| 0:28–0:31 | 进度满 → 守门人房切场景 | RiftManager |
| 0:31–0:43 | 守门人战(HP 4000) | 547 DPS → 7.3s 纯利箭 + 走位 ≈10~12s |
| 0:43–0:52 | 绿橙爆装 + 结算面板 | 固定爆装照常 |
| **合计** | **≈52~55s** | < 1 分钟 ✓ |

> 玩家不必清光全图——只需割够 15 进度权重即召唤守门人(跑过未清的怪不影响)。

## 四、程序怎么调用(给系统②/战斗①)

**机制建议**:一个测试开关 → 读本表 → 把 override 套到运行期值。开关任选其一:
- 命令行:`Godot --path . res://... -- --speedrun`(读 `OS.get_cmdline_user_args()`);
- 环境变量:`OS.get_environment("RIFT_SPEEDRUN") == "1"`;
- 或 `GameManager.test_speedrun = true`(Inspector/调试勾选)。

**读表 + 套用(GDScript 范例,放 RiftManager 初始化处)**:
```gdscript
func _load_speedrun_overrides() -> void:
    var path := "res://数值表/测试-1分钟速通/speedrun_test.csv"
    if not FileAccess.file_exists(path): return
    var f := FileAccess.open(path, FileAccess.READ)
    var ov := {}
    f.get_line()  # 跳表头
    while not f.eof_reached():
        var cols := f.get_line().split(",")
        if cols.size() >= 2: ov[cols[0]] = cols[1]
    if ov.get("启用","0") != "1": return
    # —— 套用 ——（示例字段名按你们实现改）
    guardian_max_hp   = int(ov.get("守门人HP", guardian_max_hp))
    guardian_attack   = int(ov.get("守门人ATK", guardian_attack))
    rift_progress_goal = int(ov.get("进度条目标", rift_progress_goal))
    rift_time_limit    = float(ov.get("时间条秒", rift_time_limit))
    skip_tier_select   = ov.get("跳过选层","0") == "1"
```
- 守门人 HP/ATK:测试时覆写 `butcher.gd` 实例(或 `data/monsters.tres` 的 guardian);或 RiftManager 在生成守门人后 set。
- 进度条目标 / 时间条:RiftManager 的 `progress_goal` / `time_limit` 直接吃本表。
- 密度/DPS/精英 倍率:×到对应生成数量 / 伤害(默认 1.0 = 不动)。

## 五、口径红线

- **override 不是新玩法**:只改数值,玩法/掉落/键位/地图与正式版完全一致(测试照样验证割草手感 + 爆装观感)。
- **不进正式包**:发布构建关掉测试开关(启用=0 或不读本表)。
- **单一事实源**:正式值仍在 `数值表/rift_monsters.csv`/`player_loadout.csv`/`boss_drop_list.csv` + RiftManager;本表只列"压时长"的差量。
