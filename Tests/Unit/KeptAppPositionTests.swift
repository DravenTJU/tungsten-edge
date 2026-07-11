import XCTest
@testable import macos_dock_cc_v2

@MainActor
final class KeptAppPositionTests: XCTestCase {

    /// 可变时间盒，让 `now` 闭包能从测试方法里推进。
    private final class TimeBox {
        var time: Date
        init(_ time: Date) { self.time = time }
    }

    private func makeStore(timeBox: TimeBox, keptIDs: Set<String> = []) -> StripOrderStore {
        let suite = "test-kept-pos-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return StripOrderStore(
            defaults: defaults,
            now: { timeBox.time },
            keptIDsProvider: { keptIDs }
        )
    }

    // MARK: - a. app exit → tabgrp-* grace → app-* placeholder → position = rightmost tabgrp-*

    func testExitPlaceholderInheritsRightmostWindowPosition() {
        let timeBox = TimeBox(Date())
        let store = makeStore(timeBox: timeBox)
        // Two windows from com.app, already ordered
        store.sync(current: ["tabgrp-100-s1", "tabgrp-100-s2"],
                   appKeyOf: ["tabgrp-100-s1": "com.app", "tabgrp-100-s2": "com.app"])
        // App exits → placeholder injected (DockStripView would do this)
        store.sync(current: ["app-com.app"],
                   appKeyOf: ["app-com.app": "com.app"])
        // Grace: tabgrp-* still in liveOrder; placeholder inserted after rightmost tabgrp-*
        // reconciled 只返回 current 中的 id（用户只看到占位），但 liveOrder 保留了完整位置
        XCTAssertEqual(store.liveOrder, ["tabgrp-100-s1", "tabgrp-100-s2", "app-com.app"])
        XCTAssertEqual(store.reconciled(current: ["app-com.app"],
                                        appKeyOf: ["app-com.app": "com.app"]),
                       ["app-com.app"])
    }

    // MARK: - b. grace expires → tabgrp-* gone → placeholder keeps position

    func testGraceExpiresPlaceholderStaysInPlace() {
        let timeBox = TimeBox(Date())
        let store = makeStore(timeBox: timeBox)
        store.sync(current: ["tabgrp-100-s1", "tabgrp-100-s2"],
                   appKeyOf: ["tabgrp-100-s1": "com.app", "tabgrp-100-s2": "com.app"])
        store.sync(current: ["app-com.app"],
                   appKeyOf: ["app-com.app": "com.app"])
        // Advance past grace (5s)
        timeBox.time = Date().addingTimeInterval(6)
        store.sync(current: ["app-com.app"],
                   appKeyOf: ["app-com.app": "com.app"])
        // Now tabgrp-* should be gone from liveOrder, placeholder is alone
        let reconciled = store.reconciled(current: ["app-com.app"],
                                          appKeyOf: ["app-com.app": "com.app"])
        XCTAssertEqual(reconciled, ["app-com.app"])
    }

    // MARK: - c. click placeholder → new tabgrp-* inserts next to placeholder → placeholder stops → window block returns

    func testLaunchFromPlaceholderInsertsNextToIt() {
        let timeBox = TimeBox(Date())
        let store = makeStore(timeBox: timeBox)
        store.sync(current: ["tabgrp-100-s1", "tabgrp-100-s2"],
                   appKeyOf: ["tabgrp-100-s1": "com.app", "tabgrp-100-s2": "com.app"])
        // Exit → placeholder
        store.sync(current: ["app-com.app"],
                   appKeyOf: ["app-com.app": "com.app"])
        // Advance past grace
        timeBox.time = Date().addingTimeInterval(6)
        store.sync(current: ["app-com.app"],
                   appKeyOf: ["app-com.app": "com.app"])
        // New window appears → sticky appKey for "app-com.app" = "com.app"
        // New tabgrp-* should insert after "app-com.app" (same appKey)
        store.sync(current: ["app-com.app", "tabgrp-100-s3"],
                   appKeyOf: ["app-com.app": "com.app", "tabgrp-100-s3": "com.app"])
        let reconciled = store.reconciled(current: ["app-com.app", "tabgrp-100-s3"],
                                          appKeyOf: ["app-com.app": "com.app", "tabgrp-100-s3": "com.app"])
        XCTAssertEqual(reconciled, ["app-com.app", "tabgrp-100-s3"])
        // Now placeholder stops injecting (app running with real window)
        store.sync(current: ["tabgrp-100-s3"],
                   appKeyOf: ["tabgrp-100-s3": "com.app"])
        // app-com.app enters grace, still in liveOrder temporarily
        // reconciled 只返回 current（用户只看到 tabgrp-100-s3），但 liveOrder 保留了 app-com.app 的位置
        XCTAssertEqual(store.liveOrder, ["app-com.app", "tabgrp-100-s3"])
        XCTAssertEqual(store.reconciled(current: ["tabgrp-100-s3"],
                                        appKeyOf: ["tabgrp-100-s3": "com.app"]),
                       ["tabgrp-100-s3"])
    }

    // MARK: - d. multiple kept apps alternate exit/launch without cross-contamination

    func testMultipleKeptAppsNoCrossContamination() {
        let timeBox = TimeBox(Date())
        let store = makeStore(timeBox: timeBox)
        // Two apps with windows, interleaved in order
        store.sync(current: ["tabgrp-100-s1", "tabgrp-200-s1", "tabgrp-100-s2"],
                   appKeyOf: ["tabgrp-100-s1": "com.a", "tabgrp-200-s1": "com.b", "tabgrp-100-s2": "com.a"])
        // App A exits → placeholder
        store.sync(current: ["tabgrp-200-s1", "app-com.a"],
                   appKeyOf: ["tabgrp-200-s1": "com.b", "app-com.a": "com.a"])
        // Advance past grace for tabgrp-100-*
        timeBox.time = Date().addingTimeInterval(6)
        store.sync(current: ["tabgrp-200-s1", "app-com.a"],
                   appKeyOf: ["tabgrp-200-s1": "com.b", "app-com.a": "com.a"])
        // App B exits → placeholder
        store.sync(current: ["app-com.a", "app-com.b"],
                   appKeyOf: ["app-com.a": "com.a", "app-com.b": "com.b"])
        // Advance past grace for tabgrp-200-s1
        timeBox.time = Date().addingTimeInterval(12)
        store.sync(current: ["app-com.a", "app-com.b"],
                   appKeyOf: ["app-com.a": "com.a", "app-com.b": "com.b"])
        // Both placeholders in order: A before B (matching original interleaving)
        let reconciled = store.reconciled(current: ["app-com.a", "app-com.b"],
                                          appKeyOf: ["app-com.a": "com.a", "app-com.b": "com.b"])
        XCTAssertEqual(reconciled, ["app-com.a", "app-com.b"])
        // App A relaunches → new window inserts next to app-com.a
        store.sync(current: ["app-com.a", "tabgrp-100-s3", "app-com.b"],
                   appKeyOf: ["app-com.a": "com.a", "tabgrp-100-s3": "com.a", "app-com.b": "com.b"])
        let reconciled2 = store.reconciled(current: ["app-com.a", "tabgrp-100-s3", "app-com.b"],
                                           appKeyOf: ["app-com.a": "com.a", "tabgrp-100-s3": "com.a", "app-com.b": "com.b"])
        XCTAssertEqual(reconciled2, ["app-com.a", "tabgrp-100-s3", "app-com.b"])
    }

    // MARK: - e. sticky appKey pruning

    func testStickyAppKeyPruning() {
        let timeBox = TimeBox(Date())
        let store = makeStore(timeBox: timeBox)
        store.sync(current: ["tabgrp-100-s1"],
                   appKeyOf: ["tabgrp-100-s1": "com.app"])
        // App exits and grace expires
        store.sync(current: [],
                   appKeyOf: [:])
        timeBox.time = Date().addingTimeInterval(6)
        store.sync(current: [],
                   appKeyOf: [:])
        // tabgrp-100-s1 should be gone from liveOrder; its sticky appKey should be pruned
        // Verify by launching a new window — it should go to the end (no sticky key to match)
        store.sync(current: ["tabgrp-100-s2"],
                   appKeyOf: ["tabgrp-100-s2": "com.app"])
        let reconciled = store.reconciled(current: ["tabgrp-100-s2"],
                                          appKeyOf: ["tabgrp-100-s2": "com.app"])
        XCTAssertEqual(reconciled, ["tabgrp-100-s2"])
    }

    // MARK: - f. persistableLiveOrder with keptIDs

    func testPersistableLiveOrderWithKeptIDs() {
        let order = ["tabgrp-1-s1", "app-com.kept", "app-com.notkept", "tabgrp-2-s1"]
        let result = StripOrdering.persistableLiveOrder(order, keptIDs: ["com.kept"])
        XCTAssertEqual(result, ["tabgrp-1-s1", "app-com.kept", "tabgrp-2-s1"])
    }

    func testPersistableLiveOrderWithoutKeptIDs() {
        let order = ["tabgrp-1-s1", "app-com.kept", "tabgrp-2-s1"]
        let result = StripOrdering.persistableLiveOrder(order)
        XCTAssertEqual(result, ["tabgrp-1-s1", "tabgrp-2-s1"])
    }
}
