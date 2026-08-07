# 项目结构介绍

> 面向新加入的开发者 / fork 后的快速上手文档。产品定位、功能演示见根目录 [README.zh-CN.md](../README.zh-CN.md)；工程硬约束（禁止回退的设计决策）见 [AGENTS.md](../AGENTS.md)。

## 这是什么项目

**Tungsten Edge 钨极** 是一个 macOS 底部任务条应用，用来替代系统 Dock。核心特点是**窗口级**：多窗口应用的每个窗口单独占一张卡片（chip），点击直接切换；单窗口应用压缩成图标。另外还有消息应用常驻区、应用抽屉、固定文件夹区和文件暂存架（shelf）。

- 语言 / 框架：Swift，SwiftUI 视图 + AppKit 面板（`NSPanel`）混合。
- 最低系统版本：**macOS 12 (Monterey)**，新 API 必须带可用性检查和回退。
- 无第三方依赖，一个 Xcode 工程 `macos-dock-cc-v2.xcodeproj`，两个可执行目标：主应用 `macos-dock-cc-v2` 和调试 CLI `window-lab`。
- 依赖系统能力：Accessibility (AX) API 读窗口、CoreGraphics 窗口列表、私有 SkyLight 聚焦调用、AppleEvents 读 Finder 窗口内容。首次运行需授予辅助功能权限。

## 目录总览

```
tungsten-edge/
├── App/            应用层：入口、面板管理、SwiftUI 视图、状态 Store 与交互控制器
│   ├── Entry/        @main 入口、AppDelegate、面板协调（PanelCoordinator）、状态栏菜单
│   ├── Composition/  组合根 AppRuntime + 各类 Store、拖拽控制器、菜单构建
│   └── Scenes/       SwiftUI 视图（任务条、抽屉、文件夹弹窗、chip 等）
├── Core/           纯逻辑层：数据模型、身份/生命周期/放置引擎、可单测的决策函数
├── Platform/       平台边界层：AX / CG / Finder / 权限 等系统 API 封装
├── UI/             读模型（快照 → 视图渲染用的 StripItem）
├── Tools/          WindowLab 调试 CLI 及回放场景
├── Tests/          单元测试（XCTest）
├── Scripts/        构建 / 打包脚本
├── Docs/           工程文档（本文件所在；历史资料在 Docs/Archive/）
├── Resources/      Info.plist
└── assets/         README 用的图标和演示 GIF
```

数据大方向是单向流：**Platform 观察系统窗口 → AppTracker 产出快照 → AppRuntime 发布 → SwiftUI 渲染**；用户操作则走 **视图 → IntentPipeline 规划 → PlatformActionExecutor 执行系统调用**。

## App/ — 应用层

### App/Entry/ — 入口与窗口面板

| 文件 | 职责 |
| --- | --- |
| `MacOSDockCCV2App.swift` | `@main` SwiftUI 入口，只挂 `AppDelegate`，无常规窗口 |
| `AppDelegate.swift` | 应用生命周期，启动组合根 |
| `PanelCoordinator.swift` | **所有浮动面板的总管**：任务条主面板、抽屉面板、文件夹/暂存架弹窗（三者共用一个弹窗面板）、边缘自动隐藏、多屏跟随、全屏检测隐藏。弹窗生命周期（淡入淡出、点外部关闭）也在这里 |
| `NonConstrainingPanel.swift` | 自定义 `NSPanel` 子类，摆放类面板都用它 |
| `StatusMenuController.swift` | 菜单栏状态图标及设置菜单（登录启动、唤醒延迟、系统 Dock 设置等） |

### App/Composition/ — 组合根与状态 Store

这是文件最多的目录，分几类看：

**组合根**
- `AppComposition.swift` — 定义 `AppRuntime`（`ObservableObject`）：持有 `AppTracker`、`IntentPipeline`、`PlatformActionExecutor`、`PermissionService`，订阅 tracker 快照并发布给 UI；维护乐观状态 overlay 和「启动中」应用集合。

