# Guardrail Provenance（从 AGENTS.md 搬出的历史考据）

2026-07-30 从 `AGENTS.md` 移出。搬走的是**历史叙述**——某个机制曾经存在过、后来被谁替换、当时踩过什么坑。**约束本身没有搬走**，仍在 `AGENTS.md` 原位置，那里留了指向本文的指针。

搬出的理由：`AGENTS.md` 每次会话都进上下文，而这些考据只在「有人想恢复某个旧机制」或「同类问题复发」时才需要读。它当时已经涨到 57K 字符，比整个 Obsidian 主笔记还多一倍半。

---

## 1. Long-gap duplicate prevention 为什么不是现状

对应护栏：Taskbar Trust And Placement 一节里「座位连续性」那条。

- 这个机制**已经不在代码里**，不要把它当成现有行为引用。
- 标题 + 邻近 frame 的重新认回，随 `WindowIdentityEngine.snapshotSeatResolution` 一起退休了。注意别和 `:531` 混淆——那是另一套机制（TTL 限定的近期清单绑定），不是同一回事。
- 在 `AppTracker` 里，标题和邻近 frame 这两个信号**不参与座位身份判定**；它们只被写进 `seatCreated.existingSeats`，而且只在 InventoryLog 打开时才写。日志默认关闭，所以要复现这类问题，必须**先**把日志打开再复现，事后补开没用。
- 这条不覆盖动作句柄捕获：`AXWindowMatchPolicy` 仍然按标题 + 邻近 frame 匹配。
- `21-long-gap-duplicate-card-fix.md` 记录的是**旧身份引擎时代**的真实重复卡事故。现役的 `AppTracker` 也产生过重复卡（dead-PID 误判，见 `AGENTS.md` 里 `ProcessLiveness` 那条），但**至今没有任何一例**被归因于「缺少标题 + 邻近 frame 合并」。
- 所以要恢复合并，得先有 owner 决策；而且必须权衡「两个互相重叠的独立窗口本来就该各占一个座位」——**合并错了会丢卡片，比多出一张更糟**。

## 2. 两个失效的旧回滚开关

对应护栏：Taskbar Trust And Placement 一节里 kill switch 那条。

`DOCK_INVENTORY_FIRST_ENABLED` / `DOCK_AX_ADMISSION_MODE` 早已失效。它们唯一的读者是那个从不被实例化的 legacy admission gate，所以设了也不会有任何效果——不要再对外承诺这两个开关，也不要依赖它们排障。

## 3. 窗口清单管线的替换史

对应护栏：`AppTracker` 是唯一窗口清单权威那条。

旧的 `WorkspaceSource` / observation-pipeline 清单路径，于 `ef50008`（2026-05-31）被 `AppTracker + AppWindowObserver` 取代，`WorkspaceSource` 已删除。

剩下的旧管线类型——`ObservationPipeline`、`WindowIdentityEngine`、`LifecycleTransitionEngine`、`ObservationAdmissionGate`——**不被 app 实例化**，只有 WindowLab 和 legacy tests 还在用。彻底移除它们是「方案 A step 2」，尚未做。

## 4. 全局热键回调为什么不许干别的

对应护栏：Settings And Compatibility 一节里 Global hot key rules 那条。

事实链如下，**根因未经证实**，仅作线索保留：

- `417d93d` 加了一个 SwiftUI 局部的 ⌘⇧D + `SIGUSR2` 调试快照触发器
- `ef50008` 在那次大管线重写里把它删掉了，提交信息只字未提
- `1ed0e66` 事后补文档说「间歇主线程卡死已回退」

因此护栏定成：热键回调**只能切设置**，不得导出调试快照、不得同步读取跨应用的 AX/CG 清单。这是基于上述现象的保守约束，不是已证实的因果结论。
