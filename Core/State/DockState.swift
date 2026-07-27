import Foundation

/// `Equatable` 是刻意加的（每屏常驻任务条，2026-07-27）：`rebuildSnapshot()` 在应用激活等路径上
/// 是**无条件**发布的，而每次发布都会触发一次全量 fittingSize 重测 + 面板动画。多屏之后这个成本
/// 乘以屏幕数，所以订阅端用 `.removeDuplicates()` 把完全相同的快照掐掉。
struct DockSnapshot: Sendable, Equatable {
    var windows: [WindowID: WindowRecord]
    var orderedWindowIDs: [WindowID]

    static let empty = DockSnapshot(windows: [:], orderedWindowIDs: [])
}

@MainActor
final class DockState {
    private(set) var snapshot: DockSnapshot = .empty

    func commit(_ update: StateUpdate) {
        var next = snapshot
        if let windowRecord = update.windowRecord {
            next.windows[windowRecord.id] = windowRecord
        } else {
            next.windows.removeValue(forKey: update.windowID)
        }
        next.orderedWindowIDs = update.orderedWindowIDs
        snapshot = next
    }
}
