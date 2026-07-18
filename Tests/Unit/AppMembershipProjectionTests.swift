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

    // MARK: - visibleDrawerIDs = drawer ∩ (running ∪ kept)

    func testVisibleDrawerIDsUsesRunningKeptUnion() {
        let result = AppMembershipProjection.visibleDrawerIDs(
            drawerIDs: ["running", "kept", "messagingOnly", "hidden"],
            keptIDs: ["kept"],
            runningIDs: ["running"]
        )
        // messagingOnly 既不 running 也不 kept → 现在隐藏（messaging 不再独立保活）。
        XCTAssertEqual(result, ["running", "kept"])
    }

    func testVisibleDrawerIDsPreservesInputOrderAndDeduplicates() {
        let result = AppMembershipProjection.visibleDrawerIDs(
            drawerIDs: ["b", "a", "b", "c"],
            keptIDs: ["a", "b", "c"],
            runningIDs: []
        )
        XCTAssertEqual(result, ["b", "a", "c"])
    }

    func testDrawerPreviewLimitsTo9() {
        let drawerIDs = (0..<15).map { "app\($0)" }
        let result = AppMembershipProjection.drawerPreview(
            drawerIDs: drawerIDs,
            keptIDs: drawerIDs,
            runningIDs: []
        )
        XCTAssertEqual(result.count, 9)
        XCTAssertEqual(result.first, "app0")
    }

    func testDrawerPreviewExcludesInactivePlacements() {
        let result = AppMembershipProjection.drawerPreview(
            drawerIDs: ["a", "b", "c"],
            keptIDs: ["b"],
            runningIDs: ["c"],
            limit: 9
        )
        XCTAssertEqual(result, ["b", "c"])
    }

    // MARK: - visibleMessagingIDs = (messaging − drawer) ∩ (running ∪ kept)

    func testVisibleMessagingIDsExcludesDrawerAndRequiresRunningOrKept() {
        let result = AppMembershipProjection.visibleMessagingIDs(
            messagingIDs: ["running", "kept", "stashed", "gone"],
            drawerIDs: ["stashed"],
            keptIDs: ["kept"],
            runningIDs: ["running"]
        )
        // stashed → 抽屉里隐藏；gone → 既不 running 也不 kept，隐藏。
        XCTAssertEqual(result, ["running", "kept"])
    }

    func testVisibleMessagingIDsPreservesOrderAndDeduplicates() {
        let result = AppMembershipProjection.visibleMessagingIDs(
            messagingIDs: ["c", "a", "c", "b"],
            drawerIDs: [],
            keptIDs: ["a", "b", "c"],
            runningIDs: []
        )
        XCTAssertEqual(result, ["c", "a", "b"])
    }
}
