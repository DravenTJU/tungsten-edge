import XCTest

@MainActor
final class SettingsCoordinatorTests: XCTestCase {
    func testLaunchStateAlwaysComesFromService() {
        let store = makeStore(launchAtLogin: true)
        let launch = LaunchServiceStub(state: .off)
        let coordinator = makeCoordinator(store: store, launch: launch)

        XCTAssertEqual(coordinator.launchAtLoginState, .off)

        launch.state = .requiresApproval
        coordinator.refreshLaunchAtLoginState()
        XCTAssertEqual(coordinator.launchAtLoginState, .requiresApproval)
    }

    func testLaunchFailureDoesNotChangeStoredMirror() {
        let store = makeStore(launchAtLogin: false)
        let launch = LaunchServiceStub(state: .off)
        launch.setError = TestError.failed
        let coordinator = makeCoordinator(store: store, launch: launch)

        guard case .failure = coordinator.setLaunchAtLogin(true) else {
            return XCTFail("expected failure")
        }
        XCTAssertFalse(store.launchAtLogin)
        XCTAssertEqual(coordinator.launchAtLoginState, .off)
    }

    func testLaunchSuccessUpdatesMirrorAndPublishedState() {
        let store = makeStore(launchAtLogin: false)
        let launch = LaunchServiceStub(state: .off)
        launch.stateAfterSet = .on
        let coordinator = makeCoordinator(store: store, launch: launch)

        guard case .success = coordinator.setLaunchAtLogin(true) else {
            return XCTFail("expected success")
        }
        XCTAssertTrue(store.launchAtLogin)
        XCTAssertEqual(coordinator.launchAtLoginState, .on)
    }

