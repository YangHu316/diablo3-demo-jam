# Art Requirements

> 项目: 暗黑破坏神3风格 ARPG 垂直切片 Demo (3C 骨架阶段)
> 阶段: 几何占位为主，无需复杂美术资产

---

## Art Style
- **风格**: 暗黑风 3D，低饱和度、暗调环境
- **配色方案**:
  - Player Capsule: `#4CAF50` (绿色, 占位)
  - Player Forward Cone: `#FFC107` (黄色, 朝向指示)
  - Enemy Capsule: `#D32F2F` (红色, 占位)
  - Floor: `#3A3A3A` (深灰)
  - Arrow: `#FFEB3B` (亮黄)
  - Ambient/Sky: `#000000` (纯黑)
  - DirectionalLight: 偏黄暗调 `#FFE0B2`, energy=0.6
- **本阶段策略**: 全部使用 Godot 内置 PrimitiveMesh（CapsuleMesh、PlaneMesh、CylinderMesh）+ StandardMaterial3D，**不生成任何外部美术资产文件**。

---

## Sprites / Models (占位)
本阶段所有视觉元素均使用 Godot 内置 Mesh + Material 直接在 .tscn 中创建，**无需 Artist 生成 PNG/GLB 文件**。

| 实体 | 视觉表现 | 实现方式 |
|------|---------|---------|
| Player 身体 | 绿色胶囊 | CapsuleMesh + StandardMaterial3D(albedo=#4CAF50) |
| Player 朝向锥 | 黄色小锥 | CylinderMesh(top=0) + albedo=#FFC107 |
| Enemy 身体 | 红色胶囊 | CapsuleMesh + StandardMaterial3D(albedo=#D32F2F) (唯一材质，受伤闪白用) |
| Arrow | 黄色细棒 | CylinderMesh + albedo=#FFEB3B |
| Floor | 灰色平面 | PlaneMesh 20×20 + albedo=#3A3A3A |

---

## Environment
- **天空**: 纯黑 (Sky.background_color = Color.BLACK)
- **光照**: DirectionalLight3D（暗黄偏向，模拟阴沉氛围）
- **后处理**: SSAO 轻度开启、tonemap=Filmic

---

## 3D Scenes (Infinigen)
**本阶段不使用 Infinigen**。仅使用 Godot 内置场景节点搭建测试场地。

---

## UI
本阶段无 UI（无 HUD、无菜单）。后续阶段再加。

---

## Audio
本阶段无音频。后续叠加技能/Boss 时再加。

---

## Asset Manifest

| 类型 | 路径 | 尺寸 | 说明 |
|------|------|------|------|
| — | — | — | **本阶段无需生成任何外部资产文件** |

**Artist 任务**: 本阶段无任务。所有视觉占位由 Developer 在 `.tscn` 中直接用内置 Mesh + Material 实现。
