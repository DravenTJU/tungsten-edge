import CoreGraphics
import Foundation

/// 「哪些显示器上有应用处于全屏」的纯判定（每屏常驻任务条，2026-07-27）。
///
/// 此前全屏检测只认任务条所在那一块屏、结果是一个全局 Bool；每块屏都常驻一条栏之后
/// 必须按屏分桶：副屏全屏只该藏副屏那条（owner 决策）。
///
/// 单窗口是否算全屏的判定仍然只有 `FullscreenWindowClassifier.isFullscreen` 一处，
/// 这里只负责「把候选窗口分到各自的屏、再逐屏套那条判定」。
enum FullscreenScreenScan {
    /// CG 层 0 的一个候选窗口（已排除桌面元素与本应用自己）。
    struct Candidate: Equatable {
        let quartzBounds: CGRect

        init(quartzBounds: CGRect) {
            self.quartzBounds = quartzBounds
        }
    }

    /// 返回当前处于全屏状态的显示器集合。
    ///
    /// 每块屏只看**第一个**与它显著重叠（宽度 > 70%）的候选——沿用改造前的语义：
    /// CG 列表按前后顺序排列，第一个覆盖这块屏的窗口就是这块屏的前台窗口，
    /// 它不铺满就说明这块屏没在全屏（后面被它盖住的窗口不算）。
    static func fullscreenDisplays(
        candidates: [Candidate],
        displays: [ScreenAttribution.ScreenGeometry],
        tolerance: CGFloat = 8
    ) -> Set<ScreenID> {
        var result: Set<ScreenID> = []
        for display in displays {
            let frame = display.quartzFrame
            guard let front = candidates.first(where: {
                $0.quartzBounds.intersects(frame) && $0.quartzBounds.width > frame.width * 0.7
            }) else { continue }

            let b = front.quartzBounds
            let fills = abs(b.width - frame.width) < tolerance
                && abs(b.height - frame.height) < tolerance
                && abs(b.minX - frame.minX) < tolerance
                && abs(b.minY - frame.minY) < tolerance
            if fills { result.insert(display.id) }
        }
        return result
    }
}
