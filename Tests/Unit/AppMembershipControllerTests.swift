import XCTest
@testable import macos_dock_cc_v2

@MainActor
final class AppMembershipControllerTests: XCTestCase {

    private var kept: KeptAppStore!
    private var drawer: DrawerStore!
    private var messaging: MessagingAppStore!
    private var controller: AppMembershipController!

    private func makeDefaults() -> UserDefaults {
        let suite = "test-membership-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    override func setUp() {
        super.setUp()
        let defaults = makeDefaults()
        kept = KeptAppStore(defaults: defaults)
        drawer = DrawerStore(defaults: defaults)
        messaging = MessagingAppStore(defaults: defaults)
        controller = AppMembershipController(
            keptAppStore: kept,
            drawerStore: drawer,
            messagingStore: messaging
        )
    }

    func testKeepInDockAddsAndRemovesFromDrawer() {
        drawer.add("com.example.app")
        controller.keepInDock("com.example.app")
        XCTAssertTrue(kept.contains("com.example.app"))
        XCTAssertFalse(drawer.contains("com.example.app"))
    }

    func testKeepInDockUnmarksMessaging() {
        messaging.mark("com.example.app")
        controller.keepInDock("com.example.app")
        XCTAssertTrue(kept.contains("com.example.app"))
        XCTAssertFalse(messaging.contains("com.example.app"))
    }

    func testKeepInDockRejectsFinder() {
        let finder = KeptAppStore.forbiddenBundleID
        controller.keepInDock(finder)
        XCTAssertFalse(kept.contains(finder))
    }

    func testRemoveFromDock() {
        controller.keepInDock("com.example.app")
        controller.removeFromDock("com.example.app")
        XCTAssertFalse(kept.contains("com.example.app"))
    }

    // 「从程序坞中移除」= 通用退出（owner 2026-07-11：抽屉即程序坞的一部分）

    func testRemoveFromDockClearsDrawerMembership() {
        drawer.add("com.example.app")
        controller.removeFromDock("com.example.app")
        XCTAssertFalse(drawer.contains("com.example.app"))
    }

    /// 抽屉里的消息应用移除时同时 unmark（含 opt-out）：不弹回消息区，autoRegister 也不加回。
    func testRemoveFromDockUnmarksMessagingWithOptOut() {
        let wechat = "com.tencent.xinWeChat"   // 内置白名单 id，autoRegister 无需查系统分类
        messaging.mark(wechat)
        drawer.add(wechat)
        controller.removeFromDock(wechat)
        XCTAssertFalse(drawer.contains(wechat))
        XCTAssertFalse(messaging.contains(wechat))
        messaging.autoRegister(runningBundleIDs: [wechat])
        XCTAssertFalse(messaging.contains(wechat), "opt-out 阻止自动重注册")
        messaging.mark(wechat)
        XCTAssertTrue(messaging.contains(wechat), "手动标记可回来")
    }

    func testMoveToDrawerRemovesKeptAndAddsDrawer() {
        controller.keepInDock("com.example.app")
        controller.moveToDrawer("com.example.app")
        XCTAssertFalse(kept.contains("com.example.app"))
        XCTAssertTrue(drawer.contains("com.example.app"))
    }

    func testMarkMessagingClearsKept() {
        controller.keepInDock("com.example.app")
        controller.markMessaging("com.example.app")
        XCTAssertFalse(kept.contains("com.example.app"))
        XCTAssertTrue(messaging.contains("com.example.app"))
        XCTAssertFalse(drawer.contains("com.example.app"))
    }

    func testReconcileKeptWinsRemovesKeptFromDrawerAndMessaging() {
        controller.keepInDock("com.example.app")
        // Manually add to drawer and messaging to simulate conflicting persisted state
        drawer.add("com.example.app")
        messaging.mark("com.example.app")
        controller.reconcileKeptWins()
        XCTAssertTrue(kept.contains("com.example.app"))
        XCTAssertFalse(drawer.contains("com.example.app"))
        XCTAssertFalse(messaging.contains("com.example.app"))
    }

    func testReconcileKeptWinsRemovesFinderFromDrawerAndMessaging() {
        let finder = KeptAppStore.forbiddenBundleID
        drawer.add(finder)
        messaging.mark(finder)
        controller.reconcileKeptWins()
        XCTAssertFalse(drawer.contains(finder))
        XCTAssertFalse(messaging.contains(finder))
    }

    // MARK: - DrawerStore migration

    func testDrawerStoreMigratesLaunchFavoriteKey() {
        let defaults = makeDefaults()
        defaults.set(["com.example.fav1", "com.example.fav2"], forKey: "launchFavoriteBundleIDs")
        defaults.set(["com.example.existing"], forKey: "drawerBundleIDs")
        let migrated = DrawerStore(defaults: defaults)
        // Favorites should be merged into drawer, old key deleted.
        XCTAssertTrue(migrated.contains("com.example.fav1"))
        XCTAssertTrue(migrated.contains("com.example.fav2"))
        XCTAssertTrue(migrated.contains("com.example.existing"))
        XCTAssertNil(defaults.stringArray(forKey: "launchFavoriteBundleIDs"))
    }
}
