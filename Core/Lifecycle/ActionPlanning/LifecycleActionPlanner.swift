import AppKit
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
            // 乐观态优先：上一个动作刚发出、快照还没翻面时，按预测态规划，
            // 连点才能严格交替（minimize → activate → …）而不是重复上一个动作。
            let optimistic = optimisticStates[id.rawValue]
            let status = optimistic?.status ?? record.status
            // NSWorkspace.frontmostApplication 是通知驱动缓存，SkyLight 直切前台后可滞后
            // ~1.5s（第二击被误判成"未在前台"→ 重复计划 activate 无观感）。isActive 走
            // 新建实例的即时读，SkyLight 切换后立即翻面（Docs/22 §11 POSTACTIVATE 实证）。
            let appIsFrontmost = optimistic?.isAppFrontmost
                ?? (NSRunningApplication(processIdentifier: record.pid)?.isActive == true)
            if record.id.rawValue.hasPrefix("app-") {
                // Finder persistent chip: never hide — always open/focus to match system Dock behavior.
                if record.bundleIdentifier == "com.apple.finder" {
                    return PlatformActionRequest(kind: .activateWindow, windowID: id)
                }
                return PlatformActionRequest(kind: appIsFrontmost ? .hideApp : .activateWindow, windowID: id)
            }
            if status == .active && appIsFrontmost {
                return PlatformActionRequest(kind: .minimizeWindow, windowID: id)
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
}
