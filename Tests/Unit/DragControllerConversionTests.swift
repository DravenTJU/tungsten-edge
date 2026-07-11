import AppKit
import XCTest

/// 跨面板转换状态机的转换/回滚/落定/取消全矩阵（Codex 评审 2026-07-11 P2-6）。
/// 用真 store（临时 UserDefaults）+ 固定投放区 stub 驱动 DragController 本体（本地编译进测试
/// target,同 store 一致）；几何触发（何时进/出区）归视图层,这里只验证每个转换动作前后的成员关系与载荷。
@MainActor
final class DragControllerConversionTests: XCTestCase {

    private var drawer: DrawerStore!
    private var kept: KeptAppStore!
    private var messaging: MessagingAppStore!
    private var controller: DragController!
    /// 固定投放区：命中判定只看 beginDrag 的起点坐标。
    private let dropZone = CGRect(x: 0, y: 0, width: 100, height: 100)
    private let insideZone = CGPoint(x: 50, y: 50)
    private let outsideZone = CGPoint(x: 500, y: 500)

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared   // 无宿主 app 的测试 bundle 里创建 NSPanel 前先起 AppKit
        let suite = "test-dragconv-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        drawer = DrawerStore(defaults: defaults)
        kept = KeptAppStore(defaults: defaults)
        messaging = MessagingAppStore(defaults: defaults)
        controller = DragController(
            drawerStore: drawer,
            keptAppStore: kept,
            messagingStore: messaging,
            dropZonesProvider: { [dropZone] _ in [dropZone] },
            screenProvider: { NSScreen.main ?? NSScreen.screens[0] },
            carrierFactory: { _ in NSView() }
        )
    }

    override func tearDown() {
        controller.cancelDrag()   // 幂等收尾，防面板/监视器泄漏到下个用例
        super.tearDown()
    }

    private func payload(_ source: DragSource, _ bid: String) -> DragPayload {
        DragPayload(source: source, id: bid, bundleID: bid, item: nil,
                    visualKind: .drawerIcon, canExternalDrop: true)
    }

    private func begin(_ source: DragSource, _ bid: String, at point: CGPoint) {
        controller.beginDrag(payload: payload(source, bid), startScreenLocation: point, grabOffset: .zero)
    }

    // MARK: - 消息区 chip → 抽屉（收纳预览）

    func testMessagingToDrawerConvertFlipsPayloadAndAddsMember() {
        messaging.mark("chat")
        begin(.messaging, "chat", at: outsideZone)
        controller.convertMessagingToDrawer()
        XCTAssertTrue(drawer.contains("chat"))
        XCTAssertEqual(controller.draggingPayload?.source, .drawer)
        XCTAssertTrue(controller.isConvertedFromMessaging)
        XCTAssertTrue(messaging.contains("chat"), "收纳不清消息 flag")
    }

    func testMessagingToDrawerRevertRestoresOriginal() {
        messaging.mark("chat")
        begin(.messaging, "chat", at: outsideZone)
        controller.convertMessagingToDrawer()
        controller.revertMessagingFromDrawer()
        XCTAssertFalse(drawer.contains("chat"))
        XCTAssertEqual(controller.draggingPayload?.source, .messaging)
        XCTAssertFalse(controller.isConvertedFromMessaging)
    }

    func testMessagingToDrawerDropInsideDrawerCommits() {
        messaging.mark("chat")
        begin(.messaging, "chat", at: outsideZone)
        controller.convertMessagingToDrawer()
        controller.endDrag()   // 抽屉体内松手（不在外部投放区）
        XCTAssertTrue(drawer.contains("chat"), "落定后仍是抽屉成员")
        XCTAssertNil(controller.draggingPayload)
        XCTAssertFalse(controller.isConvertedFromMessaging, "commit 清转换态")
    }

    func testMessagingToDrawerCancelRollsBack() {
        messaging.mark("chat")
        begin(.messaging, "chat", at: outsideZone)
        controller.convertMessagingToDrawer()
        controller.cancelDrag()
        XCTAssertFalse(drawer.contains("chat"), "取消恢复原成员关系")
        XCTAssertNil(controller.draggingPayload)
    }

    /// 未进抽屉体、在胶囊投放区松手 → 收纳（等同任务条卡胶囊落点）。
    func testMessagingChipDropOnCapsuleStashes() {
        messaging.mark("chat")
        begin(.messaging, "chat", at: insideZone)
        controller.endDrag()
        XCTAssertTrue(drawer.contains("chat"))
    }

    /// 桌面/文件夹区/live 区（非投放区）松手 → 原地不动。
    func testMessagingChipDropOutsideDoesNothing() {
        messaging.mark("chat")
        begin(.messaging, "chat", at: outsideZone)
        controller.endDrag()
        XCTAssertFalse(drawer.contains("chat"))
        XCTAssertTrue(messaging.contains("chat"))
    }

    // MARK: - 抽屉里的消息应用 → 消息区（临时释放）

    func testDrawerToMessagingReleaseRemovesMemberAndFlipsPayload() {
        messaging.mark("chat"); drawer.add("chat")
        begin(.drawer, "chat", at: outsideZone)
        controller.convertDrawerToMessaging()
        XCTAssertFalse(drawer.contains("chat"))
        XCTAssertEqual(controller.draggingPayload?.source, .messaging)
        XCTAssertTrue(controller.isReleasedToMessaging)
    }

    func testDrawerToMessagingRevertRestoresDrawer() {
        messaging.mark("chat"); drawer.add("chat")
        begin(.drawer, "chat", at: outsideZone)
        controller.convertDrawerToMessaging()
        controller.revertDrawerToMessaging()
        XCTAssertTrue(drawer.contains("chat"))
        XCTAssertEqual(controller.draggingPayload?.source, .drawer)
        XCTAssertFalse(controller.isReleasedToMessaging)
    }

    func testDrawerToMessagingDropCommits() {
        messaging.mark("chat"); drawer.add("chat")
        begin(.drawer, "chat", at: outsideZone)
        controller.convertDrawerToMessaging()
        controller.endDrag()   // 消息区内松手（非投放区）
        XCTAssertFalse(drawer.contains("chat"), "落定：已离开抽屉")
        XCTAssertTrue(messaging.contains("chat"), "消息 flag 原样")
        XCTAssertNil(controller.draggingPayload)
    }

    func testDrawerToMessagingCancelRollsBack() {
        messaging.mark("chat"); drawer.add("chat")
        begin(.drawer, "chat", at: outsideZone)
        controller.convertDrawerToMessaging()
        controller.cancelDrag()
        XCTAssertTrue(drawer.contains("chat"), "取消回到抽屉")
    }

    /// 消息成员的抽屉图标在任务条（消息区范围外）松手 → 不走降级 unstash,留在抽屉（评审 P1-3）。
    func testMessagingMemberDrawerDragNeverFallbackUnstashes() {
        messaging.mark("chat"); drawer.add("chat")
        begin(.drawer, "chat", at: insideZone)   // 投放区内（任务条面板）
        controller.endDrag()
        XCTAssertTrue(drawer.contains("chat"))
    }

    /// 非消息成员保持既有降级路径：任务条上松手 → 移出抽屉。
    func testNonMessagingDrawerDragFallbackUnstashes() {
        drawer.add("plain")
        begin(.drawer, "plain", at: insideZone)
        controller.endDrag()
        XCTAssertFalse(drawer.contains("plain"))
    }

    // MARK: - 既有两向的回归（转换态收敛进 CrossPanelConversion 后行为不变）

    func testStripToDrawerConvertRevertRestoresKept() {
        kept.add("app")
        begin(.strip, "app", at: outsideZone)
        controller.convertStripToDrawer()
        XCTAssertTrue(drawer.contains("app"))
        XCTAssertFalse(kept.contains("app"))
        XCTAssertTrue(controller.isConvertedFromStrip)
        controller.revertStripFromDrawer()
        XCTAssertFalse(drawer.contains("app"))
        XCTAssertTrue(kept.contains("app"), "撤销恢复 kept 标志")
        XCTAssertEqual(controller.draggingPayload?.source, .strip)
    }

    func testDrawerToStripConvertKeepPlacementAndRevert() {
        drawer.add("app")
        begin(.drawer, "app", at: outsideZone)
        controller.convertDrawerToStrip()
        XCTAssertFalse(drawer.contains("app"))
        XCTAssertEqual(controller.convertedDrawerBundleID, "app")
        controller.markKeepPlacement()
        XCTAssertTrue(kept.contains("app"))
        controller.revertDrawerToStrip()
        XCTAssertTrue(drawer.contains("app"))
        XCTAssertFalse(kept.contains("app"), "keepPlacement 撤销收回 kept")
        XCTAssertNil(controller.convertedDrawerBundleID)
    }

    func testCancelFromDrawerToStripFiresCancelCallback() {
        drawer.add("app")
        var cancelled = false
        controller.onDrawerToStripCancelled = { cancelled = true }
        begin(.drawer, "app", at: outsideZone)
        controller.convertDrawerToStrip()
        controller.cancelDrag()
        XCTAssertTrue(cancelled)
        XCTAssertTrue(drawer.contains("app"))
    }
}
