import XCTest
@testable import macos_dock_cc_v2

final class AppMembershipProjectionTests: XCTestCase {

    func testDrawerMembersExcludesKept() {
        let result = AppMembershipProjection.drawerMembers(
            drawerIDs: ["a", "b", "c"],
            keptIDs: ["b"]
        )
        XCTAssertEqual(result, ["a", "c"])
    }

    func testDrawerMembersDeduplicates() {
        let result = AppMembershipProjection.drawerMembers(
            drawerIDs: ["a", "a", "b"],
            keptIDs: []
        )
        XCTAssertEqual(result, ["a", "b"])
    }

    func testDrawerMembersPreservesOrder() {
        let result = AppMembershipProjection.drawerMembers(
            drawerIDs: ["c", "a", "b"],
            keptIDs: ["a"]
        )
        XCTAssertEqual(result, ["c", "b"])
    }

    func testDrawerPreviewLimitsTo9() {
        let drawerIDs = (0..<15).map { "app\($0)" }
        let result = AppMembershipProjection.drawerPreview(
            drawerIDs: drawerIDs,
            keptIDs: []
        )
        XCTAssertEqual(result.count, 9)
        XCTAssertEqual(result.first, "app0")
    }

    func testDrawerPreviewExcludesKept() {
        let result = AppMembershipProjection.drawerPreview(
            drawerIDs: ["a", "b", "c"],
            keptIDs: ["b"],
            limit: 9
        )
        XCTAssertEqual(result, ["a", "c"])
    }

    func testMessagingIDsExcludesKept() {
        let result = AppMembershipProjection.messagingIDs(
            ["a", "b", "c"],
            excludingKeptIDs: ["b"]
        )
        XCTAssertEqual(result, ["a", "c"])
    }
}
