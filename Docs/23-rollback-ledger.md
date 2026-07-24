# 23 · 回滚账本（Rollback Ledger）

> 这是**可执行的回滚账本**：目标 → 具体 `git revert` / `git merge` 命令 → 当前验证状态。
> 视觉版是 owner Obsidian 库 `00 当前进度.md` 的「检查点地图」——图上标签（`↩ 单点` / `⇤ 整组` / `⚠ 人工` 等）是快速视觉状态，这张表才是执行依据；两者只需结论方向一致，不必逐字对应。
> 打检查点、或某个提交的可回滚性发生变化（新冲突、组合并）时，随检查点地图一起更新本表。

以下结论以 **2026-07-18 的 `a25add5`**（`finder-folder-preview` 最新功能检查点：消息应用纳入统一保留勾选模型）为起点；其下的三键数据边界见下方专节，更早的抽屉位置 / 保留拆分数据边界仍适用于 `5f5efa0`。旧提交即使产品上是独立能力，也可能因为后来改过同一文件而无法直接 `git revert`；“人工”表示要解决冲突并重新验证，不表示功能不能移除。

## 当前本地主线（master）

以官方 `v0.6.5@9b4b5d0` 为起点的稳定重建线已于 2026-07-24 提升为本地 `master`，当前 worktree 为 `/Users/caye/Projects/macos-dock-cc-v2-v065-stable`。`codex/v065-stable-rebuild@3fb0df4` 冻结保留为 4.1 提升前检查点；旧本地 `master@d83b433` 保存在 `archive/master-before-stable-rebuild-20260724`；旧脏开发线 `codex/release-v0.6.6@5082100` 及其 worktree 原样保留。

远端 `origin/master@121724d` 未修改，也不是本地 `master` 的 upstream；它相对当前稳定线保留 3 个远端独有的旧发布提交。本地 4.4 及后续稳定重建只从 `master` 推进，不得误从旧开发线或远端 master 接续。

安装回退：若需恢复上一稳定安装版 4.2，使用备份 `/Users/caye/Projects/tungsten-edge-rebuild-artifacts/2026-07-24-stage4/4.3-quit-last/rollback/Tungsten Edge.app`；若需恢复 4.1，使用备份 `/Users/caye/Projects/tungsten-edge-rebuild-artifacts/2026-07-24-stage4/4.2-open-gray/rollback/Tungsten Edge.app`；若需恢复到 v0.6.5 原始安装，使用官方备份 `/Users/caye/Projects/tungsten-edge-rebuild-artifacts/2026-07-23-stage4/4.1-f2-first-frame-position/rollback/official-v065-20260723-221811/Tungsten Edge.app`（executable 名均为 `macos-dock-cc-v2`）。

- 当前稳定安装版（4.3）hash: `ed98039e4139d2e50ff3f4e7cf6938d5ad2ef1586fb5b82e5494a76bedd4a5ca`
- 上一稳定安装版（4.2）备份 hash: `6defba5dcb6313ede6961e5e591061fb48850def0005478bcde1bbd95ce93986`
- 4.1 备份 hash: `0b92d6d2f90fb3602bbc010987760971df89444cb7c459cf1f4a0f37c5756334`
- 官方 v0.6.5 备份 hash: `a9da38bf2f98f7ebe432d83e5cb9ac798d58297bc93b1422b03a69053e3ebb3f`

## 数据边界：抽屉位置与退出后保留拆分

- 代码回滚命令为 `git revert 5f5efa0`；这不会自动回滚 `UserDefaults` 数据。
- 抽屉键由新旧两个版本共享；新版本新增的 `keptAppBundleIDsV2` 被旧版本忽略。旧 `keptAppBundleIDs` 保持升级前内容，不由迁移覆写。
- 回滚并启动旧版后，旧版会按升级前的旧保留名单继续执行原有“kept 胜出”启动修复，可能把与旧保留名单重叠的部分应用踢出抽屉。这个局部抽屉位置变化是已接受的回滚结果。

## 数据边界：消息应用纳入统一保留勾选（a25add5）

