# ADR 23：每屏常驻任务条（Windows 式多显示器）

**日期**：2026-07-27
**状态**：已采纳，实施中
**推翻**：`AGENTS.md` 旧条目「多显示器行为固定为 dwell hover-switch」「不许重新引入多显示器策略菜单」

---

## 背景

改造前全应用只有**一套**面板（`dockPanel` / `capsulePanel` / `drawerPanel` / 弹窗 / 拖拽载体各一个）。所谓「支持多屏」，只是鼠标在某块屏底边停留 0.35 秒后，把这套面板**搬**过去（`PanelCoordinator.commitHoverSwitch`）。同一时刻只有一块屏有任务条。

Owner 接了多台显示器，要 Windows 的行为：每块屏都常驻一条任务条，且每条只显示当前在那块屏上打开的窗口。

## 决策（owner 2026-07-27 逐条拍板）

1. 每块显示器一条常驻任务条。悬停停留切屏整套**删除**。
2. **工具类分区**（暂存架 + 固定文件夹 + 抽屉胶囊）每屏都有，内容全局共享。
3. **应用/窗口类条目**跟着窗口所在的屏走。窗口跨越两屏时归**面积占多数**的那块。
4. **没有窗口的条目只在主屏**：Finder 常驻卡、已退出的保留应用灰图标、未运行的消息应用。主屏 = 菜单栏所在屏 = `NSScreen.screens[0]`。
5. 副屏消息区经常为空，**接受**；空分区自动收掉相邻分隔线（沿用已有规则）。
6. 最小化 / 隐藏的窗口**粘住最后已知的那块屏**，恢复时原地弹回。
7. 卡片顺序**全局一份总表**，各屏从中过滤。不做按屏独立顺序。
8. **跨屏拖卡片永远不支持**，拖离本屏 = 取消弹回。拖拽载体面板保持单屏。
9. 全屏隐藏**每屏独立**：副屏全屏不影响主屏那条。
10. 自动隐藏保持**全局同步**（owner 不使用自动隐藏，按最省事处理）。
11. 抽屉和文件夹/暂存架弹窗**全桌面同时只开一个**，在哪块屏点就在哪块屏弹。
12. 分两期交付，一期必须日常可用。

### 由规则推导、owner 已确认接受的后果

- 把微信窗口拖到副屏，**主屏消息区里那个微信图标会消失**，出现在副屏（规则 3 的直接结果）。
- 副屏平时是 `[暂存架 + 固定文件夹][分隔线][该屏窗口卡片]`——没有消息区，因为它是空的。

---

## 关键技术决策与理由

### 为什么用 `CGDirectDisplayID` 而不是 display UUID

`ScreenID` 取自 `NSScreen.deviceDescription["NSScreenNumber"]`。本方案**没有任何按屏持久化的数据**（顺序是全局一份总表，归属从不落盘），所以身份只需要在进程生命周期内、跨 `didChangeScreenParametersNotification` 保持稳定即可。`CGDisplayCreateUUIDFromDisplayID` 会引入 ColorSync 依赖和 CFUUID 释放纪律，换不来任何好处。

### 为什么把「派生出的屏幕键」塞进 `seatSignature`，而不是原始 bounds

这是整件事的核心修复。`AppTracker.seatSignature` 原本的指纹是 `id:token:标题:最小化:焦点`，**不含位置**。而 `reconcileSeats` 明明已经读到并写入了新 bounds——数据是对的，卡在发布闸门上。后果：把窗口从 A 屏拖到 B 屏这种**纯移动**被判定为「没变化」而永不发布快照，卡片赖在错的屏上。

放**屏幕键**而不是坐标：屏幕键每跨屏才变一次，天然防抖；塞原始坐标会让窗口在同屏内挪一下就每轮重建快照，白白喂给 `intentPipeline.reconcile` + 乐观态对账。

### 为什么刻意**不**注册 `kAXWindowMovedNotification`

拖动时它每秒触发几十次，每次都会走到 `enumerateWindows` → CG 全列表 + 该进程 AX 全量重读，是实打实的风暴，还得再配一个合并器。而它对真正要解决的场景是冗余的：**要拖动一个窗口就必须先点它，它的应用必然是前台**，现有的 0.5 秒前台轮询配上新指纹就能覆盖。

`AGENTS.md` 也把 AX 清单读取限制在 100ms 超时的预算内，移动驱动的重枚举与这条相悖。

最坏延迟：用户拖窗口跨屏 ≤ 0.55s；脚本/窗口管理器挪动**非前台**窗口 ≤ 5.5s（5 秒对账兜底）；插拔显示器立即（拓扑通知强制全量对账）。二期如果实测证明不够，再加 `kAXWindowMovedNotification` + 150ms 合并器，用 `DOCK_SCREEN_MOVE_AX=1` 门控。

### 为什么「过滤放在最后」不是风格偏好

`partitioned()` / `liveOrderIDs` / `liveAppKeys` 保持**全局**，只在 `stripEntries` 装配分区前过滤一次。

理由是在规避一个会造成**持久化数据丢失**的 bug：`StripOrderStore.reorder(draggedID:relativeTo:after:current:)` 内部走 `StripOrdering.reconcile`，第一行就是 `remembered.filter { currentSet.contains($0) }`——**然后把结果写进 UserDefaults**。喂它按屏过滤的列表，第一次拖拽就会把全局顺序表截断成一块屏的，静默且永久。

