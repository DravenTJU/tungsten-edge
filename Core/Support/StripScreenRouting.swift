import Foundation

/// 任务条上的一个条目该出现在哪块屏（每屏常驻任务条，owner 2026-07-27）。
///
/// 规则按**条目性质**分两类：
/// - **工具类**（暂存架、固定文件夹、抽屉胶囊、分隔线）：每块屏都渲染，内容全局共享。
///   它们不属于任何窗口，压根不进这里。
/// - **应用类**（窗口卡、消息应用 chip、保留应用占位、Finder 常驻卡）：跟着窗口所在的屏走；
///   **没有窗口的一律只在主屏**。
///
/// ⚠️ 这个过滤必须发生在**排序之后**。顺序层（`StripOrderStore.reconciled/sync/reorder`）
/// 永远只能吃全局并集：喂它按屏过滤的列表，别的屏上的卡片会被当成"消失了"，
/// 过 5 秒宽限期后从全局顺序表里删掉——而 `reorder` 还会**把截断后的结果写进 UserDefaults**，
/// 第一次拖拽就造成跨会话的静默数据丢失。
enum StripScreenRouting {
    enum Placement: Equatable {
        /// 跟随某个窗口所在的屏。`nil` = 归属算不出来。
        case followsWindow(ScreenID?)
        /// 没有窗口，锚定主屏：Finder 常驻卡、已退出的保留应用灰图标、未运行的消息应用。
        case anchoredPrimary
    }

    /// `screen` 传 nil 表示「不做按屏过滤」（单面板/旧行为），一律显示。
    ///
    /// **no-orphan 不变量**：归属算不出来的卡片降级到主屏，绝不让它从所有任务条上消失——
    /// 那是「一个 bug」和「一张用户永远点不到的卡片」的区别。
    static func showsOn(_ placement: Placement, screen: ScreenID?, primary: ScreenID?) -> Bool {
        guard let screen else { return true }
        switch placement {
        case .anchoredPrimary:
            return screen == primary
        case .followsWindow(let owner):
            guard let owner else { return screen == primary }
            return owner == screen
        }
    }
}
