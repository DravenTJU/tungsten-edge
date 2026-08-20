import AppKit
import CoreGraphics
import Foundation

enum UserIntentAction: String, Hashable, Sendable {
    case toggle
    case activate
    case minimize
    case hide
    case close
    case quit
    case newWindow
}

enum UserIntent: Hashable, Sendable {
    case toggle(WindowID)
    case activate(WindowID)
    case minimize(WindowID)
    case hide(WindowID)
    case close(WindowID)
    case quit(WindowID)
    case newWindow(WindowID)

    var windowID: WindowID {
        switch self {
        case let .toggle(id), let .activate(id), let .minimize(id), let .hide(id), let .close(id), let .quit(id), let .newWindow(id):
            return id
        }
    }

    var action: UserIntentAction {
        switch self {
        case .toggle:
            return .toggle
        case .activate:
            return .activate
        case .minimize:
            return .minimize
        case .hide:
            return .hide
        case .close:
            return .close
        case .quit:
            return .quit
        case .newWindow:
            return .newWindow
        }
    }
}

final class LifecycleActionPlanner {
    /// 前台轴检查，默认 = 新建 NSRunningApplication 实例的即时 isActive 读
    ///（SkyLight 切换后立即翻面，Docs/22 §11 POSTACTIVATE 实证；测试注入桩）。
    private let isAppFrontmost: (pid_t) -> Bool
    /// 「这个 App 此刻压在最上面的是哪个窗口」的现读（注入桩；生产实现是一次 CG 层序读）。
    /// 默认 `nil` = 读不出结论 → 完全退回旧的快照 `.active` 口径。
    private let frontmostWindow: (pid_t, Set<CGWindowID>) -> CGWindowID?

    init(
        isAppFrontmost: @escaping (pid_t) -> Bool = {
            NSRunningApplication(processIdentifier: $0)?.isActive == true
        },
        frontmostWindow: @escaping (pid_t, Set<CGWindowID>) -> CGWindowID? = { _, _ in nil }
    ) {
        self.isAppFrontmost = isAppFrontmost
        self.frontmostWindow = frontmostWindow
    }

    func plan(
        intent: UserIntent,
        snapshot: DockSnapshot,
        optimisticStates: [String: OptimisticWindowState] = [:]
    ) -> PlatformActionRequest {
        switch intent {
        case let .toggle(id):
            guard let record = snapshot.windows[id] else {
                return PlatformActionRequest(kind: .activateWindow, windowID: id)
            }
            // 乐观态优先（仅 status 轴）：上一个动作刚发出、快照还没翻面时，按预测态规划，
            // 连点才能严格交替（minimize → activate → …）而不是重复上一个动作。
            let optimistic = optimisticStates[id.rawValue]
            let status = optimistic?.status ?? record.status
            // 前台轴永远即时读，不许被乐观态覆盖（2026-07-05）：乐观 isAppFrontmost=true
            // 在「激活后 4s 内切去别的 App 再点回卡片」时残留不清（快照永远等不到 .active
            // 来兑现它），曾把该激活的点击误规划成 minimize。即时读本来就永远正确。
            let appIsFrontmost = isAppFrontmost(record.pid)
            if record.id.rawValue.hasPrefix("app-") {
                // Finder persistent chip: never hide — always open/focus to match system Dock behavior.
                if record.bundleIdentifier == "com.apple.finder" {
                    return PlatformActionRequest(kind: .activateWindow, windowID: id)
                }
                return PlatformActionRequest(kind: appIsFrontmost ? .hideApp : .activateWindow, windowID: id)
            }
            // 最小化的判定条件是「App 在前台」+「这张卡就是该 App 此刻压在最上面的窗口」。
            // 预测/快照里的 `.minimized` / `.hidden` 先行短路：刚点过最小化的卡再点必须是还原
            //（最小化动画期间窗口还留在 CG 屏上列表里，层序此刻不可信）。
            if appIsFrontmost, status != .minimized, status != .hidden {
                switch isFrontWindowOfApp(record: record, snapshot: snapshot) {
                case .some(true):
                    return PlatformActionRequest(kind: .minimizeWindow, windowID: id)
                case .some(false):
                    return PlatformActionRequest(kind: .activateWindow, windowID: id)
                case .none:
                    // 层序读不出结论 → 退回旧口径（快照 / 乐观态说它活跃就最小化）。
                    return PlatformActionRequest(
                        kind: status == .active ? .minimizeWindow : .activateWindow,
                        windowID: id
                    )
                }
            }
            return PlatformActionRequest(kind: .activateWindow, windowID: id)
        case let .activate(id):
            return PlatformActionRequest(kind: .activateWindow, windowID: id)
        case let .minimize(id):
            return PlatformActionRequest(kind: .minimizeWindow, windowID: id)
        case let .hide(id):
            return PlatformActionRequest(kind: .hideApp, windowID: id)
        case let .close(id):
            return PlatformActionRequest(kind: .closeWindow, windowID: id)
        case let .quit(id):
            return PlatformActionRequest(kind: .quitApp, windowID: id)
        case let .newWindow(id):
            return PlatformActionRequest(kind: .newWindow, windowID: id)
        }
    }

    /// 「这张卡是不是该 App 此刻压在最上面的那个窗口」。`nil` = 读不出结论。
    ///
    /// **为什么不能用快照 / 乐观态的 `.active`**（2026-08-20 实测，owner 报「点窗口 1 → 点窗口 2 →
    /// 再点回窗口 1，它不出来，再点一次才弹出来」）：
    /// - 快照的 `.active` 要求 AX 报出 `kAXFocusedWindow` 且它 `CFEqual` 得上 `AXWindows` 里的元素。
    ///   VS Code 这类 App 从来不满足 → 它的窗口在快照里**永远是 `.inactive`**。
    /// - 于是激活写下的乐观 `.active` **永远等不到兑现**，会挂满整个 4s 超时。4s 内再点同一张卡，
    ///   规划器就把它当成「点了当前活跃窗口」→ 最小化。实测日志：
    ///   `recordStatus=inactive optimisticStatus=active freshActive=true plannedAction=minimizeWindow`。
    /// - 这正是 2026-07-05「预测前台轴残留不清」那条教训的另一半：当年删掉了预测的 `isAppFrontmost`，
    ///   理由是「快照永远等不到 `.active` 来兑现它」——同一句话对预测的 `.active` **状态**同样成立。
    ///
    /// 改用 CG 层叠顺序：它是用户眼睛看到的那件事（谁压在上面），不需要 App 配合报告焦点，对所有
    /// App 一致。最小化 / 别的 Space / 后台标签天然不在屏上列表里，自动判 `false` → 点击 = 抬起来。
    private func isFrontWindowOfApp(record: WindowRecord, snapshot: DockSnapshot) -> Bool? {
        guard let target = record.cgWindowID else { return nil }
        // 候选只取「任务条上真有卡的窗口」，别让 App 那些隐形 layer-0 窗口挡在前面。
        var candidates: Set<CGWindowID> = []
        for sibling in snapshot.windows.values where sibling.pid == record.pid {
            if let cgID = sibling.cgWindowID { candidates.insert(cgID) }
        }
        guard let front = frontmostWindow(record.pid, candidates) else { return nil }
        return front == target
    }
}
