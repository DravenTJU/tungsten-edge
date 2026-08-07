# 每屏常驻任务条 —— 构建、运行与验收

> 配套文档：决策与理由见 [23-per-display-taskbar.md](23-per-display-taskbar.md)（ADR）；工程结构与签名证书详细步骤见 [project-structure.md](project-structure.md)。
>
> 本文是**一期交付的交接清单**：当前进度、怎么跑起来、要验什么、出问题怎么查。

---

## 一、当前状态

一期（每屏一条常驻任务条 + 按屏过滤窗口）代码已完成，分四个检查点提交：

| 提交 | 内容 |
|---|---|
| `5b20942` | 检查点 0：修正 Quartz 坐标翻转基准（主屏而非 `NSScreen.main`） |
| `6f8f07a` | 检查点 1：窗口→显示器归属数据层（界面零变化） |
| `7f1a91e` | 检查点 2：面板层重构为 `ScreenBar`，但仍然只建一条 |
| `48e1236` | 检查点 3：放开每屏一条常驻任务条 |

### 已验证 ✅

- **构建通过**，零 error。仅剩 4 条既有 warning，都在 `WindowZoomDemoController` 相关的 demo 代码里（`DOCK_ZOOM_DEMO` 门控的试验路径），非本次引入。
- **单元测试 381 个全过，0 失败**。其中本次新增三个套件：

  | 套件 | 用例数 | 覆盖 |
  |---|---|---|
  | `ScreenAttributionTests` | 24 | 坐标翻转、面积多数归属 |
  | `ScreenStickinessTests` | 10 | 最小化粘屏、拔屏清理 |
  | `PerDisplayTaskbarTests` | 25 | 屏集合 diff、按屏过滤、单例开合、按屏全屏 |

  原有 322 个一个没坏——特别是 `PanelGeometryTests`（16）与 `TabFoldDecisionTests`（77）这两块最敏感的，说明面板几何契约和标签折叠逻辑没被这次重构碰到。

### 待验证 ⏳

**多屏行为本身全部未经真机验证**——需要接第二块显示器、真实拖动窗口才能验。清单见第三节。

---

## 二、怎么构建和运行

### 前置：本地签名证书（新机器只做一次）

工程的 `CODE_SIGN_IDENTITY` 写死成自签名证书 `macos-dock-cc Local Code Signing`。它跟苹果开发者账号无关，纯本地，唯一目的是**让辅助功能授权粘住**（macOS 按代码签名身份记授权，不按路径；身份固定就不用每次重建后重新勾选）。

建证书**一共三步，缺一步都签不了名**，详细操作见 [project-structure.md](project-structure.md) 的「本地签名证书」小节：

1. 钥匙串访问 → 证书助理 → 创建证书（名称一字不差，类型选「代码签名」，自签名根证书）
2. **设为信任**——否则 `security find-identity -v -p codesigning` 报 `0 valid identities`，实际错误是 `CSSMERR_TP_NOT_TRUSTED`
3. **放开私钥访问控制**——「登录」钥匙串 → 类别选「**密钥**」→ 双击同名私钥 →「访问控制」→「允许所有应用程序访问此项目」。否则 codesign 报 `errSecInternalComponent`

验证：`security find-identity -v -p codesigning` 能列出它。

### 构建 + 运行

**必须在自己的 Terminal.app 里跑**：

```bash
cd /Users/dravenzhao/Code/Draven/tungsten-edge
Scripts/build_and_run.sh run
```

首次运行会要「辅助功能」权限（系统设置 → 隐私与安全性 → 辅助功能）。签名身份固定，**只需授权这一次**。

> ⚠️ **为什么必须在 Terminal.app 里**：私钥操作需要图形登录会话（Aqua session）。在后台会话里——launchd 后台任务、CI、部分 agent/自动化环境，判据是 `launchctl managername` 返回 `Background` 且 `SECURITYSESSIONID` 未设置——无论钥匙串怎么配都会失败，报 `User interaction is not allowed` / `errSecInternalComponent`。这类环境只能用临时签名做编译和跑测试（见下），那条路不碰钥匙串。

### 跑测试

```bash
xcodebuild -project macos-dock-cc-v2.xcodeproj -target macos-dock-cc-v2Tests \
  -configuration Debug CONFIGURATION_BUILD_DIR="$PWD/build/TestProducts" \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Automatic build

xcrun xctest build/TestProducts/macos-dock-cc-v2Tests.xctest
```

**为什么是两步**：`xcodebuild test -scheme macos-dock-cc-v2` 跑不通——工程里有 `macos-dock-cc-v2Tests` 这个 target，但仓库里**没有共享的测试 scheme**，测试 target 没被挂进任何 scheme 的 test 动作。在 Xcode 界面里手动勾过的话，那个勾存在 `xcuserdata` 里，属于个人配置、不进 git，所以别人和 CI 都用不了。

（这里的 `CODE_SIGN_IDENTITY="-"` 是临时签名，跑测试不需要真身份，也不碰钥匙串。）

---

## 三、验收清单

按「最可能出问题」排序，前三项是本次改动的核心风险。