**持久化 Store（大多按 bundleID 记录）**
- `DrawerStore.swift` / `DrawerOrderStore.swift` — 抽屉成员与抽屉内排序。抽屉成员身份 = 「在程序坞中保留」。
- `KeptAppStore.swift` — 保留应用（退出后仍显示灰色占位图标）。Finder 永远不允许进入。
- `MessagingAppStore.swift` — 消息应用（微信、飞书等）常驻区成员及顺序，含自动注册与用户退出记忆。
- `StripOrderStore.swift` — 任务条卡片顺序持久化，含应用退出后的位置保留（5 秒宽限 + 占位符）、机器重启后丢弃顺序。
- `PinnedFolderStore.swift` / `PinnedFolderCoverStore.swift` — 固定文件夹及其封面缩略图（后台枚举 + 代次校验防旧图覆盖）。
- `ShelfStore.swift` — 暂存架，只存文件引用，最新在前。
- `AppSettingsStore.swift` — 应用设置。
- `RunningApplicationStore.swift` — 运行中进程状态（抽屉亮/灰、白点）的唯一来源。
- `BadgeStore.swift` — 镜像系统 Dock 的未读角标。

**交互控制器**
- `DragController.swift` / `DragCarrierView.swift` — **本地拖拽的唯一权威**：不用系统 `.onDrag`/`NSItemProvider`，自己管鼠标监听、浮动载体面板、坐标换算、跨面板转换（strip↔抽屉↔消息区，见 `CrossPanelConversion` 枚举）与回滚。
- `AppMembershipController.swift` — 保留/抽屉/消息三种成员身份的统一路由，`removeFromDock` 是唯一的退出出口。
- `IntentPipeline/IntentPipeline.swift` — 用户点击/菜单动作 → 调 `LifecycleActionPlanner` 规划 → 执行，并管理动作反馈状态。
- `FileItemMenuBuilder.swift` — 文件夹弹窗内文件格子的右键菜单（手工 AppKit 菜单）。
- `FileMover.swift` — 外部文件拖入固定文件夹时的移动/复制策略（同卷移动、跨卷经临时项复制、绝不覆盖）。
- `PanelGeometry.swift` / `PanelVisibilityState.swift` — 面板几何计算与显隐状态。
- `WindowZoomDemoController.swift` / `WindowZoomAvoidanceController.swift` — 「最大化窗口避开任务条」：lift 模式是正式功能（任务条常驻时轮询前台窗口，检测到铺满 visibleFrame 就用 AX 把底边抬到任务条上方），纯几何逻辑在 `Core/Support/WindowZoomAvoidance.swift`；slide（任务条滑走）和 Option+绿点两条试验路径分别由 `DOCK_ZOOM_DEMO`、`DOCK_ZOOM_AVOIDANCE=1` 环境变量门控。
- `LaunchAtLoginService.swift` / `NativeDockPreferencesService.swift` — 登录启动、读写系统 Dock 偏好。

**遗留（未被主应用实例化）**
- `ObservationPipeline/` — 旧的窗口观察管线（`ObservationPipeline`、`ObservationAdmissionGate`、`PendingCloseTracker`）。已被 `AppTracker` 取代，只剩 WindowLab 和旧测试在用，等待移除。

### App/Scenes/ — SwiftUI 视图

| 文件 | 内容 |
| --- | --- |
| `ContentView.swift` | 任务条根视图 |
| `DockStripView.swift` | 任务条主体：`[消息区][分隔线][暂存架+固定文件夹区][分隔线][活动窗口区]` 布局、快照→chip 投影、保留应用占位注入、拖拽排序 |
| `DrawerView.swift` | 应用抽屉：上区运行中 / 下区未运行，按进程状态分区 |
| `LauncherChip.swift` | 应用级图标 chip（抽屉图标、消息应用、保留应用占位共用） |
| `PinnedFolderChip.swift` / `ShelfChip.swift` | 固定文件夹 chip、暂存架 chip |
| `FolderGridPopupView.swift` / `ShelfGridPopupView.swift` | 仿原生 Stacks 的网格弹窗（含钻入子目录、排序） |
| `AppMenuFragments.swift` | 手工构建的 AppKit 右键菜单（不用 SwiftUI `.contextMenu`），含 `MenuHostNSView` |
| `PermissionOnboardingView.swift` | 辅助功能权限引导 |

