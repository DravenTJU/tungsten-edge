import CoreGraphics
import Foundation

/// 显示器归属与坐标空间转换的**单一真相**（每屏常驻任务条，2026-07-27）。
///
/// 纯逻辑，不 import AppKit：拓扑由 `Platform/Screens/ScreenGeometrySource` 从 `NSScreen` 读出来
/// 喂进来，所有判断留在这里，可单测。
///
/// ⚠️ 坐标空间约定（踩过坑）：
/// - **AppKit 全局系**：原点 = 主屏（`NSScreen.screens[0]`）左下角，y 向上。`NSScreen.frame` 用它。
/// - **Quartz 全局系**：原点 = 主屏左上角，y 向下。CG 窗口列表、AX 的 `kAXPosition` 用它。
///
/// 翻转常数必须是**主屏**高度（`NSScreen.screens[0].frame.maxY`），
/// **绝不能用 `NSScreen.main`** —— 那是 key window 所在的屏，会跟着前台应用跑。
/// 修复前 `PanelCoordinator.toCGRect` / `windowZoomAvoidanceContext` / `WindowZoomAvoidanceController`
/// 都用错了它，在主副屏高度不同时（例如 1080 + 1440）会让全屏检测和最大化避让整体偏移。
enum ScreenAttribution {

    // MARK: - 坐标空间转换

    /// AppKit 全局矩形 → Quartz 全局矩形。`primaryMaxY` 必须是主屏 frame 的 maxY。
    ///
    /// 该变换是自逆的（两个方向公式相同），但仍拆成两个具名函数，
    /// 让调用点自己说清楚方向，避免读代码时反复推导。
    static func quartzRect(fromAppKit frame: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
    }

    /// Quartz 全局矩形 → AppKit 全局矩形。
    static func appKitRect(fromQuartz frame: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryMaxY - frame.maxY, width: frame.width, height: frame.height)
    }

    /// AppKit 全局点（如 `NSEvent.mouseLocation`）→ Quartz 全局点。
    static func quartzPoint(fromAppKit point: CGPoint, primaryMaxY: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryMaxY - point.y)
    }
}
