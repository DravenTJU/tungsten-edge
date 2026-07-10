import XCTest

@MainActor
final class PinnedAppStoreTests: XCTestCase {
    func testInitializationCleansInvalidAndDuplicateValuesInOrder() {
        let defaults = makeDefaults()
        defaults.set(
            ["com.example.first", "", "  ", "com.apple.finder", "com.example.first", " com.example.second "],
            forKey: PinnedAppStore.defaultsKey
        )

        let store = PinnedAppStore(defaults: defaults)

        XCTAssertEqual(store.bundleIDs, ["com.example.first", "com.example.second"])
        XCTAssertEqual(
            defaults.stringArray(forKey: PinnedAppStore.defaultsKey),
            ["com.example.first", "com.example.second"]
        )
    }

    func testCanPinRejectsEmptyValuesAndFinder() {
        let store = PinnedAppStore(defaults: makeDefaults())

        XCTAssertFalse(store.canPin(""))
        XCTAssertFalse(store.canPin(" \n "))
        XCTAssertFalse(store.canPin(PinnedAppStore.forbiddenBundleID))
        XCTAssertTrue(store.canPin("com.example.app"))
    }

    func testAddPreservesOrderRejectsFinderAndIgnoresDuplicates() {
        let defaults = makeDefaults()
        let store = PinnedAppStore(defaults: defaults)

        store.add("com.example.first")
        store.add(PinnedAppStore.forbiddenBundleID)
        store.add(" com.example.second ")
        store.add("com.example.first")

        XCTAssertEqual(store.bundleIDs, ["com.example.first", "com.example.second"])
        XCTAssertEqual(
            defaults.stringArray(forKey: PinnedAppStore.defaultsKey),
            ["com.example.first", "com.example.second"]
        )
    }

    func testRemoveUpdatesMembershipAndPersistence() {
        let defaults = makeDefaults()
        let store = PinnedAppStore(defaults: defaults)
        store.add("com.example.first")
        store.add("com.example.second")

        store.remove(" com.example.first ")

        XCTAssertFalse(store.contains("com.example.first"))
        XCTAssertTrue(store.contains("com.example.second"))
        XCTAssertEqual(defaults.stringArray(forKey: PinnedAppStore.defaultsKey), ["com.example.second"])
    }

    func testReorderUpdatesDisplayOrderAndPersistence() {
        let defaults = makeDefaults()
        let store = PinnedAppStore(defaults: defaults)
        store.add("com.example.first")
        store.add("com.example.second")
        store.add("com.example.third")

        store.reorder(
            draggedBundleID: "com.example.first",
            relativeTo: "com.example.third",
            after: true
        )

        let expected = ["com.example.second", "com.example.third", "com.example.first"]
        XCTAssertEqual(store.bundleIDs, expected)
        XCTAssertEqual(defaults.stringArray(forKey: PinnedAppStore.defaultsKey), expected)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.tungsten.edge.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