`sync` 同理：不在 `current` 里的 id 会被打上 `absentSince`，过 5 秒宽限期后从 `liveOrder` 里丢掉，连 `stickyAppKeys` 也一起清。

**决定不给 `sync` 加 owner 门控**：N 个面板算出的参数完全相同，`absentSince` 打戳幂等，`if next != liveOrder` 抑制冗余发布。相比之下「只让主屏那块调」会在主屏拔掉的瞬间让顺序收敛停摆，且没有明显症状。

### 为什么 `ScreenBar` 一个定时器都不装

七个定时器（全屏对账、边缘隐藏、边缘唤醒、弹簧开、弹簧关、弹窗补间，以及已删掉的悬停切屏）全部留在 `PanelCoordinator` 顶层。每屏一个是「N 块屏 = N 个互相竞争的状态机」这类 bug 的最大来源，而它们没一个真的需要按屏。

### 为什么拖拽仲裁归**发起屏**而不是光标所在屏

N 条任务条共享同一个 `DragController`。不加闸的话，光标不在自己身上的那条会算出「已经拖出去了」并把发起屏正在进行的转换**当场回滚**——这不是可能，是必然。既然跨屏拖卡片永不支持（决策 8），把 `activeScreenID` 在 `beginDrag` 时钉死、整段拖拽不变，是比「跟着光标」更简单也更正确的仲裁。

三处容易漏的闸门：`onChange(globalLocation)` 扇出、`onChange(messagingZoneIDs)` 的取消看门狗（副屏消息区为空时条件恒真，会取消主屏发起的拖动）、胶囊/整条的投放高亮（否则 N 条一起发光）。

### 为什么自动隐藏保持全局

Owner 不使用自动隐藏（任务条常驻）。全局 `hideReasons` 里的 `.fullscreen` 现在表示「**所有**已接显示器都在全屏」，只用来给 `EdgeAutoHideRuntimeRules` 的唤醒/隐藏门槛把关；单屏时与改造前逐位一致。

### 顺带修掉的既有缺陷：`NSScreen.main` 不是主屏

`PanelCoordinator.toCGRect` 等四处用 `NSScreen.main?.frame.height` 当 AppKit→Quartz 的翻转基准。`NSScreen.main` 是 **key window 所在的屏**，会跟着前台应用跑。主副屏高度不同时（如 1080 + 1440），全屏检测和最大化避让算出来的矩形整体偏移。已统一走 `ScreenAttribution.quartzRect(fromAppKit:primaryMaxY:)`，基准取 `NSScreen.screens[0].frame.maxY`。

⚠️ 这**改变了**混合分辨率多屏用户的现有行为，需要在 1080+1440 的组合上单独验证全屏隐藏与最大化避让。

---

## 落地结构

| 层 | 文件 | 职责 |
|---|---|---|
| 身份 | `Core/Model/Identifiers.swift` | `ScreenID` |
| 纯逻辑 | `Core/Support/ScreenAttribution.swift` | 坐标翻转、面积多数归属、粘滞 |
| 纯逻辑 | `Core/Support/ScreenSetDiff.swift` | 插拔时的增/删/留计划 |
| 纯逻辑 | `Core/Support/StripScreenRouting.swift` | 条目性质 → 显示在哪块屏 |
| 纯逻辑 | `Core/Support/SingletonPanelPlan.swift` | 抽屉/弹窗的开 / 移 / 关 |
| 纯逻辑 | `Core/Support/FullscreenScreenScan.swift` | 全屏窗口按屏分桶 |
| I/O | `Platform/Screens/ScreenGeometrySource.swift` | `NSScreen` → 值类型拓扑 |
| 数据 | `Platform/AppTracking/AppTracker.swift` | 座位 `screenID`、指纹、拓扑订阅、`[screen]` 诊断 |
| 面板 | `App/Entry/ScreenBar.swift` | 一块屏的那套面板 + 目标矩形 + 宽度 |
| 面板 | `App/Entry/PanelCoordinator.swift` | 多 bar 协调 + 全桌面单例（抽屉/弹窗/拖拽） |
| 视图 | `App/Scenes/DockStripView.swift` | 按屏过滤（**排序之后**）+ 拖拽闸门 |

## `[screen]` 诊断（常驻，正常路径零输出）

沿用 `[tabfold]` / `[tabheal]` 的先例——那两条在 `AGENTS.md` 里被明确要求不许当「诊断遗留」删掉，因为 871305d 那次清理让 2026-07-13 的复发没有任何取证材料。

- **无归属**：窗口有真实 bounds 却与所有屏零重叠。「卡片莫名其妙跑到主屏」的直接原因。
- **粘滞**：本轮算出 B 屏但保留了 A 屏。「卡片卡在错误屏幕」唯一的取证行。
- **拓扑变更**：只在确实有座位引用了已消失的显示器时打印。
- **抖动**：某座位 2 秒内翻转 ≥3 次，说明窗口正好停在接缝上、面积规则在振荡。

## 二期待办

- `partitioned()` 记忆化（现在每次 body 求值跑 6~8 遍，N 屏成倍放大）
- `stripOrderStore.sync` 从视图挪到 `PanelCoordinator` 的快照订阅
- 每块 bar 的 relayout 短路（宽度和目标矩形都没变就跳过）
- `AppTrackerCGWindowSnapshot` 顺便读 `kCGWindowBounds`，给所有应用一份 AX 之外的位置来源

**明确不做**：跨屏拖卡片、按屏独立顺序、按屏独立自动隐藏、归属数据持久化。
