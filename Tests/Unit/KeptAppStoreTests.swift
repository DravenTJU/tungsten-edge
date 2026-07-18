import XCTest
@testable import macos_dock_cc_v2

@MainActor
final class KeptAppStoreTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test-kept-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func testFreshInstallPersistsEmptyV3MigrationMarker() {
        let defaults = makeDefaults()
        let store = KeptAppStore(defaults: defaults)
        XCTAssertTrue(store.bundleIDs.isEmpty)
        XCTAssertEqual(defaults.stringArray(forKey: KeptAppStore.defaultsKey), [])
    }

    func testLoadsFromV3Key() {
        let defaults = makeDefaults()
        defaults.set(["com.example.app"], forKey: KeptAppStore.defaultsKey)
        let store = KeptAppStore(defaults: defaults)
        XCTAssertEqual(store.bundleIDs, ["com.example.app"])
    }

    func testCanKeepRejectsFinder() {
        let store = KeptAppStore(defaults: makeDefaults())
        XCTAssertFalse(store.canKeep(KeptAppStore.forbiddenBundleID))
    }

    func testAddRejectsFinder() {
        let defaults = makeDefaults()
        let store = KeptAppStore(defaults: defaults)
        store.add(KeptAppStore.forbiddenBundleID)
        XCTAssertTrue(store.bundleIDs.isEmpty)
    }

    func testAddAndContains() {
        let defaults = makeDefaults()
        let store = KeptAppStore(defaults: defaults)
        store.add("com.example.app")
        XCTAssertTrue(store.contains("com.example.app"))
        XCTAssertEqual(defaults.stringArray(forKey: KeptAppStore.defaultsKey), ["com.example.app"])
    }

    func testRemove() {
        let defaults = makeDefaults()
        defaults.set(["com.example.first", "com.example.second"], forKey: KeptAppStore.defaultsKey)
        let store = KeptAppStore(defaults: defaults)
        store.remove("com.example.first")
        XCTAssertFalse(store.contains("com.example.first"))
        XCTAssertEqual(defaults.stringArray(forKey: KeptAppStore.defaultsKey), ["com.example.second"])
    }

    // MARK: - V3 migration

    func testMigratesFromV2PlusMessaging() {
        let defaults = makeDefaults()
        defaults.set(["com.example.kept"], forKey: KeptAppStore.previousDefaultsKey) // kept V2
        defaults.set(["com.chat.app"], forKey: "messagingBundleIDsV2")               // 权威消息名单
        defaults.set(["com.ignored.pinned"], forKey: "pinnedAppBundleIDs")           // 有 V2 时 pinned/drawer 被忽略
        let store = KeptAppStore(defaults: defaults)
        XCTAssertEqual(store.bundleIDs, ["com.example.kept", "com.chat.app"])
        XCTAssertEqual(defaults.stringArray(forKey: KeptAppStore.defaultsKey),
                       ["com.example.kept", "com.chat.app"])
    }

    func testMessagingV2KeyIsAuthoritativeEvenWhenEmpty() {
        // messaging V2 存在但空 → 权威为空，禁止回退旧 messaging 键求并集。
        let defaults = makeDefaults()
        defaults.set(["com.example.kept"], forKey: KeptAppStore.previousDefaultsKey)
        defaults.set([String](), forKey: "messagingBundleIDsV2")
        defaults.set(["com.legacy.chat"], forKey: "messagingBundleIDs")
        let store = KeptAppStore(defaults: defaults)
        XCTAssertEqual(store.bundleIDs, ["com.example.kept"])
    }

    func testMigratesStraightPastV2FoldsV1PinnedDrawerMessaging() {
        // 无 kept V2 → 折叠 V1 + pinned + drawer + messaging（messaging 现在并入）。
        let defaults = makeDefaults()
        defaults.set(["com.v1.kept"], forKey: "keptAppBundleIDs")     // V1
        defaults.set(["com.pin.app"], forKey: "pinnedAppBundleIDs")
        defaults.set(["com.drawer.app", "com.chat.app"], forKey: "drawerBundleIDs")
        defaults.set(["com.chat.app"], forKey: "messagingBundleIDs")  // 无 V2，旧 messaging 键权威
        let store = KeptAppStore(defaults: defaults)
        XCTAssertEqual(store.bundleIDs,
                       ["com.v1.kept", "com.pin.app", "com.drawer.app", "com.chat.app"])
    }

    func testMigrationExcludesFinderAndDeduplicates() {
        let defaults = makeDefaults()
        defaults.set(["com.dup", "com.dup", KeptAppStore.forbiddenBundleID], forKey: "keptAppBundleIDs")
        let store = KeptAppStore(defaults: defaults)
        XCTAssertEqual(store.bundleIDs, ["com.dup"])
    }

    func testExistingEmptyV3KeyPreventsRemigration() {
        let defaults = makeDefaults()
        defaults.set([String](), forKey: KeptAppStore.defaultsKey)
        defaults.set(["com.example.kept"], forKey: KeptAppStore.previousDefaultsKey)
        defaults.set(["com.chat.app"], forKey: "messagingBundleIDsV2")
        let store = KeptAppStore(defaults: defaults)
        XCTAssertTrue(store.bundleIDs.isEmpty)
    }

    func testMigrationFreezesLegacyKeysReadOnly() {
        // V3 迁移不得删除/覆写冻结旧键（干净回滚）。
        let defaults = makeDefaults()
        defaults.set(["com.v1.kept"], forKey: "keptAppBundleIDs")
        defaults.set(["com.pin.app"], forKey: "pinnedAppBundleIDs")
        _ = KeptAppStore(defaults: defaults)
        XCTAssertEqual(defaults.stringArray(forKey: "keptAppBundleIDs"), ["com.v1.kept"])
        XCTAssertEqual(defaults.stringArray(forKey: "pinnedAppBundleIDs"), ["com.pin.app"])
    }
}
