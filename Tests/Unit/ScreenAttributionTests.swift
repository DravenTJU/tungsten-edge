import CoreGraphics
import XCTest

/// 坐标空间转换的回归保护（每屏常驻任务条，检查点 0）。
///
/// 核心是最后两个用例：它们构造成「主屏高度 ≠ NSScreen.main 高度」，
/// 在旧公式（拿 `NSScreen.main?.frame.height` 当翻转基准）下必然算错。
final class ScreenAttributionTests: XCTestCase {

    // MARK: - 基本翻转

    func testQuartzRectFlipsAgainstPrimaryMaxY() {
        // 主屏 1920x1080，AppKit 原点在左下角。
        // 一个贴着主屏顶部的 100 高窗口：AppKit y = 980...1080 → Quartz y = 0...100。
        let appKit = CGRect(x: 10, y: 980, width: 200, height: 100)
        let quartz = ScreenAttribution.quartzRect(fromAppKit: appKit, primaryMaxY: 1080)

        XCTAssertEqual(quartz.minX, 10)
        XCTAssertEqual(quartz.minY, 0)
        XCTAssertEqual(quartz.width, 200)
        XCTAssertEqual(quartz.height, 100)
    }

    func testRoundTripIsIdentity() {
        let original = CGRect(x: -400, y: 120, width: 640, height: 480)
        let quartz = ScreenAttribution.quartzRect(fromAppKit: original, primaryMaxY: 1080)
        let back = ScreenAttribution.appKitRect(fromQuartz: quartz, primaryMaxY: 1080)

        XCTAssertEqual(back, original)
    }

    func testPointFlip() {
        let point = ScreenAttribution.quartzPoint(fromAppKit: CGPoint(x: 50, y: 1000), primaryMaxY: 1080)
        XCTAssertEqual(point.x, 50)
        XCTAssertEqual(point.y, 80)
    }

    // MARK: - 副屏摆在主屏上方 / 左侧（负坐标）

    /// 副屏摆在主屏正上方：AppKit 里它的 y 是正的且大于主屏高度，Quartz 里应该是负的。
    func testSecondaryScreenAbovePrimaryMapsToNegativeQuartzY() {
        // 主屏 1920x1080 占 AppKit y = 0...1080；副屏 1920x1200 摞在上面，占 y = 1080...2280。
        let secondaryAppKit = CGRect(x: 0, y: 1080, width: 1920, height: 1200)
        let quartz = ScreenAttribution.quartzRect(fromAppKit: secondaryAppKit, primaryMaxY: 1080)

        XCTAssertEqual(quartz.minY, -1200)
        XCTAssertEqual(quartz.maxY, 0)
    }

    /// 副屏摆在主屏左侧：x 为负，翻转不应该动 x。
    func testSecondaryScreenLeftOfPrimaryKeepsNegativeX() {
        let secondaryAppKit = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let quartz = ScreenAttribution.quartzRect(fromAppKit: secondaryAppKit, primaryMaxY: 1080)

        XCTAssertEqual(quartz.minX, -2560)
        XCTAssertEqual(quartz.width, 2560)
    }

    // MARK: - 旧公式必然失败的用例

    /// 主屏 1080 高、副屏 1440 高，且副屏底边与主屏底边对齐（AppKit y 都从 0 起）。
    ///
    /// 正确结果：副屏在 Quartz 里 y = 1080 - 1440 = -360 ... 1080。
    /// 旧公式在前台窗口位于副屏时会把 `NSScreen.main?.frame.height` 读成 1440，
    /// 算出 y = 0 ... 1440 —— 整体偏移 360pt，正是全屏检测误判的根源。
    func testMixedHeightSecondaryUsesPrimaryHeightNotItsOwn() {
        let secondaryAppKit = CGRect(x: 1920, y: 0, width: 2560, height: 1440)

        let correct = ScreenAttribution.quartzRect(fromAppKit: secondaryAppKit, primaryMaxY: 1080)
        XCTAssertEqual(correct.minY, -360)
        XCTAssertEqual(correct.maxY, 1080)

        // 旧行为（错误地用副屏自身高度当基准）会得到完全不同的结果。
        let buggy = ScreenAttribution.quartzRect(fromAppKit: secondaryAppKit, primaryMaxY: 1440)
        XCTAssertNotEqual(correct, buggy)
        XCTAssertEqual(buggy.minY, 0)
    }

