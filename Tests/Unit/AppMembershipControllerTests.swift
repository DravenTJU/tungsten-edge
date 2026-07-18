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

    func testSetKeptAddsWithoutChangingDrawerPlacement() {
        drawer.add("com.example.app")
        controller.setKept("com.example.app", enabled: true)
        XCTAssertTrue(kept.contains("com.example.app"))
        XCTAssertTrue(drawer.contains("com.example.app"))
    }

    func testSetKeptRejectsMessagingIdentity() {
        messaging.mark("com.example.app")
        controller.setKept("com.example.app", enabled: true)
        XCTAssertFalse(kept.contains("com.example.app"))
        XCTAssertTrue(messaging.contains("com.example.app"))
    }

    func testSetKeptRejectsFinder() {
        let finder = KeptAppStore.forbiddenBundleID
        controller.setKept(finder, enabled: true)
        XCTAssertFalse(kept.contains(finder))
    }

    func testUnsetKeptLeavesDrawerPlacementAndMessagingUntouched() {
        controller.setKept("com.example.app", enabled: true)
        drawer.add("com.example.app")
        controller.setKept("com.example.app", enabled: false)
        XCTAssertFalse(kept.contains("com.example.app"))
        XCTAssertTrue(drawer.contains("com.example.app"))
    }

    func testMoveToDrawerPreservesKept() {
        controller.setKept("com.example.app", enabled: true)
        controller.moveToDrawer("com.example.app")
        XCTAssertTrue(kept.contains("com.example.app"))
        XCTAssertTrue(drawer.contains("com.example.app"))
    }

    func testMarkMessagingClearsKept() {
        controller.setKept("com.example.app", enabled: true)
        controller.markMessaging("com.example.app")
        XCTAssertFalse(kept.contains("com.example.app"))
        XCTAssertTrue(messaging.contains("com.example.app"))
        XCTAssertFalse(drawer.contains("com.example.app"))
    }

    func testReconcileAllowsKeptDrawerOverlapButRemovesMessagingConflict() {
        controller.setKept("com.example.app", enabled: true)
        // Manually add to drawer and messaging to simulate conflicting persisted state
        drawer.add("com.example.app")
        messaging.mark("com.example.app")
        controller.reconcileKeptWins()
        XCTAssertTrue(kept.contains("com.example.app"))
        XCTAssertTrue(drawer.contains("com.example.app"))
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