- 代码回滚命令 `git revert a25add5`；不自动回滚 `UserDefaults`。
- 三组键各升一版、旧键冻结只读：新增 `keptAppBundleIDsV3` / `messagingBundleIDsV2` / `messagingOptOutBundleIDsV2`；冻结 `keptAppBundleIDsV2`、`keptAppBundleIDs`、`pinnedAppBundleIDs`、`messagingBundleIDs`、`messagingOptOutBundleIDs`（新版一律不删不覆写）。
- 迁移把现有 kept 名单 + 消息名单并入 V3（消息应用默认勾保留，升级观感不变）。实测：升级后 `keptAppBundleIDsV3` = 原 24 个 kept + 微信 / QQ / 飞书，`keptAppBundleIDsV2` 冻结不变。
- 回滚到 `a25add5` 之前的版本：旧版只读冻结旧键（升级前快照），新版对消息应用的 kept / 标记 / 取消一律不带回；旧版启动修复遍历的是 kept V2（不含本次迁入的消息 kept，那些只在 V3），因此**不会误取消消息标记**。回滚干净。
- `drawerBundleIDs` 仍两版共享：新版用户主动拖动改的位置会被旧版读到，属既有位置数据、不宣称回滚。

| 目标 | 建议逆序 | 会保留什么 | 当前实证 |
| --- | --- | --- | --- |
| **撤销稳定重建的「退出 App」菜单末项修复** | `git revert 3bd1fef` | 保留未启动应用「打开」、消息区退出态灰显及此前全部功能；恢复部分运行态 chip 菜单把成员项排在退出之后的旧顺序 | **↩ 单点，无数据边界，已验证 revert**：从旧实现 `5535657` 恢复纯菜单排序改动与 AGENTS 护栏；`LauncherMenuPlan`、app-level fallback 和具体窗口菜单统一为动作项 → 成员项 → 退出，分隔线由退出分支自补；定向测试 6/6、Debug 全量测试 442/442、主 App Debug/Release + Window Lab Debug 三项构建通过；owner 于 2026-07-24 实机验收通过；临时 detached worktree `git revert --no-commit` 无冲突，回退后 5 个文件与父提交 `aedfb37` 完全一致。安装回退见上方当前本地主线节 |
| **撤销稳定重建的未启动应用「打开」+ 消息区退出态灰显** | `git revert d226e80` | 保留启停首帧影子滑动修复及此前全部功能；恢复未启动图标右键无「打开」、消息区退出态常亮的旧观感 | **↩ 单点，无数据边界，已验证 revert**：从旧实现 `a18c8aa` 恢复纯 UI / 菜单层改动，新增纯 `LauncherMenuPlan.open` + `LauncherChipVisualPlan`（均有单测），并收窄 `dimsWhenHidden` 与启动动作分流；定向测试 9/9、Debug 全量测试 441/441、主 App Debug/Release + Window Lab Debug 三项构建通过；owner 于 2026-07-24 实机验收通过；临时 detached worktree `git revert --no-commit` 无冲突，回退后 7 个文件与父提交 `5be8013` 完全一致。安装回退见上方当前本地主线节 |
| **撤销稳定重建的启停/重开首帧影子滑动修复** | `git revert 8af961c` | 恢复到 v0.6.5 稳定基线的排序行为，其余功能不变 | **↩ 单点，已验证 revert**：从 `0b74fa6`（原 `0a70130`）恢复 absent rank-anchor；功能 + AGENTS 护栏 + 测试同一提交；定向测试 23/23、Debug 全量测试 437/437、主 App Debug/Release + Window Lab Debug 三项构建通过；owner 于 2026-07-23 实机验收通过；临时 detached worktree `git revert --no-commit` 无冲突，回退后四文件与 `v0.6.5@9b4b5d0` 完全一致。安装回退见上方稳定重建基线节 |
| **撤销消息应用纳入统一保留勾选** | `git revert a25add5` | 抽屉图标反馈、抽屉/保留拆分及此前全部功能；恢复消息应用永久身份、消息与 kept 互斥、消息只显示取消标记的旧语义 | **↩ 单点，带三键数据边界**：功能 + 纯投影 + 纯菜单投影 + 迁移 + 测试 + AGENTS 护栏同一提交；431 项单元测试、macOS 12 通用构建（arm64 + x86_64）、`git diff --check`、owner 真机验收（消息应用保留勾选、取消勾选后退出消失、迁移观感不变）通过；未单独验证 revert |
| **撤销抽屉图标悬停/点击反馈与九宫格缩小** | `git revert 8e2b851` | 抽屉位置与保留状态拆分及此前全部功能 | **↩ 单点**：独立视觉优化提交；仅 `DrawerCapsuleButton` 内层九宫格 scaleEffect 反馈（悬停 1.07 / 点击 0.93 回弹）+ 网格常量（icon 9 / 间距 4 / 圆角 iconSize÷4），macOS 12 Debug 通用构建与 owner 实机验收通过，未单独验证 revert |
| **撤销抽屉位置与程序坞保留状态拆分** | `git revert 5f5efa0` | 精简状态栏菜单与此前全部功能；恢复抽屉成员即保留成员、动态“在程序坞中保留 / 从程序坞中移除”菜单和拖拽时同步改 kept 的旧语义 | **↩ 单点，带上述数据边界**：功能、纯投影与排序决策、迁移、测试、工程护栏同一提交；413 项单元测试、macOS 12 Debug 通用构建（arm64 + x86_64）与 `git diff --check` 通过。新产物已启动，原生菜单与迁移行为仍待 owner 完整实测验收；未单独验证 revert |
| **撤销精简状态栏菜单** | `git revert 841fe45` | 自动隐藏快捷键与此前全部功能；状态菜单恢复系统 Dock 延迟滑杆、两组自动隐藏勾选和“添加固定文件夹…”入口 | **↩ 单点**：菜单结构、系统 Dock 显隐写入、测试、README 与工程护栏同一提交；406 项单元测试、macOS 12 Release 通用构建（arm64 + x86_64）、Debug 启动、`git diff --check` 与 owner 真机验收通过。系统 Dock 动态命令只写 `autohide`、保留原 `autohide-delay`。未单独验证 revert |
| **撤销菜单栏自动隐藏开关与钨极快捷键** | `git revert 36c23c0` | 贴底边热区外闪烁修复与此前全部功能 | **↩ 单点**：功能、可靠性修复、测试、README 与 shared scheme 同一提交；408 项单元测试、macOS 12 Release 通用构建（arm64 + x86_64）、Debug 启动验证通过。owner 实测菜单关闭时 ⌥⌘E / ⌥⌘D 均有效；菜单展开时 ⌥⌘E 无效为已接受边界、直接点击菜单项，系统 ⌥⌘D 仍有效。未单独验证 revert |
| **撤销贴底边热区外闪烁修复** | `git revert 3b3c9a4` | 最大化避让全功能与此前全部功能 | **↩ 单点**：纯规则 + 调用点 + 单元测试的自包含提交；372 项单元测试、Debug 构建、`git worktree` 建改前基线做实机对照复现（外接屏底边角落停留 23 秒：改前 69 行日志 64 次唤醒/隐藏交替，改后同操作零次）、999 不唤醒模式复测通过，未单独验证 revert |
| **撤销避让响应节奏调优**（回到 1.5s/6s 保守节奏） | `git revert c9cb5a4` | 最大化避让全功能与此前全部功能 | **↩ 单点**：纯常量/确认逻辑调优；371 项单元测试、Debug 构建、双屏实测（首抬 ~0.6s、放弃态自愈 ~1.4s）通过，未单独验证 revert |
| **撤销整个最大化窗口避让** | `git revert 8c60676 c9cb5a4`（连同节奏调优一起） | 回滚账本、文档入口与此前全部功能 | **↩ 单点**：功能自包含（3 新文件 + AXWindowReader 写机器 + PanelCoordinator accessor + AppDelegate 装配 + AGENTS 护栏段）；371 项单元测试、macOS 12 Debug/Release 构建、双屏（Retina 内建 + 1x 外接）连续缩放实测通过，未单独验证 revert。旧对照试验仍封存在 `experiment/avoid-scale-hover @ 4b58365` |
| **撤销文档入口与回滚账本** | `git revert d2247a1` | 全部产品功能 | **↩ 单点**：纯文档提交（Obsidian 首页指向 + 本账本文件），未单独验证 revert |
| **撤销窗口身份持久诊断日志** | `git revert 489f5d5` | 现有折叠四级判断、影子池、幽灵自愈五道门槛和此前全部功能 | **↩ 单点**：纯观测检查点，不改变窗口行为；333 项单元测试、Debug / Release 构建、LaunchServices `/dev/null` 启动和三实例并发写入验证通过，未单独验证 revert |
| **撤销窗口标题悬停提示** | `git revert 3d1c280` | 菜单栏手动检查更新和此前全部功能 | **↩ 单点**：独立功能提交；314 项单元测试、macOS 12 Debug 构建、Tooltip 单行/两行渲染和 owner 实机验收通过，未单独验证 revert |
| **撤销菜单栏手动检查更新** | `git revert 1aced10` | 影子标签池、幽灵座位自愈和此前全部功能 | **↩ 单点**：独立功能提交；305 项单元测试、Debug 构建与 owner 实机验收通过，未单独验证 revert |
| **撤销影子标签池 + 幽灵座位自愈** | `git revert 2a00e2d` | 权限引导窗口和全部功能 | **↩ 单点**：独立修复提交；含影子标签池和幽灵座位自愈单元测试，未单独验证 revert |
| **恢复避让试验到主线**（找回，不是撤销） | `git merge experiment/avoid-scale-hover` 或挑单个提交 `git cherry-pick 229a6a5 6ca3992 4b58365` | 主线当前全部功能 + 避让试验代码 | **⚠ 人工（已基本失去意义）**：`8c60676` 已把避让正式版带上主线（AX 写机器即取自 `229a6a5`），再合旧试验会在 `AXWindowReader`/`AppDelegate`/工程文件冲突；分支仅作历史参考保留 |
| **撤销权限引导窗 + 本地重签** | `git revert 9f10a14` | 全部主链功能（避让试验已经不在主线上，不受影响） | **↩ 单点**：工程支撑与发布提交；未单独验证 revert |
| **撤销固定文件夹 chip 悬停放大反馈** | `git revert 7d1c8d0` | 外部文件移入文件夹和全部功能 | **↩ 单点**：独立视觉优化提交；纯 scaleEffect 叠加，未单独验证 revert |
| **撤销外部文件移入文件夹** | `git revert 22d22a0` | 固定文件夹 chip 悬停放大反馈、消息身份常驻、移除门控、弹窗落头和全部可靠性优化 | **↩ 单点**：独立功能提交；283 项单元测试、Debug 构建通过 |
| **撤销低风险代码清理** | `git revert 871305d` | 两项性能优化和全部产品功能 | **↩ 单点**：独立清理提交；254 项测试、Debug 构建和 owner 实机验收通过 |
| **撤销删除 WorkspaceSource** | `git revert 1d4f4ca` | 低风险代码清理和全部产品功能 | **↩ 单点**：独立清理提交；254 项测试、三 target 构建通过 |
| **撤销消息身份常驻与移除门控** | `git revert 279935e` | 删除 WorkspaceSource、低风险代码清理和全部产品功能 | **↩ 单点**：独立提交；264 项测试、Debug 构建通过 |
| **撤销悬停事件驱动改造** | `git revert 6777b6a` | CG 查询优化和全部产品功能 | **↩ 单点**：独立性能提交；254 项测试、Debug 构建和双屏实机行为通过 |
| **撤销单轮 CG 快照复用** | `git revert 4ffd99f` | 全部产品功能和成员语义 | **↩ 单点**：独立性能提交；254 项测试、Debug 构建、WindowLab 与 Ghostty 实测通过 |
| **撤销最新成员语义与消息区双向拖拽** | `git revert e123856` | 固定应用最终行为、`2d97005` 多标签修复、固定区与内容预览 | **↩ 单点**：无冲突；撤销后 214 项测试与 Debug 构建通过 |
| **移除整套固定应用 / 程序坞成员演进（G2）** | `e123856 → da4a39d → 44856eb → f9a3476` | 固定文件夹、内容预览、任务条细节和 `2d97005` 多标签修复 | **⚠ 人工**：首个提交可撤销，继续到 `da4a39d` 出现冲突；不能把这串 hash 当成可直接执行的命令 |
| **移除多标签成员历史折叠** | `2d97005` | 固定应用与最新成员语义 | **⚠ 人工但功能独立**：直接撤销会在工程文件和护栏文档冲突，不并入 G2 |
| **移除 Finder / 固定文件夹内容预览** | `c9fad7d` | 固定文件夹区、中转格和后续程序坞成员能力 | **⚠ 人工**：直接撤销会在拖拽、任务条和工程文件冲突 |
| **移除抽屉 Card Nav 入场动画** | `1821274` | 抽屉功能及后续成员关系 | **⚠ 人工**：直接撤销会在现行抽屉视图冲突 |
| **移除整套固定文件夹能力（G1）** | `c9fad7d → 7c6acb1 → f2f2123 → bf5fb32 → 55894b4 → 48a2415 → b145b1c → 0ae5348 → 3fa4404 → d7ae76e` | 核心任务条、抽屉和程序坞成员能力 | **⚠ 人工**：这是目标顺序，不是已验证命令；后续任务条与拖拽重构会产生冲突 |
| **恢复垃圾桶旧方案** | 不直接 revert；只从 `d7ae76e` 查阅旧实现 | 当前固定文件夹能力不变 | **⛔ 已反转**：`3fa4404` 明确砍除，恢复需要重新评估常驻负担与权限 |

## 相关历史

- 主线撤销避让试验：`9ff1aec → 299748a → 63f7ee8`（07-13）。撤销 `229a6a5` 时与 `4b58365` 冲突：AppDelegate 里只调用两个避让控制器 `stop()` 的收尾方法一并删除，已人工解决。完整试验封存在 `experiment/avoid-scale-hover @ 4b58365`。
- 远端 `origin/master@121724d` 保留旧 v0.5.0 发布合并历史，相对当前本地稳定主线有 3 个远端独有提交；2026-07-24 提升本地 `master` 时未 fetch、未 push、未改 `origin/HEAD`。
