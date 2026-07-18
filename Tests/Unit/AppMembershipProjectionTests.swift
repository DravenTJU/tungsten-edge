import XCTest
@testable import macos_dock_cc_v2

final class AppMembershipProjectionTests: XCTestCase {

    func testDrawerMembersDeduplicates() {
        let result = AppMembershipProjection.drawerMembers(drawerIDs: ["a", "a", "b"])
        XCTAssertEqual(result, ["a", "b"])
    }

    func testDrawerMembersPreservesOrder() {
        let result = AppMembershipProjection.drawerMembers(drawerIDs: ["c", "a", "b"])
        XCTAssertEqual(result, ["c", "a", "b"])
    }

    func testVisibleDrawerIDsUsesRunningKeptOrMessagingUnion() {
        let result = AppMembershipProjection.visibleDrawerIDs(
            drawerIDs: ["running", "kept", "messaging", "hidden"],
            keptIDs: ["kept"],
            messagingIDs: ["messaging"],
            runningIDs: ["running"]
        )
        XCTAssertEqual(result, ["running", "kept", "messaging"])
    }

    func testVisibleDrawerIDsPreservesInputOrderAndDeduplicates() {
        let result = AppMembershipProjection.visibleDrawerIDs(
            drawerIDs: ["b", "a", "b", "c"],
            keptIDs: ["a", "b", "c"],
            messagingIDs: [],
            runningIDs: []
        )
        XCTAssertEqual(result, ["b", "a", "c"])
    }

    func testDrawerPreviewLimitsTo9() {
        let drawerIDs = (0..<15).map { "app\($0)" }
        let result = AppMembershipProjection.drawerPreview(
            drawerIDs: drawerIDs,
            keptIDs: drawerIDs,
            messagingIDs: [],
            runningIDs: []
        )
        XCTAssertEqual(result.count, 9)
        XCTAssertEqual(result.first, "app0")
    }

    func testDrawerPreviewExcludesInactivePlacements() {
        let result = AppMembershipProjection.drawerPreview(
            drawerIDs: ["a", "b", "c"],
            keptIDs: ["b"],
            messagingIDs: [],
            runningIDs: ["c"],
            limit: 9
        )
        XCTAssertEqual(result, ["b", "c"])
    }

    func testMessagingIDsExcludesKept() {
        let result = AppMembershipProjection.messagingIDs(
            ["a", "b", "c"],
            excludingKeptIDs: ["b"]
        )
        XCTAssertEqual(result, ["a", "c"])
    }
}
