import Foundation

/// LauncherChip 的**纯视觉决策层**：给定「运行 / 隐藏态 + 本区是否对隐藏态降级」，
/// 产出图标透明度与是否显示运行白点。抽成纯逻辑是为了可单测，渲染副作用留在 LauncherChip。
///
/// 关键语义（与旧 `dimsWhenInactive` 的区别）：
/// - **未运行恒定灰显**（`.notRunning`）、无白点——与 `dimsWhenHidden` 无关。消息区退出态因此也会变灰，
///   与抽屉下区、所有退出应用统一（owner 2026-07-19 拍板，反转了「消息图标常亮」旧决策）。
/// - `dimsWhenHidden` **只**决定「运行但隐藏」要不要降级：抽屉 / 普通 kept 传 true（`.hidden`），
///   消息区传 false（保持全亮、随时可点）。
/// - 白点 = 是否运行，四态都不变（退出无点 / 运行有点）。
enum LauncherChipVisualPlan {
    struct Visual: Equatable {
        /// 淡化档位。具体数值按外观从 `DockThemeTokens` 取（浅色不能只靠褪透明，见 `DockIconDim`）。
        let dim: DockIconDimState
        let showsRunningDot: Bool
    }

    static func visual(isRunning: Bool,
                       isHidden: Bool,
                       dimsWhenHidden: Bool) -> Visual {
        guard isRunning else {
            return Visual(dim: .notRunning, showsRunningDot: false)
        }
        let dim: DockIconDimState = (isHidden && dimsWhenHidden) ? .hidden : .bright
        return Visual(dim: dim, showsRunningDot: true)
    }
}
