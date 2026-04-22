# MyProject4 — 技术架构与开发日志

> 本文档供 LLM 或新开发者快速理解项目的技术决策、已实现功能和已知问题。

---

## 一、项目概览

| 项 | 值 |
|---|---|
| **目标** | 2D 横版动作游戏，对标《武士 零》(Katana ZERO) |
| **引擎** | Unreal Engine 5.7 |
| **视角** | 3D 资产 + 固定 2.5D 侧视角（Y 轴锁定） |
| **模板** | Third Person 模板创建，后迁入 Game Animation Sample 资产 |
| **核心角色** | `SandboxCharacter_CMC`（Blueprint），父类为 `ASandboxCharacterBase`（C++） |

---

## 二、工程来源与迁移

### 2.1 基础层
- 用 UE 5.7 的 **Third Person** C++ 模板创建 `MyProject4`。

### 2.2 动画系统迁移
- 从 **Game Animation Sample** (Epic 官方示例) 迁入以下资产：
  - `SandboxCharacter_CMC`（角色 BP + ABP + 所有动画依赖）
  - `AC_TraversalLogic`（攀爬/翻越组件）
  - `LevelBlock_Traversable`（可攀爬关卡方块）
  - `Variant_Sandbox` 相关 Input/Camera/GameMode 资产
- 迁移后需要启用的插件（已写入 `.uproject`）：
  - `AnimationWarping`
  - `AnimationLocomotionLibrary`
  - `Chooser`
  - `PoseSearch`
  - `MotionWarping`

### 2.3 Git 管理策略
- `.gitignore` 默认忽略所有内容（`*`），仅白名单放行：
  - `Source/` — 全部 C++ 源码
  - `MyProject4.uproject` — 插件/模块配置
  - `Content/Blueprints/SandboxCharacter_CMC.uasset` — 改过父类和 EventGraph
  - `Content/Input/IMC_Sandbox.uasset` — 改过按键映射
  - `Content/Variant_SideScrolling/Lvl_SideScrolling.umap` — 测试关卡
- 其余资产由 Third Person 模板 + Game Animation Sample 迁移还原。

---

## 三、核心架构

### 3.1 角色类继承关系

```
ACharacter (Engine)
  └── ASandboxCharacterBase (C++, Source/MyProject4/SandboxCharacterBase.h/.cpp)
        └── SandboxCharacter_CMC (Blueprint, Content/Blueprints/)
```

- **ASandboxCharacterBase**：C++ 基类，处理所有对时间敏感的物理/输入逻辑。
- **SandboxCharacter_CMC**：Blueprint 子类，保留 Game Animation Sample 的完整 Locomotion 系统（Motion Matching + Choosers + Blend Stack + Offset Root Bone）。

### 3.2 动画系统架构（来自 Game Animation Sample）

```
AnimGraph 管线：
  Motion Matching  ──→  Blend Poses by Int  ──→  Apply Mesh Space Additive (Lean)
  Blend Stack      ──→       ↑                     ──→  Offset Root Bone
  Slot DefaultSlot ──→  (Traversal/Attack Montage)       ──→  Foot Placement
                                                         ──→  Pose History
                                                         ──→  Output Pose
```

- **Motion Matching**：负责走跑停转等 locomotion，由速度/加速度/方向自动匹配动画。
- **Blend Stack**：通过 `On State Entry` 注入动画，和 Motion Matching 二选一混合。
- **Slot 'DefaultSlot'**：Montage 注入点，攀爬动画和攻击动画都从这里进入。
- **Offset Root Bone**：独立于 Actor Rotation 控制 Mesh 视觉朝向，有自己的插值逻辑。

### 3.3 输入系统

- 使用 **Enhanced Input** 系统。
- 移动输入（`IA_Move`）在 Blueprint EventGraph 中绑定。
- 攻击输入（`IA_ComboAttack`）在 C++ `SetupPlayerInputComponent` 中绑定。
- 按键映射在 `IMC_Sandbox`（`Content/Input/IMC_Sandbox.uasset`）中配置。

---

## 四、已实现功能

### 4.1 2D 输入重映射

**问题**：Game Animation Sample 默认 W/S 控制前后（世界 X 轴），A/D 控制左右（世界 Y 轴）。2D 横版需要 A/D 控制前后，W/S 控制上下。

