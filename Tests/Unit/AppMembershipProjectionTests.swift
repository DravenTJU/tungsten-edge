import XCTest

final class AppMembershipProjectionTests: XCTestCase {
    func testDrawerMembersFormOrderedUnionAndExcludePinnedApps() {
        let result = AppMembershipProjection.drawerMembers(
            drawerIDs: ["drawer.one", "shared", "pinned"],
            launchFavoriteIDs: ["favorite.one", "shared", "favorite.two", "pinned"],
            pinnedIDs: ["pinned"]
        )

        XCTAssertEqual(result, ["drawer.one", "shared", "favorite.one", "favorite.two"])
    }

    func testDrawerPreviewUsesEffectiveMembersAndLimit() {
        let result = AppMembershipProjection.drawerPreview(
            drawerIDs: ["drawer.one", "pinned"],
            pinnedIDs: ["pinned"],
            limit: 2
        )

        XCTAssertEqual(result, ["drawer.one"])
    }

    func testDrawerPreviewWithNonPositiveLimitIsEmpty() {
        XCTAssertEqual(
            AppMembershipProjection.drawerPreview(
                drawerIDs: ["drawer.one"],
                pinnedIDs: [],
                limit: 0
            ),
            []
        )
    }

    func testMessagingIDsExcludePinnedAppsWithoutChangingOrder() {
        let result = AppMembershipProjection.messagingIDs(
            ["message.one", "pinned", "message.two", "message.one", ""],
            excludingPinnedIDs: ["pinned"]
        )

        XCTAssertEqual(result, ["message.one", "message.two"])
    }
}