## Core/ — 纯逻辑层

不碰系统 API 的模型与决策逻辑，大部分有单元测试覆盖。

- `Model/` — 基础数据类型：`WindowModels.swift`（窗口记录、快照）、`Identifiers.swift`、`Decisions.swift`、`SystemBoundaryModels.swift`（平台层输入的抽象）、`WindowFrameMatchPolicy.swift`（窗口框架匹配容差）等。
- `State/DockState.swift` — dock 状态聚合。
- `Placement/PlacementEngine.swift` — 卡片占位（seat）放置规则：最小化/隐藏/暂时消失不释放位置，只有真正关闭才释放。
- `Support/` — **可独立单测的纯决策函数**，这是本项目的重要模式（逻辑先提纯、视图只渲染）：
  - `DragConversionPlan.swift` — 抽屉拖出时走哪种模式（拒绝/回消息区/落回任务条/保位置）。
  - `StripDropRouting.swift` — 外部文件拖到任务条落在哪（暂存/入文件夹/固定/拒绝）。
  - `LauncherMenuPlan.swift` — 应用图标右键菜单显示哪些项的纯决策。
  - `FolderDropPlan.swift` / `FolderChipDropZone.swift` / `FolderInteraction.swift` / `FolderContentsLoader.swift` — 文件夹相关决策与加载。
  - `FinderAppleEventMatcher.swift` — Finder AppleEvents 结果按标题+框架匹配窗口。
  - `DirectoryWatcher.swift` — kqueue/dispatch source 目录监视。
  - `StripOrdering`（在 `StripOrderStore` 相关）— 顺序 reconcile 纯函数。
- `Identity/`、`Lifecycle/` — `WindowIdentityEngine`、`LifecycleTransitionEngine` 等属于旧管线（主应用不再实例化），但 `Lifecycle/ActionPlanning/LifecycleActionPlanner.swift` **仍在用**：它是 `IntentPipeline` 的动作规划器（点击卡片时决定激活/最小化/恢复及焦点行为）。

## Platform/ — 系统边界层

所有直接调系统 API 的代码都收在这里。

- `AppTracking/` — **当前窗口清单的唯一权威**：
  - `AppTracker.swift` — 从 `NSWorkspace` 常规应用播种，逐应用读 `AXWindows`（带 100ms 超时），维护 seat 状态与快照 `rebuildSnapshot()`；启动后 0.5/1/2/4s 四轮补扫慢应用。
  - `AppWindowObserver.swift` — 每应用 AX 通知观察。
  - `CGWindowSnapshot.swift` — CG 窗口全列表快照；CG 信号只能证明/保留/否决 seat，**绝不创建** seat。
  - `TabFoldDecision.swift` — 原生标签折叠决策（单 seat 模型：一个物理窗口 = 一张卡片），四级判定 + 影子标签池 + 幽灵座位自愈（`PhantomSeatDecision`），有完整单测。这是本项目最精细的逻辑之一，改动前务必读 AGENTS.md 对应条目。
- `Accessibility/` — `AXWindowReader`（AX 窗口属性读取）、`AccessibilitySource`、`AXWindowMatchPolicy`、`DockBadgeReader`（读系统 Dock 角标）。
- `CoreGraphics/` — `CoreGraphicsSource`、`DockWindowEligibilityPolicy`（过滤系统内部窗口/widget/透明假窗口）。
- `Finder/` — Finder 特殊处理：`FinderSource`、`FinderWindowContentsReader`（AppleEvents/AppleScript I/O 层）、`FinderWindowRules`。Finder 永远保有常驻卡片。
- `Permissions/PermissionService.swift` — 辅助功能权限检测。

