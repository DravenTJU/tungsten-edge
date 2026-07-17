import AppKit
import Carbon.HIToolbox
import XCTest

@MainActor
final class AppSettingsStoreTests: XCTestCase {
    func testFreshDefaultsKeepFiniteDelaysWhenLegacyEnabledKeysAreMissing() {
        let defaults = makeDefaults()

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.nativeDockAutoHideDelay, 1.0)
        XCTAssertEqual(store.edgeAutoHideDelay, 0.1)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(store.nativeDockAutoHideDelay), 10)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(store.edgeAutoHideDelay), 1)
        XCTAssertNil(defaults.object(forKey: "com.tungsten.edge.autoHide.nativeDock.enabled"))
        XCTAssertNil(defaults.object(forKey: "com.tungsten.edge.autoHide.edge.enabled"))
    }

    func testLegacyDisabledEnabledKeyMigratesToNeverHideOnlyWhenKeyExists() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "com.tungsten.edge.autoHide.nativeDock.enabled")
        defaults.set(0.0, forKey: "com.tungsten.edge.autoHide.nativeDock.delay")

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.nativeDockAutoHideDelay, AppSettingsStore.neverHideDelay)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(store.nativeDockAutoHideDelay), 0)
        XCTAssertNil(defaults.object(forKey: "com.tungsten.edge.autoHide.nativeDock.enabled"))
    }

    func testLegacyEnabledTrueWithZeroDelaySnapsToFiniteMinimum() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "com.tungsten.edge.autoHide.nativeDock.enabled")
        defaults.set(0.0, forKey: "com.tungsten.edge.autoHide.nativeDock.delay")

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.nativeDockAutoHideDelay, AppSettingsStore.finiteDelayMin)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(store.nativeDockAutoHideDelay), 1)
        XCTAssertNil(defaults.object(forKey: "com.tungsten.edge.autoHide.nativeDock.enabled"))
    }

    func testLegacyEnabledTrueWithSubMinimumDelaySnapsToFiniteMinimum() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "com.tungsten.edge.autoHide.edge.enabled")
        defaults.set(0.05, forKey: "com.tungsten.edge.autoHide.edge.delay")

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.edgeAutoHideDelay, AppSettingsStore.finiteDelayMin)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(store.edgeAutoHideDelay), 1)
        XCTAssertNil(defaults.object(forKey: "com.tungsten.edge.autoHide.edge.enabled"))
    }

    func testSliderDelayMappingKeepsSubMinimumSecondsDistinctFromNeverHide() {
        XCTAssertEqual(AppSettingsStore.delayFromSliderIndex(0), AppSettingsStore.neverHideDelay)
        XCTAssertEqual(AppSettingsStore.delayFromSliderIndex(1), AppSettingsStore.finiteDelayMin)
        XCTAssertEqual(AppSettingsStore.delayFromSliderIndex(30), AppSettingsStore.finiteDelayMax)
        XCTAssertEqual(AppSettingsStore.delayFromSliderIndex(31), AppSettingsStore.neverWakeDelay)

        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(-99.0), 0)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(AppSettingsStore.neverHideDelay), 0)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(0.0), 1)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(0.3), 3)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(1.0), 10)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(3.0), 30)
        XCTAssertEqual(AppSettingsStore.sliderIndexFromDelay(AppSettingsStore.neverWakeDelay), 31)
    }

    func testSnapDelayClampsOnlySentinelBoundsToSpecialStates() {
        XCTAssertEqual(AppSettingsStore.snapDelay(-99.0), AppSettingsStore.neverHideDelay)
        XCTAssertEqual(AppSettingsStore.snapDelay(-0.2), AppSettingsStore.finiteDelayMin)
        XCTAssertEqual(AppSettingsStore.snapDelay(0.0), AppSettingsStore.finiteDelayMin)
        XCTAssertEqual(AppSettingsStore.snapDelay(0.05), AppSettingsStore.finiteDelayMin)
        XCTAssertEqual(AppSettingsStore.snapDelay(0.3), 0.3)
        XCTAssertEqual(AppSettingsStore.snapDelay(3.3), AppSettingsStore.finiteDelayMax)
        XCTAssertEqual(AppSettingsStore.snapDelay(999.0), AppSettingsStore.neverWakeDelay)
        XCTAssertEqual(AppSettingsStore.snapDelay(1.34), 1.3)
    }

    @MainActor
    func testNativeDockVisibilityCommandsDisableAutohideWithoutTouchingDelay() {
        let commands = NativeDockPreferencesService.commands(autohideEnabled: false)

        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0].executable, "/usr/bin/defaults")
        XCTAssertEqual(commands[0].arguments, ["write", "com.apple.dock", "autohide", "-bool", "false"])
        XCTAssertEqual(commands[1].arguments, ["Dock"])
        XCTAssertFalse(commands.flatMap(\.arguments).contains("autohide-delay"))
    }

    @MainActor
    func testNativeDockVisibilityCommandsEnableAutohideWithoutTouchingDelay() {
        let commands = NativeDockPreferencesService.commands(autohideEnabled: true)

        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands[0].arguments, ["write", "com.apple.dock", "autohide", "-bool", "true"])
        XCTAssertEqual(commands[1].arguments, ["Dock"])
        XCTAssertFalse(commands.flatMap(\.arguments).contains("autohide-delay"))
    }

    @MainActor
    func testNativeDockPreferenceServiceDoesNotRunWhenSandboxed() {
        var didRun = false
        let service = NativeDockPreferencesService(sandbox: SandboxEnvironment(isSandboxed: true)) { _, _ in
            didRun = true
        }

        XCTAssertFalse(service.isAvailable)
        XCTAssertThrowsError(try service.setAutohideEnabled(true))
        XCTAssertFalse(didRun)
    }

    @MainActor
    func testNativeDockPreferenceServiceRunsMappedCommandsWhenAvailable() throws {
        var ranCommands: [(String, [String])] = []
        let service = NativeDockPreferencesService(sandbox: SandboxEnvironment(isSandboxed: false)) { executable, arguments in
            ranCommands.append((executable, arguments))
        }

        try service.setAutohideEnabled(true)

        XCTAssertTrue(service.isAvailable)
        XCTAssertEqual(ranCommands.map(\.0), ["/usr/bin/defaults", "/usr/bin/killall"])
        XCTAssertEqual(ranCommands[0].1, ["write", "com.apple.dock", "autohide", "-bool", "true"])
    }

    func testNativeDockStateReadStopsBeforeValueAccessWhenSynchronizeFails() {
        var requestedKeys: [String] = []

        let state = NativeDockPreferencesService.readAutohideState(
            synchronize: { false },
            valueForKey: { key in
                requestedKeys.append(key)
                return nil
            }
        )

        XCTAssertNil(state)
        XCTAssertTrue(requestedKeys.isEmpty)
    }

    func testNativeDockStateDecoderDistinguishesMissingKeysFromCorruptValues() {
        XCTAssertEqual(
            NativeDockPreferencesService.decodeAutohideState(autohideValue: nil, delayValue: nil),
            NativeDockAutohideState(enabled: false, delay: nil)
        )
        XCTAssertEqual(
            NativeDockPreferencesService.decodeAutohideState(autohideValue: true, delayValue: 0.2),
            NativeDockAutohideState(enabled: true, delay: 0.2)
        )
        XCTAssertEqual(
            NativeDockPreferencesService.decodeAutohideState(autohideValue: nil, delayValue: 0.2),
            NativeDockAutohideState(enabled: false, delay: 0.2)
        )
        XCTAssertEqual(
            NativeDockPreferencesService.decodeAutohideState(autohideValue: false, delayValue: "bad"),
            NativeDockAutohideState(enabled: false, delay: nil),
            "系统明确关闭时，坏 delay 不得掩盖可信的 autohide 真值"
        )

        XCTAssertNil(NativeDockPreferencesService.decodeAutohideState(autohideValue: "true", delayValue: 0.2))
        XCTAssertNil(NativeDockPreferencesService.decodeAutohideState(autohideValue: NSNumber(value: 1), delayValue: 0.2))
        XCTAssertNil(NativeDockPreferencesService.decodeAutohideState(autohideValue: true, delayValue: "0.2"))
        XCTAssertNil(NativeDockPreferencesService.decodeAutohideState(autohideValue: true, delayValue: false))
        XCTAssertNil(NativeDockPreferencesService.decodeAutohideState(
            autohideValue: true,
            delayValue: NSNumber(value: Double.nan)
        ))
        XCTAssertNil(NativeDockPreferencesService.decodeAutohideState(
            autohideValue: true,
            delayValue: NSNumber(value: Double.infinity)
        ))
    }

    func testLaunchAtLoginMenuPresentationCoversFourStates() {
        XCTAssertEqual(
            LaunchAtLoginMenuPresentation(state: .unsupported),
            LaunchAtLoginMenuPresentation(title: "登录时启动（macOS 13+）", isEnabled: false, isChecked: false, showsSettingsItem: false)
        )
        XCTAssertEqual(
            LaunchAtLoginMenuPresentation(state: .off),
            LaunchAtLoginMenuPresentation(title: "登录时启动", isEnabled: true, isChecked: false, showsSettingsItem: false)
        )
        XCTAssertEqual(
            LaunchAtLoginMenuPresentation(state: .on),
            LaunchAtLoginMenuPresentation(title: "登录时启动", isEnabled: true, isChecked: true, showsSettingsItem: false)
        )
        XCTAssertEqual(
            LaunchAtLoginMenuPresentation(state: .requiresApproval),
            LaunchAtLoginMenuPresentation(title: "登录时启动（待批准）", isEnabled: true, isChecked: false, showsSettingsItem: true)
        )
    }

    func testLaunchAtLoginMenuToggleDecisionCoversFourStates() {
        XCTAssertNil(LaunchAtLoginMenuModel.requestedEnabledValue(afterSelecting: .unsupported))
        XCTAssertEqual(LaunchAtLoginMenuModel.requestedEnabledValue(afterSelecting: .off), true)
        XCTAssertEqual(LaunchAtLoginMenuModel.requestedEnabledValue(afterSelecting: .on), false)
        XCTAssertEqual(LaunchAtLoginMenuModel.requestedEnabledValue(afterSelecting: .requiresApproval), true)
    }

    func testLaunchAtLoginColdStartPresentationUsesRealStatusOverStoredIntent() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "com.tungsten.edge.launchAtLogin")
        let store = AppSettingsStore(defaults: defaults)

        let presentation = LaunchAtLoginMenuPresentation(state: .off)

        XCTAssertTrue(store.launchAtLogin)
        XCTAssertFalse(presentation.isChecked)
    }

    func testPanelVisibilityKeepsHiddenUntilAllReasonsAreCleared() {
        var state = PanelVisibilityState()

        state.setFullscreen(true)
        state.setEdgeAutoHidden(true)
        XCTAssertFalse(state.isVisible)

        state.setFullscreen(false)
        XCTAssertFalse(state.isVisible)

        state.setEdgeAutoHidden(false)
        XCTAssertTrue(state.isVisible)
    }

    func testPanelVisibilityInhibitorClearsEdgeAutoHideEvenAfterFullscreenExit() {
        var state = PanelVisibilityState()

        state.setEdgeAutoHidden(true)
        state.setFullscreen(true)
        state.setInhibitor(.dragging, active: true)
        state.setFullscreen(false)
        state.reconcileEdgeAutoHide(isEnabled: true)

        XCTAssertFalse(state.hideReasons.contains(.edgeAutoHide))
        XCTAssertTrue(state.isVisible)
    }

    func testPanelVisibilityConstantModeClearsEdgeAutoHide() {
        var state = PanelVisibilityState()

        state.setEdgeAutoHidden(true)
        state.reconcileEdgeAutoHide(isEnabled: false)

        XCTAssertTrue(state.isVisible)
    }

    func testEdgeAutoHideWakeRulesRequireHiddenFiniteDelayAndNoInhibitors() {
        var state = PanelVisibilityState()

        XCTAssertFalse(EdgeAutoHideRuntimeRules.canArmWake(state: state, delay: 0.9))

        state.setEdgeAutoHidden(true)
        XCTAssertTrue(EdgeAutoHideRuntimeRules.canArmWake(state: state, delay: 0.9))
        XCTAssertFalse(EdgeAutoHideRuntimeRules.canArmWake(state: state, delay: AppSettingsStore.neverWakeDelay))
        XCTAssertFalse(EdgeAutoHideRuntimeRules.canArmWake(state: state, delay: AppSettingsStore.neverHideDelay))

        state.setInhibitor(.drawerOpen, active: true)
        XCTAssertFalse(EdgeAutoHideRuntimeRules.canArmWake(state: state, delay: 0.9))
    }

    func testEdgeAutoHideIdleRulesRequireVisibleAndNoInhibitors() {
        var state = PanelVisibilityState()

        XCTAssertTrue(EdgeAutoHideRuntimeRules.canArmIdleHide(state: state, delay: 0.9))
        XCTAssertEqual(EdgeAutoHideRuntimeRules.idleHideInterval(for: 0.9), EdgeAutoHideRuntimeRules.fixedIdleHideDelay)
        XCTAssertEqual(EdgeAutoHideRuntimeRules.idleHideInterval(for: AppSettingsStore.neverWakeDelay), EdgeAutoHideRuntimeRules.fixedIdleHideDelay)
        XCTAssertNil(EdgeAutoHideRuntimeRules.idleHideInterval(for: AppSettingsStore.neverHideDelay))

        state.setEdgeAutoHidden(true)
        XCTAssertFalse(EdgeAutoHideRuntimeRules.canArmIdleHide(state: state, delay: 0.9))

        state.setEdgeAutoHidden(false)
        state.setInhibitor(.dragging, active: true)
        XCTAssertFalse(EdgeAutoHideRuntimeRules.canArmIdleHide(state: state, delay: 0.9))
    }

    func testBottomHotZoneSuppressesIdleHideOnlyForFiniteWakeDelays() {
        XCTAssertTrue(EdgeAutoHideRuntimeRules.bottomHotZoneSuppressesIdleHide(delay: 0.1))
        XCTAssertTrue(EdgeAutoHideRuntimeRules.bottomHotZoneSuppressesIdleHide(delay: 0.9))
        XCTAssertTrue(EdgeAutoHideRuntimeRules.bottomHotZoneSuppressesIdleHide(delay: 3.0))

        // 999：自动隐藏但不唤醒——没有唤醒动作就没有"打架"风险，底边热区不该额外压住隐藏。
        XCTAssertFalse(EdgeAutoHideRuntimeRules.bottomHotZoneSuppressesIdleHide(delay: AppSettingsStore.neverWakeDelay))

        // -1：常驻显示——本来就不会隐藏，压不压都一样，规则仍应返回 false（不代表要生效）。
        XCTAssertFalse(EdgeAutoHideRuntimeRules.bottomHotZoneSuppressesIdleHide(delay: AppSettingsStore.neverHideDelay))
    }

    // MARK: - 常驻切换（toggleEdgeAutoHideMode）与 remembered 播种

    func testToggleFromFiniteDelayEntersResidentAndRestoresSameDelay() {
        let defaults = makeDefaults()
        defaults.set(0.5, forKey: "com.tungsten.edge.autoHide.edge.delay")
        let store = AppSettingsStore(defaults: defaults)

        store.toggleEdgeAutoHideMode()
        XCTAssertEqual(store.edgeAutoHideDelay, AppSettingsStore.neverHideDelay)
        XCTAssertEqual(store.lastEnabledEdgeAutoHideDelay, 0.5)

        store.toggleEdgeAutoHideMode()
        XCTAssertEqual(store.edgeAutoHideDelay, 0.5)
    }

    func testToggleFromNeverWakeRoundTripsBackToNeverWake() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.setEdgeAutoHideDelay(AppSettingsStore.neverWakeDelay)

        store.toggleEdgeAutoHideMode()
        XCTAssertEqual(store.edgeAutoHideDelay, AppSettingsStore.neverHideDelay)

        store.toggleEdgeAutoHideMode()
        XCTAssertEqual(store.edgeAutoHideDelay, AppSettingsStore.neverWakeDelay)
    }

    func testToggleFromResidentWithoutHistoryFallsBackToDefaultDelay() {
        let defaults = makeDefaults()
        defaults.set(AppSettingsStore.neverHideDelay, forKey: "com.tungsten.edge.autoHide.edge.delay")
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.lastEnabledEdgeAutoHideDelay, AppSettingsStore.defaultEdgeAutoHideDelay)

        store.toggleEdgeAutoHideMode()
        XCTAssertEqual(store.edgeAutoHideDelay, AppSettingsStore.defaultEdgeAutoHideDelay)
    }

    func testRememberedSeedsFromCurrentFiniteValueOverStaleStoredValue() {
        let defaults = makeDefaults()
        defaults.set(0.5, forKey: "com.tungsten.edge.autoHide.edge.delay")
        defaults.set(2.0, forKey: "com.tungsten.edge.autoHide.edge.lastEnabledDelay")

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.lastEnabledEdgeAutoHideDelay, 0.5)
        XCTAssertEqual(defaults.double(forKey: "com.tungsten.edge.autoHide.edge.lastEnabledDelay"), 0.5)
    }

    func testRememberedIsReadOnlyWhenCurrentIsResident() {
        let defaults = makeDefaults()
        defaults.set(AppSettingsStore.neverHideDelay, forKey: "com.tungsten.edge.autoHide.edge.delay")
        defaults.set(2.0, forKey: "com.tungsten.edge.autoHide.edge.lastEnabledDelay")

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.lastEnabledEdgeAutoHideDelay, 2.0)
    }

    func testCorruptRememberedValuesFallBackToDefault() {
        let corruptValues: [Any] = ["字符串", Double.nan, AppSettingsStore.neverHideDelay, -50.0]
        for corrupt in corruptValues {
            let defaults = makeDefaults()
            defaults.set(AppSettingsStore.neverHideDelay, forKey: "com.tungsten.edge.autoHide.edge.delay")
            defaults.set(corrupt, forKey: "com.tungsten.edge.autoHide.edge.lastEnabledDelay")

            let store = AppSettingsStore(defaults: defaults)

            XCTAssertEqual(store.lastEnabledEdgeAutoHideDelay, AppSettingsStore.defaultEdgeAutoHideDelay, "corrupt=\(corrupt)")
        }
    }

    func testLegacyDisabledMigrationThenToggleRestoresDefaultDelay() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "com.tungsten.edge.autoHide.edge.enabled")
        defaults.set(0.7, forKey: "com.tungsten.edge.autoHide.edge.delay")

        let store = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(store.edgeAutoHideDelay, AppSettingsStore.neverHideDelay)
        XCTAssertEqual(store.lastEnabledEdgeAutoHideDelay, AppSettingsStore.defaultEdgeAutoHideDelay)

        store.toggleEdgeAutoHideMode()
        XCTAssertEqual(store.edgeAutoHideDelay, AppSettingsStore.defaultEdgeAutoHideDelay)
    }

    func testCrossStoreRebuildKeepsRememberedDelay() {
        let defaults = makeDefaults()
        let first = AppSettingsStore(defaults: defaults)
        first.setEdgeAutoHideDelay(2.0)
        first.toggleEdgeAutoHideMode()
        XCTAssertEqual(first.edgeAutoHideDelay, AppSettingsStore.neverHideDelay)

        let second = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(second.edgeAutoHideDelay, AppSettingsStore.neverHideDelay)
        XCTAssertEqual(second.lastEnabledEdgeAutoHideDelay, 2.0)

        second.toggleEdgeAutoHideMode()
        XCTAssertEqual(second.edgeAutoHideDelay, 2.0)
    }

    func testNonFiniteSetterInputsAreIgnored() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)
        store.setEdgeAutoHideDelay(0.5)

        store.setEdgeAutoHideDelay(.nan)
        store.setEdgeAutoHideDelay(.infinity)
        store.setEdgeAutoHideDelay(-.infinity)
        store.setNativeDockAutoHideDelay(.nan)

        XCTAssertEqual(store.edgeAutoHideDelay, 0.5)
        XCTAssertEqual(store.lastEnabledEdgeAutoHideDelay, 0.5)
        XCTAssertEqual(store.nativeDockAutoHideDelay, AppSettingsStore.defaultNativeDockAutoHideDelay)
    }

    func testSnapDelayReturnsFallbackForNonFiniteInput() {
        XCTAssertEqual(AppSettingsStore.snapDelay(.nan), AppSettingsStore.defaultEdgeAutoHideDelay)
        XCTAssertEqual(AppSettingsStore.snapDelay(.infinity, fallbackForNonFinite: 1.0), 1.0)
        XCTAssertEqual(AppSettingsStore.snapDelay(-.infinity, fallbackForNonFinite: 2.0), 2.0)
    }

    func testStoredActiveDelayRejectsWrongTypesAndUsesPerGroupFallback() {
        XCTAssertEqual(AppSettingsStore.sanitizedStoredDelay("bad", fallback: 1.0), 1.0)
        XCTAssertEqual(AppSettingsStore.sanitizedStoredDelay(true, fallback: 1.0), 1.0)
        XCTAssertEqual(AppSettingsStore.sanitizedStoredDelay(NSNumber(value: Double.nan), fallback: 1.0), 1.0)
        XCTAssertEqual(AppSettingsStore.sanitizedStoredDelay(2.04, fallback: 1.0), 2.0)

        let defaults = makeDefaults()
        defaults.set("bad", forKey: "com.tungsten.edge.autoHide.nativeDock.delay")
        defaults.set(true, forKey: "com.tungsten.edge.autoHide.edge.delay")

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.nativeDockAutoHideDelay, AppSettingsStore.defaultNativeDockAutoHideDelay)
        XCTAssertEqual(store.edgeAutoHideDelay, AppSettingsStore.defaultEdgeAutoHideDelay)
        XCTAssertEqual(defaults.double(forKey: "com.tungsten.edge.autoHide.nativeDock.delay"), 1.0)
        XCTAssertEqual(defaults.double(forKey: "com.tungsten.edge.autoHide.edge.delay"), 0.1)
    }

    func testSanitizedLastEnabledDelayNeverReturnsResident() {
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(nil), AppSettingsStore.defaultEdgeAutoHideDelay)
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(.nan), AppSettingsStore.defaultEdgeAutoHideDelay)
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(AppSettingsStore.neverHideDelay), AppSettingsStore.defaultEdgeAutoHideDelay)
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(-50.0), AppSettingsStore.defaultEdgeAutoHideDelay)
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(0.05), AppSettingsStore.finiteDelayMin)
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(2.0), 2.0)
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(AppSettingsStore.neverWakeDelay), AppSettingsStore.neverWakeDelay)
    }

    // MARK: - 动态显隐命令纯逻辑

    func testEdgeToggleTitleDescribesNextModeAction() {
        XCTAssertEqual(
            AutoHideToggleMenuModel.edgeTitle(delay: AppSettingsStore.neverHideDelay),
            "隐藏 Tungsten Edge 钨极"
        )
        XCTAssertEqual(AutoHideToggleMenuModel.edgeTitle(delay: 0.5), "显示 Tungsten Edge 钨极")
        XCTAssertEqual(
            AutoHideToggleMenuModel.edgeTitle(delay: AppSettingsStore.neverWakeDelay),
            "显示 Tungsten Edge 钨极"
        )
    }

    @MainActor
    func testEdgeSliderIsCompactAndKeepsAccessibilityContext() {
        let view = PreferenceSliderMenuItemView(accessibilityTitle: "Tungsten Edge 钨极唤醒时间")
        view.sync(delay: 0.5)

        XCTAssertEqual(view.frame.height, 58)
        XCTAssertEqual(view.accessibilityLabel(), "Tungsten Edge 钨极唤醒时间，0.5s")
        XCTAssertEqual(view.accessibilityValue() as? String, "0.5s")
    }

    func testNativeToggleTitlePrefersLiveSystemStateOverStore() {
        // live 可读：以 live 为准，存值被无视。
        XCTAssertEqual(
            AutoHideToggleMenuModel.nativeTitle(liveAutohide: true, storeDelay: AppSettingsStore.neverHideDelay),
            "显示系统 Dock"
        )
        XCTAssertEqual(
            AutoHideToggleMenuModel.nativeTitle(liveAutohide: false, storeDelay: 1.0),
            "隐藏系统 Dock"
        )
        // live 读不到：回退存值推导。
        XCTAssertEqual(AutoHideToggleMenuModel.nativeTitle(liveAutohide: nil, storeDelay: 1.0), "显示系统 Dock")
        XCTAssertEqual(
            AutoHideToggleMenuModel.nativeTitle(liveAutohide: nil, storeDelay: AppSettingsStore.neverHideDelay),
            "隐藏系统 Dock"
        )
    }

    func testNativeToggleTargetDirectionComesFromEffectiveState() {
        // 实际开着（无论存值说什么）→ 目标是关；实际关着 → 目标是开。
        XCTAssertFalse(AutoHideToggleMenuModel.nativeToggleTargetEnabled(
            liveAutohide: true,
            storeDelay: AppSettingsStore.neverHideDelay
        ))
        XCTAssertTrue(AutoHideToggleMenuModel.nativeToggleTargetEnabled(
            liveAutohide: false,
            storeDelay: 1.0
        ))
        // live 读不到 → 按存值方向翻。
        XCTAssertFalse(AutoHideToggleMenuModel.nativeToggleTargetEnabled(liveAutohide: nil, storeDelay: 1.0))
        XCTAssertTrue(AutoHideToggleMenuModel.nativeToggleTargetEnabled(
            liveAutohide: nil,
            storeDelay: AppSettingsStore.neverHideDelay
        ))
    }

    func testToggleMenuKeyEquivalentShownOnlyWhenHotKeyRegistered() {
        let shortcut = GlobalHotKeyShortcut.edgeAutoHideMode

        let shown = AutoHideToggleMenuModel.keyEquivalentPresentation(isHotKeyRegistered: true, shortcut: shortcut)
        XCTAssertEqual(shown.key, "e")
        XCTAssertEqual(shown.mask, [.option, .command])

        let hidden = AutoHideToggleMenuModel.keyEquivalentPresentation(isHotKeyRegistered: false, shortcut: shortcut)
        XCTAssertEqual(hidden.key, "")
        XCTAssertEqual(hidden.mask, [])

        // 系统 Dock 行：⌥⌘D 恒生效，调用方恒传 true。
        let native = AutoHideToggleMenuModel.keyEquivalentPresentation(isHotKeyRegistered: true, shortcut: .nativeDockAutoHide)
        XCTAssertEqual(native.key, "d")
        XCTAssertEqual(native.mask, [.option, .command])
    }

    func testNativeDockMenuActionSkipsOnlyExactSystemShortcut() {
        let exactMask: NSEvent.ModifierFlags = [.option, .command]
        let keyE = UInt16(kVK_ANSI_E)
        let keyD = UInt16(kVK_ANSI_D)

        // 系统 ⌥⌘D 在菜单展开时仍有效：D 的精确 keyDown 跳过 menu action。
        XCTAssertTrue(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .keyDown, keyCode: keyD, modifierFlags: exactMask,
            isSystemShortcutAvailable: true
        ))

        // 鼠标点击、回车、修饰键不同、系统路径不可用——一律照常执行菜单 action。
        XCTAssertFalse(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .leftMouseUp, keyCode: nil, modifierFlags: [],
            isSystemShortcutAvailable: true
        ))
        XCTAssertFalse(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .keyDown, keyCode: UInt16(kVK_Return), modifierFlags: [],
            isSystemShortcutAvailable: true
        ))
        XCTAssertFalse(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .keyDown, keyCode: keyD, modifierFlags: [.command],
            isSystemShortcutAvailable: true
        ))
        XCTAssertFalse(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .keyDown, keyCode: keyD, modifierFlags: exactMask,
            isSystemShortcutAvailable: false
        ))

        // 物理键码而非字符决定系统路径去重，E 键不能误伤 D 行。
        XCTAssertFalse(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .keyDown, keyCode: keyE, modifierFlags: exactMask,
            isSystemShortcutAvailable: true
        ))
    }

    func testReconciledStoreDelayAlignsStoreWithSystemTruth() {
        // 系统关着：存值不是常驻就改成常驻；已是常驻则无需改动。
        XCTAssertEqual(
            AutoHideToggleMenuModel.reconciledStoreDelay(systemEnabled: false, systemDelay: nil, currentStoreDelay: 1.0),
            AppSettingsStore.neverHideDelay
        )
        XCTAssertNil(
            AutoHideToggleMenuModel.reconciledStoreDelay(systemEnabled: false, systemDelay: 0.5, currentStoreDelay: AppSettingsStore.neverHideDelay)
        )

        // 系统开着：对齐到系统延迟（吸附到合法档位）；键不存在用系统默认 0.5。
        XCTAssertEqual(
            AutoHideToggleMenuModel.reconciledStoreDelay(systemEnabled: true, systemDelay: 0.2, currentStoreDelay: AppSettingsStore.neverHideDelay),
            0.2
        )
        XCTAssertEqual(
            AutoHideToggleMenuModel.reconciledStoreDelay(systemEnabled: true, systemDelay: nil, currentStoreDelay: AppSettingsStore.neverHideDelay),
            AutoHideToggleMenuModel.systemDefaultAutohideDelay
        )
        // 999（不唤醒档）原样往返；0 吸附到最小档 0.1；已一致返回 nil。
        XCTAssertEqual(
            AutoHideToggleMenuModel.reconciledStoreDelay(systemEnabled: true, systemDelay: 999.0, currentStoreDelay: 1.0),
            AppSettingsStore.neverWakeDelay
        )
        XCTAssertEqual(
            AutoHideToggleMenuModel.reconciledStoreDelay(systemEnabled: true, systemDelay: 0.0, currentStoreDelay: 1.0),
            AppSettingsStore.finiteDelayMin
        )
        XCTAssertEqual(
            AutoHideToggleMenuModel.reconciledStoreDelay(systemEnabled: true, systemDelay: -1.0, currentStoreDelay: 1.0),
            AppSettingsStore.finiteDelayMin,
            "系统开关明确开启时，负 delay 不能被解释成 App 的常驻哨兵"
        )
        XCTAssertEqual(
            AutoHideToggleMenuModel.reconciledStoreDelay(systemEnabled: true, systemDelay: .nan, currentStoreDelay: 0.2),
            AppSettingsStore.defaultNativeDockAutoHideDelay
        )
        XCTAssertNil(
            AutoHideToggleMenuModel.reconciledStoreDelay(systemEnabled: true, systemDelay: 1.0, currentStoreDelay: 1.0)
        )
    }

    @MainActor
    func testNativeDockAutohideStateReadRespectsSandboxAndInjectedReader() {
        let sandboxed = NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: true),
            runner: { _, _ in },
            autohideReader: { NativeDockAutohideState(enabled: true, delay: 0.5) }
        )
        XCTAssertNil(sandboxed.currentAutohideState(), "沙箱下读不到，返回 nil 让调用方回退存值")

        let readable = NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: false),
            runner: { _, _ in },
            autohideReader: { NativeDockAutohideState(enabled: true, delay: 0.2) }
        )
        XCTAssertEqual(readable.currentAutohideState(), NativeDockAutohideState(enabled: true, delay: 0.2))
    }

    // MARK: - 系统 Dock 组 remembered 镜像

    func testNativeRememberedSeedsFromCurrentFiniteValueOverStaleStoredValue() {
        let defaults = makeDefaults()
        defaults.set(2.0, forKey: "com.tungsten.edge.autoHide.nativeDock.delay")
        defaults.set(0.5, forKey: "com.tungsten.edge.autoHide.nativeDock.lastEnabledDelay")

        let store = AppSettingsStore(defaults: defaults)

        XCTAssertEqual(store.lastEnabledNativeDockAutoHideDelay, 2.0)
        XCTAssertEqual(defaults.double(forKey: "com.tungsten.edge.autoHide.nativeDock.lastEnabledDelay"), 2.0)
    }

    func testNativeRememberedIsReadWhenCurrentIsResidentAndCorruptFallsBackToNativeDefault() {
        let defaults = makeDefaults()
        defaults.set(AppSettingsStore.neverHideDelay, forKey: "com.tungsten.edge.autoHide.nativeDock.delay")
        defaults.set(2.0, forKey: "com.tungsten.edge.autoHide.nativeDock.lastEnabledDelay")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).lastEnabledNativeDockAutoHideDelay, 2.0)

        let corrupted = makeDefaults()
        corrupted.set(AppSettingsStore.neverHideDelay, forKey: "com.tungsten.edge.autoHide.nativeDock.delay")
        corrupted.set(AppSettingsStore.neverHideDelay, forKey: "com.tungsten.edge.autoHide.nativeDock.lastEnabledDelay")
        // 回退值是 native 组自己的默认档位 1.0，不是 edge 的 0.1。
        XCTAssertEqual(AppSettingsStore(defaults: corrupted).lastEnabledNativeDockAutoHideDelay, AppSettingsStore.defaultNativeDockAutoHideDelay)
    }

    func testNativeSetterSyncsRememberedBeforeActiveDedup() {
        let defaults = makeDefaults()
        let store = AppSettingsStore(defaults: defaults)

        store.setNativeDockAutoHideDelay(2.0)
        XCTAssertEqual(store.lastEnabledNativeDockAutoHideDelay, 2.0)

        store.setNativeDockAutoHideDelay(AppSettingsStore.neverHideDelay)
        XCTAssertEqual(store.nativeDockAutoHideDelay, AppSettingsStore.neverHideDelay)
        XCTAssertEqual(store.lastEnabledNativeDockAutoHideDelay, 2.0, "写入常驻不动 remembered")

        let rebuilt = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(rebuilt.lastEnabledNativeDockAutoHideDelay, 2.0, "跨 Store 重建保留 remembered")
    }

    func testSanitizedLastEnabledDelayHonorsPerGroupFallback() {
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(nil, fallback: AppSettingsStore.defaultNativeDockAutoHideDelay), 1.0)
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(.nan, fallback: 1.0), 1.0)
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(AppSettingsStore.neverHideDelay, fallback: 1.0), 1.0)
        XCTAssertEqual(AppSettingsStore.sanitizedLastEnabledDelay(2.0, fallback: 1.0), 2.0)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "com.tungsten.edge.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
