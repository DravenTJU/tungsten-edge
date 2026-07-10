import XCTest

@MainActor
final class AppMembershipControllerTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var pinned: PinnedAppStore!
    private var drawer: DrawerStore!
    private var favorite: LaunchFavoriteStore!
    private var messaging: MessagingAppStore!
    private var controller: AppMembershipController!

    override func setUp() {
        super.setUp()
        suiteName = "com.tungsten.edge.membership-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        pinned = PinnedAppStore(defaults: defaults)
        drawer = DrawerStore(defaults: defaults)
        favorite = LaunchFavoriteStore(defaults: defaults)
        messaging = MessagingAppStore(defaults: defaults)
        controller = AppMembershipController(
            pinnedAppStore: pinned,
            drawerStore: drawer,
            launchFavoriteStore: favorite,
            messagingStore: messaging
        )
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        controller = nil
        messaging = nil
        favorite = nil
        drawer = nil
        pinned = nil
        defaults = nil
        super.tearDown()
    }

    func testPinToStripRemovesOtherMembershipsAndOptsOutOfMessaging() {
        let id = "com.example.app"
        drawer.add(id)
        favorite.add(id)
        messaging.mark(id)

        controller.pinToStrip(id)

        XCTAssertTrue(pinned.contains(id))
        XCTAssertFalse(drawer.contains(id))
        XCTAssertFalse(favorite.contains(id))
        XCTAssertFalse(messaging.contains(id))
        messaging.autoRegister(runningBundleIDs: [id])
        XCTAssertFalse(messaging.contains(id))
    }

    func testPinToStripRejectsFinderWithoutChangingOtherMemberships() {
        let finder = PinnedAppStore.forbiddenBundleID
        drawer.add(finder)
        favorite.add(finder)
        messaging.mark(finder)

        controller.pinToStrip(finder)

        XCTAssertFalse(pinned.contains(finder))
        XCTAssertTrue(drawer.contains(finder))
        XCTAssertTrue(favorite.contains(finder))
        XCTAssertTrue(messaging.contains(finder))
    }

    func testFinderCannotEnterAnyManagedMembership() {
        let finder = PinnedAppStore.forbiddenBundleID

        controller.moveToDrawer(finder)
        controller.pinToLaunchpad(finder)
        controller.markMessaging(finder)

        XCTAssertFalse(pinned.contains(finder))
        XCTAssertFalse(drawer.contains(finder))
        XCTAssertFalse(favorite.contains(finder))
        XCTAssertFalse(messaging.contains(finder))
    }

    func testStartupReconciliationRemovesLegacyFinderMemberships() {
        let finder = PinnedAppStore.forbiddenBundleID
        drawer.add(finder)
        favorite.add(finder)
        messaging.mark(finder)

        controller.reconcilePinnedWins()

        XCTAssertFalse(drawer.contains(finder))
        XCTAssertFalse(favorite.contains(finder))
        XCTAssertFalse(messaging.contains(finder))
    }

    func testPinnedAppCanMoveToEachTargetIdentity() {
        let drawerID = "com.example.drawer"
        let favoriteID = "com.example.favorite"
        let messagingID = "com.example.messaging"
        [drawerID, favoriteID, messagingID].forEach(controller.pinToStrip)

        controller.moveToDrawer(drawerID)
        controller.pinToLaunchpad(favoriteID)
        controller.markMessaging(messagingID)

        XCTAssertFalse(pinned.contains(drawerID))
        XCTAssertTrue(drawer.contains(drawerID))
        XCTAssertFalse(pinned.contains(favoriteID))
        XCTAssertTrue(favorite.contains(favoriteID))
        XCTAssertFalse(pinned.contains(messagingID))
        XCTAssertTrue(messaging.contains(messagingID))
    }

    func testStartupReconciliationKeepsOnlyPinnedMembership() {
        let id = "com.example.conflict"
        pinned.add(id)
        drawer.add(id)
        favorite.add(id)
        messaging.mark(id)

        controller.reconcilePinnedWins()

        XCTAssertTrue(pinned.contains(id))
        XCTAssertFalse(drawer.contains(id))
        XCTAssertFalse(favorite.contains(id))
        XCTAssertFalse(messaging.contains(id))
    }
}
