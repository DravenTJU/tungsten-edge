import Foundation

/// 抽屉 / 文件夹弹窗这类「全桌面同时只开一个」的面板，在多显示器下点击该怎么处理
/// （每屏常驻任务条，owner 2026-07-27）。
///
/// 规则只有三条，但很容易在视图层写歪成「每屏各开一个」或「换屏时先关再开导致闪黑」：
/// - 什么都没开 → 开。
/// - 同内容 **且** 同屏 → 收起（再点一次关掉）。
/// - 其余（换内容 / 换屏 / 两者都换）→ **就地移动或切换**，不要 orderOut 再开。
enum SingletonPanelPlan {
    enum Action: Equatable {
        case open
        case moveOrSwitch
        case close
    }

    /// `content` 用泛型是因为抽屉只有一种内容（传常量即可），弹窗有文件夹/暂存架两种。
    static func decide<C: Equatable>(
        open: (content: C, screen: ScreenID)?,
        requested: (content: C, screen: ScreenID)
    ) -> Action {
        guard let open else { return .open }
        if open.content == requested.content && open.screen == requested.screen { return .close }
        return .moveOrSwitch
    }
}