**解决方案**：在 `IMC_Sandbox` 中用 Modifier 重映射：

| 按键 | Modifier | 输出 | 游戏效果 |
|---|---|---|---|
| **W** | 无 Swizzle | X=1 | 向上（跳跃方向） |
| **S** | Negate | X=-1 | 向下 |
| **D** | Swizzle YXZ | Y=1 | 向右（前进方向） |
| **A** | Swizzle YXZ + Negate | Y=-1 | 向左（后退方向） |

### 4.2 自动转身（面朝移动方向）

**问题**：角色按 A 后退时不转身，背对着走。

**解决方案**：
- 在 `SandboxCharacter_CMC` BP 的 Class Defaults 中：`bOrientRotationToMovement = true`
- BP 中的 `Wants to Strafe` 变量设为 `false`
- `UpdateRotation_PreCMC` 函数中的 Strafe 相关逻辑被旁路

### 4.3 Y 轴平面锁定

**问题**：3D 角色会在 Y 轴方向漂移，掉出 2D 平台。

**解决方案**：在 Character Movement Component 中：
- `bConstrainToPlane = true`
- `PlaneConstraintNormal = (0, 1, 0)`

### 4.4 Wall Jump（弹墙跳）

**文件**：`SandboxCharacterBase.cpp` → `TryWallJump()`

**逻辑**：
1. 角色在空中 + 有水平输入 → 向前方射线检测墙壁
2. 命中墙壁 → 计算 ImpactNormal 反弹方向
3. 关闭 `bOrientRotationToMovement` → `SetActorRotation(反弹方向)` → `LaunchCharacter(反弹力)`
4. 设置 `bWallJumpInputLocked = true`，0.3 秒内：
   - Blueprint `IA_Move` 事件被 Branch 拦截，不执行 `AddMovementInput`
   - Blueprint `UpdateRotation_PreCMC` 被 `HasWallJumped()` Branch 跳过
5. 0.3 秒后 `ResetWallJump()` 恢复一切

**已知问题**：
- 视觉转身不是瞬间的。ABP 的 `Offset Root Bone` 节点有自己的旋转插值，独立于 Actor Rotation。需要调 ABP 中 `OffsetRootRotationMode` 相关参数才能加速视觉转身。此问题暂缓。

### 4.5 Coyote Time（郊狼时间）

**文件**：`SandboxCharacterBase.cpp` → `MultiJump()`

**逻辑**：角色离开平台后 0.16 秒内仍可执行普通跳跃。通过 `OnMovementModeChanged` 记录开始下落时间。

### 4.6 Double Jump（二段跳）

**文件**：`SandboxCharacterBase.cpp` → `MultiJump()`

**逻辑**：在空中且不满足 Wall Jump 和 Coyote Time 条件时，允许一次额外跳跃。`JumpMaxCount = 3`（普通 + 二段 + 弹墙）。落地时重置。

### 4.7 Traversal（攀爬/翻越）

**组件**：`AC_TraversalLogic`（Blueprint Component，来自 Game Animation Sample）

**功能**：
- **Vault**：翻越矮障碍物
- **Mantle**：攀上高台（爬上沿）
- **Climb**：抓住上沿攀爬

**触发**：通过 `LevelBlock_Traversable` Actor 的 Spline Ledge 定义可攀爬边缘。目前仅顶部边缘有 Spline，侧面暂无（无法侧面抓墙）。

### 4.8 Combo Attack（连击攻击）

**文件**：`SandboxCharacterBase.cpp` → `ComboAttack()`, `OnComboAttackPressed()`, `AttackMontageEnded()`

**逻辑**：
1. 鼠标左键（`IA_ComboAttack`）触发 → C++ `OnComboAttackPressed()`
2. 若未在攻击中 → `Montage_Play(ComboAttackMontage)` 通过 DefaultSlot 注入 ABP
3. 若已在攻击中 → 缓存输入时间 `CachedAttackInputTime`
4. Montage 结束时 `AttackMontageEnded()` → 若缓存输入未过期 → 自动连续攻击
5. Montage 资源和 Input Action 在 BP Class Defaults 中配置

**当前状态**：
- 使用 `AM_ComboAttack`（Game Animation Sample 自带的拳击动画），不适合武士刀风格，后续需替换。
- 伤害判定（`DoAttackTrace`）尚未移植。

