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

    // MARK: - 拓扑

    /// 一块显示器的几何，全部是 **Quartz** 坐标（与 AX / CG 读出来的窗口 bounds 同一空间）。
    struct ScreenGeometry: Hashable, Sendable {
        let id: ScreenID
        let quartzFrame: CGRect
        /// 菜单栏所在屏（`NSScreen.screens[0]`）。无窗口条目锚定在它上面。
        let isPrimary: Bool

        init(id: ScreenID, quartzFrame: CGRect, isPrimary: Bool) {
            self.id = id
            self.quartzFrame = quartzFrame
            self.isPrimary = isPrimary
        }
    }

    static func primaryID(_ screens: [ScreenGeometry]) -> ScreenID? {
        (screens.first(where: \.isPrimary) ?? screens.first)?.id
    }

    // MARK: - 归属

    enum Attribution: Equatable {
        case resolved(ScreenID)
        /// 算不出来：没有 bounds、没有屏幕、或窗口与所有屏零重叠（例如被停在 x=-32000）。
        case unresolved
    }

    /// 窗口矩形属于哪块屏：**重叠面积最大者**。
    ///
    /// 平局规则（必须确定，否则窗口正好卡在接缝上会来回抖）：并列者里有主屏则取主屏，
    /// 否则取 `rawValue` 最小的那块。
    ///
    /// 退化矩形（宽或高 ≤ 0）没有面积可比，退化成「原点落在哪块屏里」。
    static func attribute(quartzFrame: CGRect?, screens: [ScreenGeometry]) -> Attribution {
        guard let frame = quartzFrame, !screens.isEmpty else { return .unresolved }

        if frame.width <= 0 || frame.height <= 0 {
            guard let hit = screens.first(where: { $0.quartzFrame.contains(frame.origin) }) else {
                return .unresolved
            }
            return .resolved(hit.id)
        }

        var best: (screen: ScreenGeometry, area: CGFloat)?
        for screen in screens {
            let overlap = frame.intersection(screen.quartzFrame)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            guard let current = best else { best = (screen, area); continue }
            if area > current.area {
                best = (screen, area)
            } else if area == current.area {
                // 平局：主屏优先，否则取较小 id —— 保证同样输入永远得到同样输出。
                if screen.isPrimary && !current.screen.isPrimary {
                    best = (screen, area)
                } else if screen.isPrimary == current.screen.isPrimary,
                          screen.id.rawValue < current.screen.id.rawValue {
                    best = (screen, area)
                }
            }
        }

        guard let winner = best else { return .unresolved }
        return .resolved(winner.screen.id)
    }

    // MARK: - 粘滞

    /// 把「本轮算出来的归属」和「座位上一次的归属」合成最终归属。
    ///
    /// - `isPinned`：座位已最小化、或它所属应用被隐藏。此时**旧值优先**——不少应用在最小化
    ///   期间会报出垃圾或贴着 Dock 的坐标，信它就会让卡片乱跳屏。这比「读不到才保留」更强，
    ///   是刻意的。
    /// - 旧值指向一块**已经不在拓扑里**的显示器（拔掉了）时一律丢弃，让它降级回主屏。
    ///   拔屏清理就靠这一条，所以检查必须在这里做，不能放在调用方。
    ///
    /// **不变量：返回值要么是 nil，要么一定在 `screens` 里。** 两个来源（本轮值和旧值）都过同一道
    /// 活性检查——绝不能只查旧值，否则调用方拿到一个指向已消失显示器的 id，卡片会投影到不存在的
    /// 任务条上而彻底消失。
    static func resolve(
        fresh: Attribution,
        previous: ScreenID?,
        isPinned: Bool,
        screens: [ScreenGeometry]
    ) -> ScreenID? {
        let live = Set(screens.map(\.id))
        func alive(_ id: ScreenID?) -> ScreenID? { id.flatMap { live.contains($0) ? $0 : nil } }

        let validPrevious = alive(previous)
        let validFresh: ScreenID? = {
            guard case .resolved(let id) = fresh else { return nil }
            return alive(id)
        }()

        if isPinned, let validPrevious { return validPrevious }
        return validFresh ?? validPrevious
    }
}
