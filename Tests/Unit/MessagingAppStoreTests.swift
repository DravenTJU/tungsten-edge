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

    // MARK: - V2 key migration

    func testNameListMigratesFromLegacyKeyToV2AndFreezesLegacy() {
        let defaults = makeDefaults()
        defaults.set(["com.chat.legacy"], forKey: "messagingBundleIDs")
        let store = MessagingAppStore(defaults: defaults)
        XCTAssertTrue(store.contains("com.chat.legacy"))
        XCTAssertEqual(defaults.stringArray(forKey: "messagingBundleIDsV2"), ["com.chat.legacy"])
        // 旧键冻结、不动（回滚可读）。
        XCTAssertEqual(defaults.stringArray(forKey: "messagingBundleIDs"), ["com.chat.legacy"])
    }

    func testFreshInstallPersistsEmptyV2Markers() {
        let defaults = makeDefaults()
        _ = MessagingAppStore(defaults: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "messagingBundleIDsV2"), [])
        XCTAssertEqual(defaults.stringArray(forKey: "messagingOptOutBundleIDsV2"), [])
    }

    func testExistingV2KeyPreventsRemigrationFromLegacy() {
        let defaults = makeDefaults()
        defaults.set(["com.v2.only"], forKey: "messagingBundleIDsV2")
        defaults.set(["com.legacy.ignored"], forKey: "messagingBundleIDs")
        let store = MessagingAppStore(defaults: defaults)
        XCTAssertTrue(store.contains("com.v2.only"))
        XCTAssertFalse(store.contains("com.legacy.ignored"))
    }

    func testOptOutMigratesIndependentlyOfNameList() {
        // 名单已有 V2、opt-out 只有旧键 → opt-out 独立迁移（部分迁移状态）。
        let defaults = makeDefaults()
        defaults.set([String](), forKey: "messagingBundleIDsV2")
        defaults.set(["com.tencent.qq"], forKey: "messagingOptOutBundleIDs") // builtin，被 opt-out
        let store = MessagingAppStore(defaults: defaults)
        let added = store.autoRegister(runningBundleIDs: ["com.tencent.qq"])
        XCTAssertTrue(added.isEmpty) // opt-out 迁移生效，不重新注册
        XCTAssertEqual(defaults.stringArray(forKey: "messagingOptOutBundleIDsV2"), ["com.tencent.qq"])
    }

    func testMarkReturnsTrueOnFirstJoinFalseAfter() {
        let store = MessagingAppStore(defaults: makeDefaults())
        XCTAssertTrue(store.mark("com.chat.app"))
        XCTAssertFalse(store.mark("com.chat.app"))
    }

    func testAutoRegisterReturnsNewlyAddedIDs() {
        let store = MessagingAppStore(defaults: makeDefaults())
        let chat = "com.tencent.xinWeChat" // builtin whitelist
        let added = store.autoRegister(runningBundleIDs: [chat, "com.not.messaging"])
        XCTAssertEqual(added, [chat])
        XCTAssertTrue(store.autoRegister(runningBundleIDs: [chat]).isEmpty) // 第二轮无新增
    }
}
