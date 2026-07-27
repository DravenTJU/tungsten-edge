import Foundation

/// 显示器插拔 / 排列变化时，算出「哪些屏要新建任务条、哪些要拆掉、哪些只是换了几何」。
/// 纯函数，可单测（每屏常驻任务条，2026-07-27）。
enum ScreenSetDiff {
    struct Plan: Equatable {
        /// 新接上的屏 → 建一条新的 `ScreenBar`。
        let added: [ScreenID]
        /// 已拔掉的屏 → 拆掉它那条。
        let removed: [ScreenID]
        /// 仍在的屏 → 只换 `NSScreen` 实例（分辨率/排列可能变了），面板不重建。
        let kept: [ScreenID]
    }

    /// `current` 保持系统给的顺序（`screens[0]` = 主屏），`added` / `kept` 沿用它，
    /// 这样调用方排出来的任务条顺序是确定的。
    static func plan(existing: Set<ScreenID>, current: [ScreenID]) -> Plan {
        // 去重：同一块屏理论上不会出现两次，但拓扑读取失败退化出合成 id 时可能撞车。
        var seen = Set<ScreenID>()
        let uniqueCurrent = current.filter { seen.insert($0).inserted }
        let currentSet = Set(uniqueCurrent)

        return Plan(
            added: uniqueCurrent.filter { !existing.contains($0) },
            removed: existing.subtracting(currentSet).sorted { $0.rawValue < $1.rawValue },
            kept: uniqueCurrent.filter { existing.contains($0) }
        )
    }
}