另外，窗口聚焦的核心 `postSkyLightWindowFocus`（私有 SkyLight API 调用）是共享聚焦通道，字节布局是硬约束，有 `DOCK_SKYLIGHT_FOCUS=0` 开关可禁用。

## UI/ — 读模型

- `ReadModel/StripItem.swift` — 快照到视图的投影模型。关键概念：chip 的身份是稳定 token（`groupID = seat token`，形如 `tabgrp-<pid>-s<serial>`），而动作目标是当下活跃的 `actionWindowID`（cgID），两者严格分离。

## Tools/ — WindowLab 调试 CLI

`window-lab` 是独立 CLI 目标，用于离线回放窗口事件序列、调试身份/生命周期决策。`Scenarios/` 下是一批真实采样的 JSON 回放场景（最小化恢复、Chromium 标签组、飞书回退、Finder 标签等）。它仍依赖旧观察管线类型，所以那些类型暂未删除。

## Tests/ — 单元测试

`Tests/Unit/` 下 28 个测试文件（共 381 个用例），覆盖的基本都是 `Core/Support` 的纯决策函数和各 Store：标签折叠、拖拽转换、菜单决策、外部拖放路由、Finder 匹配、消息区排序、保留应用位置、多屏归属等。**项目惯例：行为决策先写成纯函数 + 单测，视图层只做渲染**，新增逻辑请沿用这个模式。

### 怎么跑测试

在 Xcode 界面里跑测试目标即可。

命令行要**分两步**——`xcodebuild test -scheme macos-dock-cc-v2` 跑不通：工程里有 `macos-dock-cc-v2Tests` 这个 target，但仓库里**没有共享的测试 scheme**，测试 target 没被挂进任何 scheme 的 test 动作。（在 Xcode 里手动勾过测试 target 的话，那个勾存在 `xcuserdata` 里，属于个人配置、不进 git，所以别人和 CI 都用不了。）

```bash
# 1. 单独编译测试 bundle 到固定目录
xcodebuild -project macos-dock-cc-v2.xcodeproj -target macos-dock-cc-v2Tests \
  -configuration Debug CONFIGURATION_BUILD_DIR="$PWD/build/TestProducts" build

# 2. 直接执行
xcrun xctest build/TestProducts/macos-dock-cc-v2Tests.xctest
```

没有本地签名证书时（见下节），两条命令都要追加 `CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic`。

## Scripts/ 与构建

- `Scripts/build_and_run.sh` — 构建 + 本地签名 + 运行（`run` / 其他模式），构建日志写到 `/tmp/macos-dock-cc-v2-build.log`。
- `Scripts/package_release.sh` — 打发布包。
- 构建产物在 `build/DerivedData/`。

### 本地签名证书（新机器/重装系统后的第一件事）

工程的 `CODE_SIGN_IDENTITY` **写死**成一个叫 `macos-dock-cc Local Code Signing` 的自签名证书。它跟苹果开发者账号无关，纯本地，存在的唯一目的是**让辅助功能授权粘住**：

macOS 的辅助功能授权是按 app 的**代码签名身份**记的，不是按路径。用固定证书签，每次重新构建身份不变，系统认为还是同一个 app，授权一直有效；用临时签名（`-`）则只能按二进制哈希认，改一行代码重建就要去系统设置里重新勾一遍。

**这个证书不在仓库里，也没法用脚本可靠地建**，换机器必须手动重建一次：

1. 打开「钥匙串访问」→ 菜单「钥匙串访问」→「证书助理」→「创建证书…」
2. **名称**：`macos-dock-cc Local Code Signing`（一字不差——工程文件和 `build_and_run.sh` 都按这个名字找）
3. **身份类型**：自签名根证书
4. **证书类型**：代码签名
5. 「让我覆盖这些默认值」不勾，创建，存进「登录」钥匙串

