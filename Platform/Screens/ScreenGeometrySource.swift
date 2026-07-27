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
}
