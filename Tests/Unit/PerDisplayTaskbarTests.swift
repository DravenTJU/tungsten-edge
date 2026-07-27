import CoreGraphics
import XCTest

/// 每屏常驻任务条的纯决策函数（检查点 3）：屏幕集合 diff、按屏过滤、单例面板开合、按屏全屏。
final class PerDisplayTaskbarTests: XCTestCase {

    private let s1 = ScreenID(rawValue: 1)
    private let s2 = ScreenID(rawValue: 2)
    private let s3 = ScreenID(rawValue: 3)

    // MARK: - ScreenSetDiff

    func testDiffAddsNewScreen() {
        let plan = ScreenSetDiff.plan(existing: [s1], current: [s1, s2])
        XCTAssertEqual(plan.added, [s2])
        XCTAssertEqual(plan.kept, [s1])
        XCTAssertEqual(plan.removed, [])
    }

    func testDiffRemovesDetachedScreen() {
        let plan = ScreenSetDiff.plan(existing: [s1, s2], current: [s1])
        XCTAssertEqual(plan.added, [])
        XCTAssertEqual(plan.kept, [s1])
        XCTAssertEqual(plan.removed, [s2])
    }

    /// 只是改了排列顺序（或分辨率）→ 全部 kept，不该拆了重建面板。
    func testDiffReorderOnlyKeepsEverything() {
        let plan = ScreenSetDiff.plan(existing: [s1, s2], current: [s2, s1])
        XCTAssertEqual(plan.added, [])
        XCTAssertEqual(plan.removed, [])
        XCTAssertEqual(Set(plan.kept), [s1, s2])
    }

    func testDiffEmptyCurrentRemovesAll() {
        let plan = ScreenSetDiff.plan(existing: [s1, s2], current: [])
        XCTAssertEqual(plan.added, [])
        XCTAssertEqual(plan.kept, [])
        XCTAssertEqual(plan.removed, [s1, s2])
    }

    func testDiffKeepsSystemOrderForAdded() {
        let plan = ScreenSetDiff.plan(existing: [], current: [s3, s1, s2])
        XCTAssertEqual(plan.added, [s3, s1, s2], "added 要沿用系统顺序，任务条排布才确定")
    }

    /// 合成 id 撞车时不能产出重复条目（否则同一块屏会建两条任务条）。
    func testDiffDeduplicatesCurrent() {
        let plan = ScreenSetDiff.plan(existing: [], current: [s1, s1, s2])
        XCTAssertEqual(plan.added, [s1, s2])
    }

    // MARK: - StripScreenRouting

    func testWindowChipShowsOnlyOnItsOwnScreen() {
        let p = StripScreenRouting.Placement.followsWindow(s2)
        XCTAssertTrue(StripScreenRouting.showsOn(p, screen: s2, primary: s1))
        XCTAssertFalse(StripScreenRouting.showsOn(p, screen: s1, primary: s1))
    }

    /// Finder 常驻卡 / 已退出的保留应用 / 未运行的消息应用（owner 2026-07-27：只放主屏）。
    func testWindowlessItemShowsOnlyOnPrimary() {
        let p = StripScreenRouting.Placement.anchoredPrimary
        XCTAssertTrue(StripScreenRouting.showsOn(p, screen: s1, primary: s1))
        XCTAssertFalse(StripScreenRouting.showsOn(p, screen: s2, primary: s1))
    }

    /// no-orphan 不变量：归属算不出来的卡片降级到主屏，绝不能从所有任务条上消失。
    func testUnknownScreenChipFallsBackToPrimaryAndNeverVanishes() {
        let p = StripScreenRouting.Placement.followsWindow(nil)
        XCTAssertTrue(StripScreenRouting.showsOn(p, screen: s1, primary: s1))
        XCTAssertFalse(StripScreenRouting.showsOn(p, screen: s2, primary: s1))
    }

    /// 运行中的消息应用跟着它主窗口所在的屏走。
    func testRunningMessagingWithMainWindowFollowsThatWindowsScreen() {
        let p = StripScreenRouting.Placement.followsWindow(s2)
        XCTAssertFalse(StripScreenRouting.showsOn(p, screen: s1, primary: s1))
        XCTAssertTrue(StripScreenRouting.showsOn(p, screen: s2, primary: s1))
    }

    /// `screen == nil` = 不做按屏过滤（单面板/测试路径），一律显示——95% 单屏用户的回归保护。
    func testNilScreenContextShowsEverything() {
        XCTAssertTrue(StripScreenRouting.showsOn(.anchoredPrimary, screen: nil, primary: s1))
        XCTAssertTrue(StripScreenRouting.showsOn(.followsWindow(s2), screen: nil, primary: s1))
        XCTAssertTrue(StripScreenRouting.showsOn(.followsWindow(nil), screen: nil, primary: nil))
    }

    /// 主屏未知时（拓扑还没读出来）也不能让锚定主屏的条目全部消失……
    /// 但这里必须返回 false：primary 为 nil 说明还没有任何屏，此时也没有任务条在渲染。
    func testNoPrimaryYieldsNoAnchoredItems() {
        XCTAssertFalse(StripScreenRouting.showsOn(.anchoredPrimary, screen: s1, primary: nil))
    }

    // MARK: - SingletonPanelPlan