    /// 同样的偏移会污染鼠标点换算 —— Option+绿点命中测试就是靠它找窗口的。
    func testMixedHeightMousePointUsesPrimaryHeight() {
        let mouse = CGPoint(x: 2500, y: 700)

        let correct = ScreenAttribution.quartzPoint(fromAppKit: mouse, primaryMaxY: 1080)
        let buggy = ScreenAttribution.quartzPoint(fromAppKit: mouse, primaryMaxY: 1440)

        XCTAssertEqual(correct.y, 380)
        XCTAssertEqual(buggy.y, 740)
        XCTAssertNotEqual(correct, buggy)
    }

    // MARK: - 退化输入

    func testZeroPrimaryHeightDoesNotCrashAndStaysConsistent() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let quartz = ScreenAttribution.quartzRect(fromAppKit: rect, primaryMaxY: 0)
        XCTAssertEqual(quartz.minY, -100)
        XCTAssertEqual(ScreenAttribution.appKitRect(fromQuartz: quartz, primaryMaxY: 0), rect)
    }

    func testZeroSizeRectKeepsOrigin() {
        let rect = CGRect(x: 42, y: 300, width: 0, height: 0)
        let quartz = ScreenAttribution.quartzRect(fromAppKit: rect, primaryMaxY: 1080)
        XCTAssertEqual(quartz.minX, 42)
        XCTAssertEqual(quartz.minY, 780)
        XCTAssertEqual(quartz.width, 0)
        XCTAssertEqual(quartz.height, 0)
    }

    // MARK: - 归属（面积多数）

    /// 主屏 1920x1080 在左，副屏 2560x1440 在右（Quartz 坐标，主屏左上角为原点）。
    private static let primary = ScreenAttribution.ScreenGeometry(
        id: ScreenID(rawValue: 1), quartzFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true)
    private static let secondary = ScreenAttribution.ScreenGeometry(
        id: ScreenID(rawValue: 2), quartzFrame: CGRect(x: 1920, y: -360, width: 2560, height: 1440), isPrimary: false)
    private var twoScreens: [ScreenAttribution.ScreenGeometry] { [Self.primary, Self.secondary] }

    func testWindowFullyInsideSecondaryReturnsThatScreen() {
        let w = CGRect(x: 2200, y: 100, width: 800, height: 600)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: twoScreens), .resolved(ScreenID(rawValue: 2)))
    }

    func testWindowFullyInsidePrimaryReturnsPrimary() {
        let w = CGRect(x: 100, y: 100, width: 800, height: 600)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: twoScreens), .resolved(ScreenID(rawValue: 1)))
    }

    /// 跨接缝 60/40：1000 宽的窗口，600 在主屏、400 在副屏 → 主屏。
    func testStraddlingWindowGoesToMajorityAreaScreenPrimarySide() {
        let w = CGRect(x: 1320, y: 100, width: 1000, height: 600)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: twoScreens), .resolved(ScreenID(rawValue: 1)))
    }

    /// 反方向 40/60 → 副屏。
    func testStraddlingWindowGoesToMajorityAreaScreenSecondarySide() {
        let w = CGRect(x: 1520, y: 100, width: 1000, height: 600)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: twoScreens), .resolved(ScreenID(rawValue: 2)))
    }

    /// 正好 50/50：必须确定性地落到主屏，否则窗口卡在接缝上时卡片会两屏来回跳。
    func testExactFiftyFiftyTieBreaksToPrimary() {
        let w = CGRect(x: 1420, y: 100, width: 1000, height: 600)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: twoScreens), .resolved(ScreenID(rawValue: 1)))
    }

    /// 两块都不是主屏时平局 → 取 rawValue 较小者（同样是为了确定性）。
    func testTieAmongNonPrimariesBreaksToLowestDisplayID() {
        let left = ScreenAttribution.ScreenGeometry(
            id: ScreenID(rawValue: 7), quartzFrame: CGRect(x: 0, y: 0, width: 1000, height: 1000), isPrimary: false)
        let right = ScreenAttribution.ScreenGeometry(
            id: ScreenID(rawValue: 3), quartzFrame: CGRect(x: 1000, y: 0, width: 1000, height: 1000), isPrimary: false)
        let w = CGRect(x: 500, y: 0, width: 1000, height: 100)

        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: [left, right]), .resolved(ScreenID(rawValue: 3)))
        // 顺序不影响结果。
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: [right, left]), .resolved(ScreenID(rawValue: 3)))
    }

    func testWindowEntirelyOutsideAllScreensIsUnresolved() {
        let w = CGRect(x: 9000, y: 9000, width: 100, height: 100)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: twoScreens), .unresolved)
    }

    /// AX 经典「停车位」：窗口被挪到 x = -32000。必须判定为无归属，由投影层降级到主屏。
    func testParkedWindowAtLargeNegativeCoordinatesIsUnresolved() {
        let w = CGRect(x: -32000, y: -32000, width: 800, height: 600)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: twoScreens), .unresolved)
    }

    func testNilBoundsIsUnresolved() {
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: nil, screens: twoScreens), .unresolved)
    }

    func testZeroScreensIsUnresolved() {
        let w = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: []), .unresolved)
    }

    /// 退化矩形（宽或高 ≤ 0）没有面积可比，退化成原点包含判定。
    func testDegenerateZeroSizeRectUsesOriginContainment() {
        let onSecondary = CGRect(x: 2200, y: 100, width: 0, height: 0)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: onSecondary, screens: twoScreens), .resolved(ScreenID(rawValue: 2)))

        let nowhere = CGRect(x: 9999, y: 9999, width: 0, height: 0)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: nowhere, screens: twoScreens), .unresolved)
    }

    /// 只贴着边缘、零面积重叠（窗口右边缘正好等于主屏左边缘）→ 不算归属。
    func testEdgeTouchingWithZeroOverlapIsNotAMatch() {
        let single = [Self.primary]
        let w = CGRect(x: -800, y: 100, width: 800, height: 600)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: single), .unresolved)
    }

    /// 垂直堆叠布局（副屏在主屏上方，Quartz y 为负）。
    func testVerticallyStackedLayout() {
        let above = ScreenAttribution.ScreenGeometry(
            id: ScreenID(rawValue: 5), quartzFrame: CGRect(x: 0, y: -1200, width: 1920, height: 1200), isPrimary: false)
        let w = CGRect(x: 100, y: -900, width: 400, height: 300)
        XCTAssertEqual(ScreenAttribution.attribute(quartzFrame: w, screens: [Self.primary, above]), .resolved(ScreenID(rawValue: 5)))
    }

    // MARK: - primaryID

    func testPrimaryIDPrefersFlaggedScreen() {
        XCTAssertEqual(ScreenAttribution.primaryID(twoScreens), ScreenID(rawValue: 1))
        XCTAssertEqual(ScreenAttribution.primaryID([Self.secondary, Self.primary]), ScreenID(rawValue: 1))
    }

    func testPrimaryIDFallsBackToFirstWhenNoneFlagged() {
        XCTAssertEqual(ScreenAttribution.primaryID([Self.secondary]), ScreenID(rawValue: 2))
        XCTAssertNil(ScreenAttribution.primaryID([]))
    }
}