| # | 操作 | 期望 | 风险等级 |
|---|---|---|---|
| 1 | 冷启动 | 每块显示器底部各一条任务条，都带暂存架 + 固定文件夹。**主屏额外**有 Finder 常驻卡、灰色保留应用、未运行的消息应用；副屏没有这些 | 基础 |
| 2 | 在副屏开窗口 → **先点一下让它成为前台** → 拖到主屏 | 卡片在 **0.5 秒内**从副屏消失、在主屏出现 | 🔴 **最高** |
| 3 | 在主屏拖动几张卡片调顺序 → **完全退出 app 再启动** | 顺序还在 | 🔴 **最高** |
| 4 | 副屏全屏播视频 | 只有副屏那条消失，主屏照常 | 中 |
| 5 | 副屏点胶囊开抽屉 → 再去主屏点胶囊 | 副屏那个关闭、主屏弹出（不是开出两个） | 中 |
| 6 | 从任务条拖卡片进抽屉，再从抽屉拖回来 | 转换正常，中途**不会突然弹回原位** | 中 |
| 7 | 把窗口拖到跨越两屏、偏向副屏 | 卡片在副屏（面积多数规则） | 低 |
| 8 | 在副屏最小化一个窗口 | 卡片**留在副屏**；点一下原地弹回 | 低 |
| 9 | 拖一张卡片越过屏幕边缘 | 弹回原位，不跨屏（跨屏拖卡片永不支持） | 低 |
| 10 | 拔掉副屏 | 副屏那条消失；副屏上的窗口卡片迁到主屏；无幽灵卡片 | 低 |
| 11 | 插回副屏 | 任务条恢复；卡片按窗口实际位置重新分布 | 低 |
| 12 | 最大化主屏一个窗口；副屏同样操作 | 两边都把底边抬到该屏任务条上方 | 低 |
| 13 | **拔到只剩一块屏，跑一遍日常操作** | 与改造前完全一样 | 🟡 回归保护 |

### 三项高风险的说明

**第 2 项**是整个方案里唯一预判可能反复出问题的地方。原因：改造前 `AppTracker` 判断"要不要重建快照"的指纹**不含位置**，纯移动窗口会被判为"没变化"而永不刷新。修法是把**派生出的屏幕键**（不是原始坐标）加进指纹，靠已有的 0.5 秒前台轮询兜底——要拖窗口就必须先点它，它必然是前台。所以**测的时候一定要先点一下让窗口成为前台**，否则测的是另一条路径（最长 5 秒才刷新）。

**第 3 项**在验证"多屏过滤没有截断全局顺序表"。`StripOrderStore.reorder` 内部会用传入列表过滤全局顺序表**再写进 UserDefaults**——如果按屏过滤的列表被喂进去，第一次拖拽就会静默且永久地丢掉其他屏的排序。设计上是靠"过滤放在排序之后"从构造上规避的，但这条必须实测确认。

**第 13 项**别忘。95% 的使用场景是单屏，不能为了多屏把单屏搞坏。

---

## 四、出问题怎么查

### `[screen]` 诊断日志

代码里留了四条常驻诊断（Console.app 里搜 `[screen]`），**正常路径零输出**。看到任何一条都说明归属逻辑出了问题：

| 日志 | 含义 |
|---|---|
| `[screen] 无归属` | 窗口有真实坐标却与所有屏零重叠。这是"卡片莫名其妙跑到主屏"的直接原因 |
| `[screen] 粘滞` | 本轮算出 B 屏但保留了 A 屏。这是"卡片卡在错误屏幕"唯一的取证行 |
| `[screen] 拓扑变更` | 插拔时确实有座位引用了已消失的显示器 |
| `[screen] 抖动` | 某座位 2 秒内翻转 ≥3 次，说明窗口正好停在接缝上、面积规则在振荡 |

同类的还有既有的 `[tabfold]`（标签折叠分裂点）和 `[tabheal]`（幽灵座位自愈）。这三组都是**永久保留**的异常路径取证，不要当"诊断遗留"清掉——`AGENTS.md` 有对应条目。

### 回退

**本次改动没有环境变量开关**（不像 `DOCK_SEED_AX_TIMEOUT_MS` / `DOCK_SKYLIGHT_FOCUS`）。要回到"一条栏跟着鼠标走"的旧行为，检出检查点 2 即可——那个提交的行为与改造前逐位一致：

```bash
git checkout 7f1a91e
```

检查点 0 和 1 是纯修复与纯数据层（界面零变化），一般不需要回退。

---

## 五、二期待办

见 [23-per-display-taskbar.md](23-per-display-taskbar.md) 末节。要点：

- `partitioned()` 记忆化（现在每次 body 求值跑 6~8 遍，多屏成倍放大）
- `stripOrderStore.sync` 从视图挪到 `PanelCoordinator` 的快照订阅
- 每块 bar 的 relayout 短路（宽度和目标矩形都没变就跳过）
- 仅在实测证明 0.5 秒轮询不够时：`kAXWindowMovedNotification` + 150ms 合并器，`DOCK_SCREEN_MOVE_AX=1` 门控

**明确不做**：跨屏拖卡片、按屏独立顺序、按屏独立自动隐藏、归属数据持久化。

### 顺带记录的两个工程债

1. **`build_and_run.sh` 的兜底形同虚设**：`sign_app()` 里写了"找不到证书就打警告继续"，但那段永远走不到——工程的 `CODE_SIGN_IDENTITY` 会让 `xcodebuild` 先一步失败，`set -e` 直接退出。在没证书的机器上，脚本会带着一句没头没尾的报错死掉。
2. **没有共享测试 scheme**：导致 `xcodebuild test` 用不了（见第二节）。修法是往仓库加一个 `xcshareddata/xcschemes/` 下的 scheme 文件；owner 2026-07-28 决定暂不加，只改文档。