**建完还有两步，缺一个都签不了名**：

- **信任**：新建的自签名根证书默认不受信任，`security find-identity -v -p codesigning` 会显示 `0 valid identities`，实际报错是 `CSSMERR_TP_NOT_TRUSTED`。在钥匙串访问里双击证书 →「信任」→「代码签名」设为「始终信任」。
- **私钥访问控制**：证书助理建出来的私钥默认是「使用前询问」。在「登录」钥匙串 → 类别选「**密钥**」（不是「我的证书」）→ 双击同名私钥 →「访问控制」→ 选「允许所有应用程序访问此项目」。不改的话 codesign 会报 `errSecInternalComponent`。

验证：`security find-identity -v -p codesigning` 能列出它，且 `codesign --force --sign "macos-dock-cc Local Code Signing" 某个可执行文件` 不报错。

⚠️ **签名构建必须在自己的 Terminal.app 里跑**。私钥操作需要图形登录会话（Aqua session）；在后台会话里（launchd 后台任务、CI、部分 agent/自动化环境，判据是 `launchctl managername` 返回 `Background` 且 `SECURITYSESSIONID` 未设置）无论钥匙串怎么配都会失败，报 `User interaction is not allowed` / `errSecInternalComponent`。这类环境里只能用临时签名（`CODE_SIGN_IDENTITY="-"`）做编译和跑测试——那条路不碰钥匙串，完全可用。

想跨机器复用同一个身份（连辅助功能授权一起省），在钥匙串里右键把它导出成 `.p12` 存好；重新生成的证书是新钥匙、新身份，授权还得再给一次。

⚠️ **已知坑**：`build_and_run.sh` 的 `sign_app()` 里写了「找不到证书就打个警告继续」的兜底，但那段**永远走不到**——工程的 `CODE_SIGN_IDENTITY` 会让 `xcodebuild` 先一步失败，脚本的 `set -e` 直接退出。所以在没证书的机器上，这个脚本会带着一句 `No certificate matching 'macos-dock-cc Local Code Signing' found` 死掉。临时绕过：给 `xcodebuild` 追加 `CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic`（能构建能跑测试，但每次重建都要重新授权辅助功能）。

调试用环境变量开关：`DOCK_SEED_AX_TIMEOUT_MS=0`（关闭播种 AX 超时）、`DOCK_SKYLIGHT_FOCUS=0`（关闭 SkyLight 聚焦）。

## Docs/ — 文档

- `Docs/README.md` — 文档目录说明。
- `05-known-platform-quirks.md` — 仍影响实现的平台怪癖。
- `22-window-focus-flicker-debugging.md` — 聚焦/激活调试史与硬约束。
- `23-per-display-taskbar.md` — 每屏常驻任务条的决策记录（ADR）：owner 拍板的 12 条规则、为什么用 `CGDirectDisplayID`、为什么屏幕键进 `seatSignature` 而不是坐标、为什么刻意不注册 AX 移动通知。
- `24-per-display-taskbar-verification.md` — 同一改动的构建/运行/验收清单：当前进度、签名证书三步、13 项手动验收、`[screen]` 诊断日志速查、回退方式。
- `Archive/` — 历史资料（早期规划、真实窗口采样、工程深挖、发布说明），只作证据参考，不代表现状。

## 新手上路建议

1. 先读 [AGENTS.md](../AGENTS.md) —— 它是「不许回退的工程决策」清单，很多看似可以简化的代码背后都有踩坑史。
2. 顺着数据流读一遍：`AppTracker.start()` → `rebuildSnapshot()` → `AppRuntime.handleSnapshotUpdate` → `DockStripView` 的投影 → chip 点击 → `IntentPipeline`。
3. 改行为逻辑前先找 `Core/Support` 或 `Platform/AppTracking` 里对应的纯决策函数和它的测试。
4. 拖拽相关一律从 `DragController` 入手，不要引入系统拖拽 API。
