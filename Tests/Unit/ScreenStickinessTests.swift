import CoreGraphics
import XCTest

/// 最小化 / 隐藏窗口「粘住最后已知屏幕」的规则（每屏常驻任务条，检查点 1）。
///
/// 关键点：粘滞条件是「座位已最小化或应用被隐藏」，**不是**「读不到 bounds 才保留」。
/// 不少应用在最小化期间会报出垃圾或贴着 Dock 的坐标，信它就会让卡片乱跳屏。
final class ScreenStickinessTests: XCTestCase {

    private let s1 = ScreenID(rawValue: 1)
    private let s2 = ScreenID(rawValue: 2)

    private lazy var screens: [ScreenAttribution.ScreenGeometry] = [
        .init(id: s1, quartzFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true),
        .init(id: s2, quartzFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1440), isPrimary: false),
    ]

    // MARK: - 粘滞生效

    func testMinimizedKeepsPreviousScreenEvenWhenFreshBoundsSayOtherScreen() {
        let result = ScreenAttribution.resolve(
            fresh: .resolved(s1), previous: s2, isPinned: true, screens: screens)
        XCTAssertEqual(result, s2, "最小化期间的 AX 坐标不可信，必须保留旧归属")
    }

    func testHiddenAppKeepsPreviousScreen() {
        // isPinned 同时覆盖「应用被隐藏」，调用方传的是 s.isMinimized || app.isHidden。
        let result = ScreenAttribution.resolve(
            fresh: .resolved(s1), previous: s2, isPinned: true, screens: screens)
        XCTAssertEqual(result, s2)
    }

    func testUnresolvedFreshKeepsPreviousEvenWhenNotPinned() {
        let result = ScreenAttribution.resolve(
            fresh: .unresolved, previous: s2, isPinned: false, screens: screens)
        XCTAssertEqual(result, s2, "算不出来时不该把已知归属清掉")
    }

    // MARK: - 粘滞不该生效

    func testVisibleWindowMoveOverridesPrevious() {
        let result = ScreenAttribution.resolve(
            fresh: .resolved(s2), previous: s1, isPinned: false, screens: screens)
        XCTAssertEqual(result, s2, "可见窗口跨屏必须立刻改归属，否则卡片赖在错的屏上")
    }

    func testFirstAttributionWhileMinimizedUsesFreshWhenNoPrevious() {
        // seed 时本来就已最小化的窗口没有历史，只能尽力用当下的 bounds。
        let result = ScreenAttribution.resolve(
            fresh: .resolved(s2), previous: nil, isPinned: true, screens: screens)
        XCTAssertEqual(result, s2)
    }

    func testPinnedWithNoPreviousAndUnresolvedFreshIsNil() {
        let result = ScreenAttribution.resolve(
            fresh: .unresolved, previous: nil, isPinned: true, screens: screens)
        XCTAssertNil(result, "彻底算不出来 → nil，由投影层降级到主屏")
    }

    // MARK: - 拔屏清理

    /// 旧归属指向一块已经不在拓扑里的显示器时必须丢弃。
    /// 这条检查刻意放在 `resolve` 里而不是调用方：否则最小化的窗口会被粘滞规则
    /// 永远钉在一块已经拔掉的显示器上。
    func testPreviousScreenMissingFromTopologyIsDropped() {
        let detached = ScreenID(rawValue: 99)
        let result = ScreenAttribution.resolve(
            fresh: .resolved(s1), previous: detached, isPinned: true, screens: screens)
        XCTAssertEqual(result, s1, "失效的旧归属让位给本轮算出的值")
    }

    func testPinnedWithDetachedPreviousAndUnresolvedFreshIsNil() {
        let detached = ScreenID(rawValue: 99)
        let result = ScreenAttribution.resolve(
            fresh: .unresolved, previous: detached, isPinned: true, screens: screens)
        XCTAssertNil(result, "旧归属失效 + 算不出新的 → nil → 主屏")
    }

    /// 不变量：返回值要么 nil，要么一定在当前拓扑里。本轮值和旧值都要过活性检查——
    /// 只查旧值的话，调用方会拿到一个指向已消失显示器的 id，卡片投影不到任何任务条上就消失了。
    func testEmptyTopologyDropsEverything() {
        XCTAssertNil(ScreenAttribution.resolve(fresh: .resolved(s1), previous: s2, isPinned: true, screens: []))
        XCTAssertNil(ScreenAttribution.resolve(fresh: .resolved(s1), previous: nil, isPinned: false, screens: []))
    }

    func testFreshPointingAtDetachedScreenIsAlsoDropped() {
        let detached = ScreenID(rawValue: 99)
        XCTAssertNil(ScreenAttribution.resolve(
            fresh: .resolved(detached), previous: nil, isPinned: false, screens: screens))
        XCTAssertEqual(
            ScreenAttribution.resolve(fresh: .resolved(detached), previous: s2, isPinned: false, screens: screens),
            s2, "本轮值失效时退回仍然有效的旧值")
    }
}
