import AppKit
import CoreGraphics
import Foundation

/// 显示器拓扑的 I/O 层：把 `NSScreen` 读成值类型喂给纯逻辑 `ScreenAttribution`。
/// 这里只做读取，不做任何判断。
@MainActor
enum ScreenGeometrySource {

    /// AppKit ↔ Quartz 翻转基准 = **主屏**（菜单栏所在屏 = `NSScreen.screens[0]`）frame 的 maxY。
    ///
    /// 绝不用 `NSScreen.main`：那是 key window 所在的屏，会跟着前台应用在显示器之间跑，
    /// 主副屏高度不同时会让所有 Quartz 换算整体偏移。
    static var primaryMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    /// 当前拓扑，Quartz 坐标。`screens[0]` = 主屏。
    ///
    /// 读不到 `NSScreenNumber` 的屏（实测从未出现）会退化成一个按下标合成的 id，
    /// 保证它仍然拿得到任务条，而不是被静默丢掉。
    static func current() -> [ScreenAttribution.ScreenGeometry] {
        let primaryMaxY = self.primaryMaxY
        return NSScreen.screens.enumerated().map { index, screen in
            ScreenAttribution.ScreenGeometry(
                id: screenID(of: screen) ?? ScreenID(rawValue: 0xFFFF_0000 | UInt32(index)),
                quartzFrame: ScreenAttribution.quartzRect(fromAppKit: screen.frame, primaryMaxY: primaryMaxY),
                isPrimary: index == 0
            )
        }
    }

    static func screenID(of screen: NSScreen) -> ScreenID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
            .map { ScreenID(rawValue: $0.uint32Value) }
    }
}