    func testSingletonOpensWhenNothingOpen() {
        XCTAssertEqual(SingletonPanelPlan.decide(open: nil, requested: (content: 0, screen: s1)), .open)
    }

    func testSingletonClosesOnSameContentSameScreen() {
        XCTAssertEqual(
            SingletonPanelPlan.decide(open: (content: 0, screen: s1), requested: (content: 0, screen: s1)),
            .close)
    }

    /// 同内容换屏 = 移过去，不是关掉，也不是开出第二个。
    func testSingletonMovesOnSameContentOtherScreen() {
        XCTAssertEqual(
            SingletonPanelPlan.decide(open: (content: 0, screen: s1), requested: (content: 0, screen: s2)),
            .moveOrSwitch)
    }

    func testSingletonSwitchesOnOtherContentSameScreen() {
        XCTAssertEqual(
            SingletonPanelPlan.decide(open: (content: "a", screen: s1), requested: (content: "b", screen: s1)),
            .moveOrSwitch)
    }

    func testSingletonMovesAndSwitchesOnBothDifferent() {
        XCTAssertEqual(
            SingletonPanelPlan.decide(open: (content: "a", screen: s1), requested: (content: "b", screen: s2)),
            .moveOrSwitch)
    }

    // MARK: - FullscreenScreenScan

    private let primaryDisplay = ScreenAttribution.ScreenGeometry(
        id: ScreenID(rawValue: 1), quartzFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080), isPrimary: true)
    private let secondaryDisplay = ScreenAttribution.ScreenGeometry(
        id: ScreenID(rawValue: 2), quartzFrame: CGRect(x: 1920, y: 0, width: 2560, height: 1440), isPrimary: false)

    /// 核心用例：副屏全屏**不该**把主屏也算进去（owner 2026-07-27 推翻了旧的「一屏全屏全部隐藏」）。
    func testFullscreenOnSecondaryOnlyMarksSecondary() {
        let candidates = [
            FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440)),
            FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 100, y: 100, width: 800, height: 600)),
        ]
        let result = FullscreenScreenScan.fullscreenDisplays(
            candidates: candidates, displays: [primaryDisplay, secondaryDisplay])
        XCTAssertEqual(result, [ScreenID(rawValue: 2)])
    }

    func testTwoFullscreenAppsOnTwoDisplays() {
        let candidates = [
            FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
            FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 1920, y: 0, width: 2560, height: 1440)),
        ]
        let result = FullscreenScreenScan.fullscreenDisplays(
            candidates: candidates, displays: [primaryDisplay, secondaryDisplay])
        XCTAssertEqual(result, [ScreenID(rawValue: 1), ScreenID(rawValue: 2)])
    }

    func testNoFullscreenWhenNothingFills() {
        let candidates = [FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 0, y: 0, width: 1900, height: 900))]
        let result = FullscreenScreenScan.fullscreenDisplays(
            candidates: candidates, displays: [primaryDisplay, secondaryDisplay])
        XCTAssertTrue(result.isEmpty)
    }

    /// 8pt 容差内算铺满，容差外不算。
    func testEightPointTolerance() {
        let within = [FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 0, y: 0, width: 1915, height: 1075))]
        XCTAssertEqual(
            FullscreenScreenScan.fullscreenDisplays(candidates: within, displays: [primaryDisplay]),
            [ScreenID(rawValue: 1)])

        let outside = [FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 0, y: 0, width: 1900, height: 1060))]
        XCTAssertTrue(
            FullscreenScreenScan.fullscreenDisplays(candidates: outside, displays: [primaryDisplay]).isEmpty)
    }

    /// 前台窗口没铺满这块屏 → 这块屏不算全屏，即使它**后面**盖着一个铺满的窗口。
    /// 沿用改造前的语义：CG 列表按前后顺序，只看第一个覆盖这块屏的。
    func testOnlyFrontmostCoveringWindowCounts() {
        let candidates = [
            FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 0, y: 40, width: 1900, height: 900)),
            FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
        ]
        XCTAssertTrue(
            FullscreenScreenScan.fullscreenDisplays(candidates: candidates, displays: [primaryDisplay]).isEmpty)
    }

    /// 窄窗口（宽度不到屏幕 70%）不算这块屏的前台覆盖窗口，直接跳过。
    func testNarrowWindowIsNotACoveringCandidate() {
        let candidates = [
            FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 0, y: 0, width: 400, height: 1080)),
            FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
        ]
        XCTAssertEqual(
            FullscreenScreenScan.fullscreenDisplays(candidates: candidates, displays: [primaryDisplay]),
            [ScreenID(rawValue: 1)])
    }

    func testNoDisplaysYieldsEmpty() {
        let candidates = [FullscreenScreenScan.Candidate(quartzBounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))]
        XCTAssertTrue(FullscreenScreenScan.fullscreenDisplays(candidates: candidates, displays: []).isEmpty)
    }

    // MARK: - PanelVisibilityState.barIsVisible

    func testBarVisibilityMatrix() {
        XCTAssertTrue(PanelVisibilityState.barIsVisible(global: true, screenFullscreen: false))
        XCTAssertFalse(PanelVisibilityState.barIsVisible(global: true, screenFullscreen: true))
        XCTAssertFalse(PanelVisibilityState.barIsVisible(global: false, screenFullscreen: false))
        XCTAssertFalse(PanelVisibilityState.barIsVisible(global: false, screenFullscreen: true))
    }
}