---

## 五、Blueprint 修改记录

### 5.1 SandboxCharacter_CMC (EventGraph)

1. **IA_Move Triggered** 前插入 Branch：
   - Condition: `Is Wall Jump Input Locked` (C++ 函数)
   - True → 跳过（不执行 AddMovementInput）
   - False → 原逻辑

2. **UpdateRotation_PreCMC** 入口插入 Branch：
   - Condition: `Has Wall Jumped` (C++ 函数，`bWallJumpInputLocked` 的别名)
   - True → 跳过（不执行旋转更新）
   - False → 原逻辑

3. **IA_Jump** 替换为调用 C++ 的 `MultiJump()`（替代原始 `Jump`）。

4. **Class Defaults**：
   - Parent Class → `SandboxCharacterBase`
   - `Combo Attack Action` → `IA_ComboAttack`
   - `Combo Attack Montage` → `AM_ComboAttack`

### 5.2 IMC_Sandbox

- 添加 `IA_ComboAttack` 映射 → Left Mouse Button
- W/S/A/D 的 Modifier 按 §4.1 配置

---

## 六、文件清单

### C++ 核心文件

| 文件 | 职责 |
|---|---|
| `SandboxCharacterBase.h/.cpp` | Wall Jump, Coyote Time, Double Jump, Combo Attack |
| `MyProject4.Build.cs` | 模块依赖（EnhancedInput 等） |

### C++ 来自 Game Animation Sample（未修改）

| 目录 | 内容 |
|---|---|
| `Variant_Combat/` | 完整战斗系统（连击、蓄力、伤害、AI、死亡重生） |
| `Variant_SideScrolling/` | 横版关卡逻辑（摄像机、NPC、可交互物） |
| `Variant_Platforming/` | 平台跳跃逻辑（冲刺） |

### Blueprint 资产（需 Git 管理）

| 文件 | 修改内容 |
|---|---|
| `Content/Blueprints/SandboxCharacter_CMC.uasset` | 父类、EventGraph |
| `Content/Input/IMC_Sandbox.uasset` | 按键映射 |
| `Content/Variant_SideScrolling/Lvl_SideScrolling.umap` | 测试关卡布局 |

---

## 七、待办事项

| 优先级 | 任务 | 状态 |
|---|---|---|
| P0 | Wall Jump 视觉转身速度优化（ABP OffsetRootRotationMode） | 暂缓 |
| P0 | 替换攻击动画为武士刀劈砍（Mixamo/Fab 资源） | 未开始 |
| P1 | LevelBlock_Traversable 侧面 Spline → 侧面抓墙/攀爬 | 未开始 |
| P1 | 伤害判定 DoAttackTrace 移植到 SandboxCharacterBase | 未开始 |
| P2 | 将 IA_Move 蓝图绑定迁移到 C++ SetupPlayerInputComponent | 计划中 |
| P2 | HP/死亡/重生系统 | 未开始 |
| P3 | 格挡机制（按住 Loop Montage） | 未开始 |
| P3 | 手柄支持（新增 IMC 或 Modifier） | 未开始 |

---

## 八、已踩过的坑

| 问题 | 原因 | 解决 |
|---|---|---|
| MSVC PCH 编译失败 (C1083) | 工程路径包含中文字符 | 重命名路径为纯英文 |
| ABP 报错 `cannot find tag 'OffsetRoot'` | 缺少 `AnimationWarping` 插件 | 启用插件 |
| 角色 Y 轴漂移掉出平台 | 3D 移动无平面约束 | CMC 开启 `bConstrainToPlane` |
| LevelBlock_Traversable 附近移动卡顿 | 碰撞体积和其他方块重叠 | 移除重叠方块 |
| Wall Jump 后 A/D 反向 | `SetControlRotation` 翻转了输入参考方向 | 只改 `SetActorRotation`，不动 Controller |
| Wall Jump `SetActorRotation` 无效 | `HasWallJumped()` 函数被删除后蓝图调用失效，旋转从未被跳过 | 恢复函数作为 `bWallJumpInputLocked` 的别名 |
| 攻击 `IA_ComboAttack` 在蓝图中搜不到 | 改了 .h 新增函数但未重启编辑器 | 重启编辑器刷新反射数据 |
