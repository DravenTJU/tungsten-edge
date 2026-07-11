import XCTest

@MainActor
final class MessagingAppStoreTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test-messaging-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(_ ids: [String], defaults: UserDefaults? = nil) -> MessagingAppStore {
        let d = defaults ?? makeDefaults()
        let store = MessagingAppStore(defaults: d)
        for id in ids { store.mark(id) }
        return store
    }

    // MARK: - reorder

    func testReorderBeforeAndAfterTarget() {
        let store = makeStore(["a", "b", "c"])
        store.reorder(draggedID: "c", relativeTo: "a", after: false)
        XCTAssertEqual(store.bundleIDs, ["c", "a", "b"])
        store.reorder(draggedID: "c", relativeTo: "b", after: true)
        XCTAssertEqual(store.bundleIDs, ["a", "b", "c"])
    }

    func testReorderToHeadAndTail() {
        let store = makeStore(["a", "b", "c"])
        store.reorder(draggedID: "b", relativeTo: "a", after: false)   // 首位
        XCTAssertEqual(store.bundleIDs, ["b", "a", "c"])
        store.reorder(draggedID: "b", relativeTo: "c", after: true)    // 末位
        XCTAssertEqual(store.bundleIDs, ["a", "c", "b"])
    }

    func testReorderMiddle() {
        let store = makeStore(["a", "b", "c", "d"])
        store.reorder(draggedID: "d", relativeTo: "b", after: false)
        XCTAssertEqual(store.bundleIDs, ["a", "d", "b", "c"])
    }

    func testReorderOntoSelfIsNoOp() {
        let store = makeStore(["a", "b"])
        store.reorder(draggedID: "a", relativeTo: "a", after: true)
        XCTAssertEqual(store.bundleIDs, ["a", "b"])
    }

    func testReorderUnknownIDsAreNoOp() {
        let store = makeStore(["a", "b"])
        store.reorder(draggedID: "ghost", relativeTo: "a", after: true)
        XCTAssertEqual(store.bundleIDs, ["a", "b"])
        store.reorder(draggedID: "a", relativeTo: "ghost", after: true)
        XCTAssertEqual(store.bundleIDs, ["a", "b"])
    }

    /// 隐藏成员（收进抽屉/未运行,不在区里显示）保持相对位置——reorder 直接改全量持久数组。
    func testHiddenMemberKeepsRelativePosition() {
        let store = makeStore(["a", "hidden", "b"])
        store.reorder(draggedID: "a", relativeTo: "b", after: true)
        XCTAssertEqual(store.bundleIDs, ["hidden", "b", "a"])
    }

    func testReorderPersistsAcrossReload() {
        let defaults = makeDefaults()
        let store = makeStore(["a", "b", "c"], defaults: defaults)
        store.reorder(draggedID: "c", relativeTo: "a", after: false)
        let reloaded = MessagingAppStore(defaults: defaults)
        XCTAssertEqual(reloaded.bundleIDs, ["c", "a", "b"])
    }
}