    func testNativeApplyReadsLivePreviousAndPublishesReadback() {
        let store = makeStore(nativeDelay: AppSettingsStore.neverHideDelay)
        let native = NativeDockServiceStub(states: [
            NativeDockAutohideState(enabled: true, delay: 0.4),
            NativeDockAutohideState(enabled: true, delay: 0.7),
        ])
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = coordinator.applyNativeDock(target: 1.0)

        XCTAssertEqual(native.appliedDelays, [1.0])
        XCTAssertEqual(outcome.resolvedDelay, 0.7)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 0.7)
    }

    func testNativeApplyFallsBackToMirrorWhenBothReadsFail() {
        let store = makeStore(nativeDelay: 0.3)
        let native = NativeDockServiceStub(states: [nil, nil])
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = coordinator.applyNativeDock(target: 1.0)

        XCTAssertEqual(outcome.resolvedDelay, 1.0)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 1.0)
    }

    func testNativeFailureAndUnreadableReadbackKeepsLivePrevious() {
        let store = makeStore(nativeDelay: 0.2)
        let native = NativeDockServiceStub(states: [
            NativeDockAutohideState(enabled: true, delay: 0.6),
            nil,
        ])
        native.applyError = TestError.failed
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = coordinator.applyNativeDock(target: 1.0)

        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(outcome.resolvedDelay, 0.6)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 0.6)
    }

    func testNativeFailureStillUsesReadablePartialResult() {
        let store = makeStore(nativeDelay: 0.2)
        let native = NativeDockServiceStub(states: [
            NativeDockAutohideState(enabled: true, delay: 0.6),
            NativeDockAutohideState(enabled: true, delay: 0.8),
        ])
        native.applyError = TestError.failed
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = coordinator.applyNativeDock(target: 1.0)

        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(outcome.resolvedDelay, 0.8)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 0.8)
    }

    func testSandboxUnavailableDoesNotWriteOrChangeMirror() {
        let store = makeStore(nativeDelay: 0.5)
        let native = NativeDockServiceStub(isAvailable: false)
        let coordinator = makeCoordinator(store: store, native: native)

        let outcome = coordinator.applyNativeDock(target: 1.0)

        XCTAssertNotNil(outcome.error)
        XCTAssertEqual(outcome.resolvedDelay, 0.5)
        XCTAssertTrue(native.appliedDelays.isEmpty)
        XCTAssertEqual(store.nativeDockAutoHideDelay, 0.5)
    }

    /// 在飞守卫是**共享**的：菜单和设置窗口各有一个「检查更新」入口，
    /// 各守各的会同时发两次请求。
    func testUpdateCheckGuardIsSharedAcrossBothEntryPoints() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.beginUpdateCheck())
        XCTAssertFalse(coordinator.beginUpdateCheck())
        XCTAssertFalse(coordinator.updateCheckState.presentation.isEnabled)

        coordinator.finishUpdateCheck()
        XCTAssertTrue(coordinator.updateCheckState.presentation.isEnabled)
        XCTAssertTrue(coordinator.beginUpdateCheck())
    }

    func testUpdateCheckFailureMapsToSharedFailureCopy() async {
        let updates = UpdateCheckerStub()
        updates.error = TestError.failed
        let coordinator = makeCoordinator(updates: updates)

        let content = await coordinator.performUpdateCheck()
        XCTAssertEqual(content, UpdateCheckAlertContent.failure)
        XCTAssertTrue(content.isWarning)
        XCTAssertEqual(updates.checkCount, 1)
    }

    private func makeCoordinator(
        store: AppSettingsStore? = nil,
        launch: LaunchServiceStub? = nil,
        native: NativeDockServiceStub? = nil,
        updates: UpdateCheckerStub? = nil
    ) -> SettingsCoordinator {
        SettingsCoordinator(
            store: store ?? makeStore(),
            launchAtLoginService: launch ?? LaunchServiceStub(state: .off),
            nativeDockPreferencesService: native ?? NativeDockServiceStub(),
            updateChecker: updates ?? UpdateCheckerStub()
        )
    }

    private func makeStore(
        launchAtLogin: Bool = false,
        nativeDelay: Double = AppSettingsStore.defaultNativeDockAutoHideDelay
    ) -> AppSettingsStore {
        let suite = "SettingsCoordinatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(launchAtLogin, forKey: "com.tungsten.edge.launchAtLogin")
        defaults.set(nativeDelay, forKey: "com.tungsten.edge.autoHide.nativeDock.delay")
        return AppSettingsStore(defaults: defaults)
    }
}

@MainActor
private final class LaunchServiceStub: LaunchAtLoginServicing {
    var state: LaunchAtLoginState
    var stateAfterSet: LaunchAtLoginState?
    var setError: Error?

    init(state: LaunchAtLoginState) {
        self.state = state
    }

    func setEnabled(_ enabled: Bool) throws {
        if let setError { throw setError }
        state = stateAfterSet ?? (enabled ? .on : .off)
    }

    func openSystemSettings() {}
}

@MainActor
private final class NativeDockServiceStub: NativeDockPreferencesServicing {
    let isAvailable: Bool
    var states: [NativeDockAutohideState?]
    var applyError: Error?
    var appliedDelays: [Double] = []

    init(isAvailable: Bool = true, states: [NativeDockAutohideState?] = []) {
        self.isAvailable = isAvailable
        self.states = states
    }

    func apply(delay: Double) throws {
        appliedDelays.append(delay)
        if let applyError { throw applyError }
    }

    func currentAutohideState() -> NativeDockAutohideState? {
        states.isEmpty ? nil : states.removeFirst()
    }

    func openSystemSettings() -> Bool { true }
}

private final class UpdateCheckerStub: UpdateChecking, @unchecked Sendable {
    var outcome: UpdateCheckOutcome?
    var error: Error?
    private(set) var checkCount = 0

    func check(currentVersion: String) async throws -> UpdateCheckOutcome {
        checkCount += 1
        if let error { throw error }
        return outcome ?? .upToDate(currentVersion: currentVersion, latestVersion: currentVersion)
    }
}

private enum TestError: Error {
    case failed
}
