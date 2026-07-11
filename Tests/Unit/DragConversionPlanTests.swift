import XCTest

final class DragConversionPlanTests: XCTestCase {

    // MARK: - drawerDragOutMode

    func testFinderAndEmptyBundleIDReject() {
        XCTAssertEqual(DragConversionPlan.drawerDragOutMode(
            bundleID: "com.apple.finder", isMessagingMember: false, isInSnapshot: true, hasRealWindow: true), .reject)
        XCTAssertEqual(DragConversionPlan.drawerDragOutMode(
            bundleID: "", isMessagingMember: false, isInSnapshot: true, hasRealWindow: true), .reject)
    }

    func testRunningMessagingMemberReleasesToMessaging() {
        XCTAssertEqual(DragConversionPlan.drawerDragOutMode(
            bundleID: "com.example.chat", isMessagingMember: true, isInSnapshot: true, hasRealWindow: false), .releaseToMessaging)
    }

    /// 消息判定必须先于真窗口判定：运行中的消息应用有主窗口,不能误入 unstash。
    func testMessagingPrecedesRealWindowCheck() {
        XCTAssertEqual(DragConversionPlan.drawerDragOutMode(
            bundleID: "com.example.chat", isMessagingMember: true, isInSnapshot: true, hasRealWindow: true), .releaseToMessaging)
    }

    /// 未运行的消息应用拒收：消息区只显示运行中的应用,释放会凭空消失。
    func testNotRunningMessagingMemberRejects() {
        XCTAssertEqual(DragConversionPlan.drawerDragOutMode(
            bundleID: "com.example.chat", isMessagingMember: true, isInSnapshot: false, hasRealWindow: false), .reject)
    }

    func testRealWindowUnstashes() {
        XCTAssertEqual(DragConversionPlan.drawerDragOutMode(
            bundleID: "com.example.app", isMessagingMember: false, isInSnapshot: true, hasRealWindow: true), .unstash)
    }

    func testNoRealWindowKeepPlacement() {
        XCTAssertEqual(DragConversionPlan.drawerDragOutMode(
            bundleID: "com.example.app", isMessagingMember: false, isInSnapshot: false, hasRealWindow: false), .keepPlacement)
    }

    // MARK: - endAction

    func testStripAndFolderNeverRouteHere() {
        XCTAssertEqual(DragConversionPlan.endAction(
            source: .strip, isConvertedToStrip: false, isOverDropZone: true, isMessagingMember: false), .none)
        XCTAssertEqual(DragConversionPlan.endAction(
            source: .folder, isConvertedToStrip: false, isOverDropZone: true, isMessagingMember: false), .none)
    }

    func testMessagingChipOverDropZoneStashes() {
        XCTAssertEqual(DragConversionPlan.endAction(
            source: .messaging, isConvertedToStrip: false, isOverDropZone: true, isMessagingMember: true), .stashMessagingChip)
    }

    /// 消息 chip 在桌面/文件夹区/live 区（都不是投放区）松手 → 原地不动。
    func testMessagingChipOutsideDropZoneDoesNothing() {
        XCTAssertEqual(DragConversionPlan.endAction(
            source: .messaging, isConvertedToStrip: false, isOverDropZone: false, isMessagingMember: true), .none)
    }

    func testConvertedDrawerDragCommits() {
        XCTAssertEqual(DragConversionPlan.endAction(
            source: .drawer, isConvertedToStrip: true, isOverDropZone: true, isMessagingMember: false), .commitDrawerToStrip)
        XCTAssertEqual(DragConversionPlan.endAction(
            source: .drawer, isConvertedToStrip: true, isOverDropZone: false, isMessagingMember: false), .commitDrawerToStrip)
    }

    func testUnconvertedDrawerDropOnStripFallbackUnstashes() {
        XCTAssertEqual(DragConversionPlan.endAction(
            source: .drawer, isConvertedToStrip: false, isOverDropZone: true, isMessagingMember: false), .fallbackUnstash)
    }

    /// 消息成员的抽屉图标永不走降级 unstash：任务条上（消息区范围外）松手 → 留在抽屉。
    func testMessagingMemberNeverFallbackUnstashes() {
        XCTAssertEqual(DragConversionPlan.endAction(
            source: .drawer, isConvertedToStrip: false, isOverDropZone: true, isMessagingMember: true), .none)
    }

    func testUnconvertedDrawerDropOutsideDoesNothing() {
        XCTAssertEqual(DragConversionPlan.endAction(
            source: .drawer, isConvertedToStrip: false, isOverDropZone: false, isMessagingMember: false), .none)
    }
}
