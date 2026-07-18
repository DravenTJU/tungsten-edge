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

    func testFreshInstallPersistsEmptyV2MigrationMarker() {
        let defaults = makeDefaults()
        let store = KeptAppStore(defaults: defaults)
        XCTAssertTrue(store.bundleIDs.isEmpty)
        XCTAssertEqual(defaults.stringArray(forKey: KeptAppStore.defaultsKey), [])
    }

    func testLoadsFromDefaultsKey() {
        let defaults = makeDefaults()
        defaults.set(["com.example.app"], forKey: KeptAppStore.defaultsKey)
        let store = KeptAppStore(defaults: defaults)
        XCTAssertEqual(store.bundleIDs, ["com.example.app"])
        XCTAssertEqual(
            defaults.stringArray(forKey: KeptAppStore.defaultsKey),
            ["com.example.app"]
        )
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
        XCTAssertEqual(defaults.stringArray(forKey: KeptAppStore.defaultsKey), [])
    }

    func testAddAndContains() {
        let defaults = makeDefaults()
        let store = KeptAppStore(defaults: defaults)
        store.add("com.example.app")
        XCTAssertTrue(store.contains("com.example.app"))
        XCTAssertEqual(
            defaults.stringArray(forKey: KeptAppStore.defaultsKey),
            ["com.example.app"]
        )
    }

    func testRemove() {
        let defaults = makeDefaults()
        defaults.set(["com.example.first", "com.example.second"], forKey: KeptAppStore.defaultsKey)
        let store = KeptAppStore(defaults: defaults)
        store.remove("com.example.first")
        XCTAssertFalse(store.contains("com.example.first"))
        XCTAssertEqual(
            defaults.stringArray(forKey: KeptAppStore.defaultsKey),
            ["com.example.second"]
        )
    }

    func testReorderIsNoOp() {
        let defaults = makeDefaults()
        defaults.set(["a", "b", "c"], forKey: KeptAppStore.defaultsKey)
        let store = KeptAppStore(defaults: defaults)
        // KeptAppStore has no reorder method — order is managed by StripOrderStore.
        // Verify the store keeps insertion/persistence order as-is.
        XCTAssertEqual(store.bundleIDs, ["a", "b", "c"])
    }

    // MARK: - Migration

    func testMigratesPreviousKeptAndLegacyPinnedIntoV2() {
        let defaults = makeDefaults()
        defaults.set(["com.example.previous"], forKey: KeptAppStore.previousDefaultsKey)
        defaults.set(["com.example.app1", "com.example.app2"], forKey: "pinnedAppBundleIDs")
        let store = KeptAppStore(defaults: defaults)
        // Migration: old key contents → new key, old key deleted.
        XCTAssertEqual(store.bundleIDs, ["com.example.previous", "com.example.app1", "com.example.app2"])
        XCTAssertEqual(
            defaults.stringArray(forKey: KeptAppStore.defaultsKey),
            ["com.example.previous", "com.example.app1", "com.example.app2"]
        )
        XCTAssertEqual(defaults.stringArray(forKey: KeptAppStore.previousDefaultsKey), ["com.example.previous"])
        XCTAssertNil(defaults.stringArray(forKey: "pinnedAppBundleIDs"))
    }

    func testMigratesDrawerPlacementsExceptMessagingAndFinder() {
        let defaults = makeDefaults()
        defaults.set(["plain", "chat", KeptAppStore.forbiddenBundleID], forKey: "drawerBundleIDs")
        defaults.set(["chat"], forKey: "messagingBundleIDs")
        let store = KeptAppStore(defaults: defaults)
        XCTAssertEqual(store.bundleIDs, ["plain"])
    }

    func testExistingEmptyV2KeyPreventsRemigration() {
        let defaults = makeDefaults()
        defaults.set([String](), forKey: KeptAppStore.defaultsKey)
        defaults.set(["drawer-app"], forKey: "drawerBundleIDs")
        let store = KeptAppStore(defaults: defaults)
        XCTAssertTrue(store.bundleIDs.isEmpty)
        XCTAssertEqual(defaults.stringArray(forKey: KeptAppStore.defaultsKey), [])
    }

    func testMigrationCleansFinderFromLegacy() {
        let defaults = makeDefaults()
        defaults.set(["com.example.app", "com.apple.finder"], forKey: "pinnedAppBundleIDs")
        let store = KeptAppStore(defaults: defaults)
        XCTAssertEqual(store.bundleIDs, ["com.example.app"])
        XCTAssertNil(defaults.stringArray(forKey: "pinnedAppBundleIDs"))
    }

    func testNoMigrationWhenLegacyEmpty() {
        let defaults = makeDefaults()
        defaults.set(["com.example.existing"], forKey: KeptAppStore.defaultsKey)
        let store = KeptAppStore(defaults: defaults)
        XCTAssertEqual(store.bundleIDs, ["com.example.existing"])
    }

    func testEmptyLegacyKeyIsRemovedWithoutOverwritingNewKey() {
        let defaults = makeDefaults()
        defaults.set([String](), forKey: "pinnedAppBundleIDs")
        defaults.set(["com.example.existing"], forKey: KeptAppStore.defaultsKey)
        let store = KeptAppStore(defaults: defaults)
        // 空的旧 key 也要删掉（不留残 key），且不得覆盖新 key 已有数据。
        XCTAssertNil(defaults.stringArray(forKey: "pinnedAppBundleIDs"))
        XCTAssertEqual(store.bundleIDs, ["com.example.existing"])
    }
}
