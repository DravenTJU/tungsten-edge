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
        XCTAssertNil(defaults.stringArray(forKey: KeptAppStore.defaultsKey))
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

    func testMigratesFromLegacyPinnedKey() {
        let defaults = makeDefaults()
        defaults.set(["com.example.app1", "com.example.app2"], forKey: "pinnedAppBundleIDs")
        let store = KeptAppStore(defaults: defaults)
        // Migration: old key contents → new key, old key deleted.
        XCTAssertEqual(store.bundleIDs, ["com.example.app1", "com.example.app2"])
        XCTAssertEqual(
            defaults.stringArray(forKey: KeptAppStore.defaultsKey),
            ["com.example.app1", "com.example.app2"]
        )
        XCTAssertNil(defaults.stringArray(forKey: "pinnedAppBundleIDs"))
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
}
