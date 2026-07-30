import AppKit
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
    func testShowShelfDefaultsToOnAndPersists() {
        let defaults = makeDefaults()
        XCTAssertTrue(AppSettingsStore(defaults: defaults).showShelf, "默认显示中转格，升级不改变现有观感")

        let store = AppSettingsStore(defaults: defaults)
        store.setShowShelf(false)
        XCTAssertFalse(store.showShelf)
        XCTAssertFalse(AppSettingsStore(defaults: defaults).showShelf, "关掉后要跨重启保持")

        store.setShowShelf(true)
        XCTAssertTrue(AppSettingsStore(defaults: defaults).showShelf)
    }

    @MainActor
    func testDockSizeDefaultsToMediumAndPersists() {
        let defaults = makeDefaults()
        XCTAssertEqual(AppSettingsStore(defaults: defaults).dockSize, .medium)

        let store = AppSettingsStore(defaults: defaults)
        store.setDockSize(.extraLarge)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).dockSize, .extraLarge, "档位要跨重启保持")
    }

    @MainActor
    func testDockSizeRewritesCorruptStoredValueToMedium() {
        let defaults = makeDefaults()
        defaults.set("gigantic", forKey: "com.tungsten.edge.dockSize")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).dockSize, .medium)
        // 必须**立刻重写**，否则每次启动都要重走一遍回退，存值和 UI 勾选也一直对不上。
        XCTAssertEqual(defaults.string(forKey: "com.tungsten.edge.dockSize"), DockSize.medium.rawValue)

        defaults.set(42, forKey: "com.tungsten.edge.dockSize")
        XCTAssertEqual(AppSettingsStore(defaults: defaults).dockSize, .medium, "类型不对也要回退")
    }

    func testDockSizeRawValuesAreStableAcrossReleases() {
        // raw value 进了 UserDefaults，改名等于把所有老用户的档位悄悄重置成中档。
        XCTAssertEqual(DockSize.allCases.map(\.rawValue), ["small", "medium", "large", "extraLarge"])
        XCTAssertEqual(DockSize.allCases.map(\.title), ["小", "中", "大", "特大"])
    }

    @MainActor
    func testNativeDockSliderCommandsCoverResidentFiniteAndNeverWake() {
        // 常驻档只关 autohide，不写延迟——此时延迟没有意义，写了反而覆盖用户原值。
        let resident = NativeDockPreferencesService.commands(for: AppSettingsStore.neverHideDelay)
        XCTAssertEqual(resident.count, 2)
        XCTAssertEqual(resident[0].executable, "/usr/bin/defaults")
        XCTAssertEqual(resident[0].arguments, ["write", "com.apple.dock", "autohide", "-bool", "false"])
        XCTAssertEqual(resident[1].arguments, ["Dock"])

        let finite = NativeDockPreferencesService.commands(for: 0.5)
        XCTAssertEqual(finite.count, 3)
        XCTAssertEqual(finite[0].arguments, ["write", "com.apple.dock", "autohide", "-bool", "true"])
        XCTAssertEqual(finite[1].arguments, ["write", "com.apple.dock", "autohide-delay", "-float", "0.5"])
        XCTAssertEqual(finite[2].arguments, ["Dock"])

        let neverWake = NativeDockPreferencesService.commands(for: AppSettingsStore.neverWakeDelay)
        XCTAssertEqual(neverWake[1].arguments, ["write", "com.apple.dock", "autohide-delay", "-float", "999.0"])
    }

    @MainActor
    func testNativeDockCommandPathNeverWritesAutohideDelay() throws {
        var ranCommands: [(String, [String])] = []
        let service = NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: false),
            runner: { executable, arguments in ranCommands.append((executable, arguments)) },
            autohideReader: { NativeDockAutohideState(enabled: false, delay: 0.75) }
        )

        try service.setAutohideEnabled(true)
        try service.setAutohideEnabled(false)

        XCTAssertEqual(ranCommands.map(\.0), [
            "/usr/bin/defaults", "/usr/bin/killall",
            "/usr/bin/defaults", "/usr/bin/killall",
        ])
        XCTAssertEqual(ranCommands[0].1, ["write", "com.apple.dock", "autohide", "-bool", "true"])
        XCTAssertEqual(ranCommands[2].1, ["write", "com.apple.dock", "autohide", "-bool", "false"])
        XCTAssertFalse(
            ranCommands.contains { $0.1.contains("autohide-delay") },
            "菜单显隐命令必须严格等价 ⌥⌘D：碰了 autohide-delay 就等于顺手改掉用户的唤醒延迟"
        )
    }

    @MainActor
    func testNativeDockPreferenceServiceDoesNotRunWhenSandboxed() {
        var didRun = false
        let service = NativeDockPreferencesService(sandbox: SandboxEnvironment(isSandboxed: true)) { _, _ in
            didRun = true
        }

        XCTAssertFalse(service.isAvailable)
        XCTAssertThrowsError(try service.setAutohideEnabled(true))
        XCTAssertThrowsError(try service.apply(delay: 0.5))
        XCTAssertFalse(didRun)
    }

    @MainActor
    func testNativeDockSliderApplyStopsAtFirstFailedCommand() {
        var ranCommands: [(String, [String])] = []
        let service = NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: false),
            runner: { executable, arguments in
                ranCommands.append((executable, arguments))
                if arguments.contains("autohide-delay") {
                    throw NativeDockPreferencesError.commandFailed(executable: executable, status: 1)
                }
            },
            autohideReader: { nil }
        )

        XCTAssertThrowsError(try service.apply(delay: 0.5))
        XCTAssertEqual(ranCommands.count, 2, "第二条失败后不得继续 killall Dock")
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

    func testNativeToggleTitlePrefersLiveAutohideStateOverStore() {
        // live 可读：以 live 为准，存值被无视。
        XCTAssertEqual(
            AutoHideToggleMenuModel.nativeTitle(liveAutohide: true, storeDelay: AppSettingsStore.neverHideDelay),
            "显示系统 Dock"
        )
        XCTAssertEqual(
            AutoHideToggleMenuModel.nativeTitle(liveAutohide: false, storeDelay: 999),
            "隐藏系统 Dock"
        )
        // live 读不到：回退存值推导。
        XCTAssertEqual(AutoHideToggleMenuModel.nativeTitle(liveAutohide: nil, storeDelay: 0.5), "显示系统 Dock")
        XCTAssertEqual(
            AutoHideToggleMenuModel.nativeTitle(liveAutohide: nil, storeDelay: AppSettingsStore.neverHideDelay),
            "隐藏系统 Dock"
        )
        XCTAssertEqual(
            AutoHideToggleMenuModel.nativeTitle(liveAutohide: nil, storeDelay: AppSettingsStore.neverWakeDelay),
            "显示系统 Dock",
            "不唤醒也是自动隐藏的一档，命令方向仍是「显示」"
        )
    }

    func testNativeToggleTargetDirectionComesFromEffectiveAutohideState() {
        XCTAssertFalse(AutoHideToggleMenuModel.nativeToggleTargetEnabled(
            liveAutohide: true,
            storeDelay: AppSettingsStore.neverHideDelay
        ))
        XCTAssertTrue(AutoHideToggleMenuModel.nativeToggleTargetEnabled(liveAutohide: false, storeDelay: 1.0))
        // live 读不到 → 按存值方向翻。
        XCTAssertFalse(AutoHideToggleMenuModel.nativeToggleTargetEnabled(liveAutohide: nil, storeDelay: 999))
        XCTAssertTrue(AutoHideToggleMenuModel.nativeToggleTargetEnabled(
            liveAutohide: nil,
            storeDelay: AppSettingsStore.neverHideDelay
        ))
    }

    func testNativeDockMenuActionSkipsOnlyTheExactSystemShortcutKeyDown() {
        // 菜单开着按 ⌥⌘D：macOS 已经处理过一次，菜单 action 必须跳过，否则等于连按两下。
        XCTAssertTrue(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .keyDown,
            keyCode: UInt16(GlobalHotKeyShortcut.nativeDockAutoHide.keyCode),
            modifierFlags: [.option, .command],
            isSystemShortcutAvailable: true
        ))
        // 鼠标点击照常执行。
        XCTAssertFalse(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .leftMouseUp,
            keyCode: nil,
            modifierFlags: [],
            isSystemShortcutAvailable: true
        ))
        // 修饰键不完全一致 → 不是那条系统快捷键。
        XCTAssertFalse(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .keyDown,
            keyCode: UInt16(GlobalHotKeyShortcut.nativeDockAutoHide.keyCode),
            modifierFlags: [.option, .shift, .command],
            isSystemShortcutAvailable: true
        ))
        // 别的键。
        XCTAssertFalse(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .keyDown,
            keyCode: 0,
            modifierFlags: [.option, .command],
            isSystemShortcutAvailable: true
        ))
        // 系统快捷键不可用时不跳过，否则命令会完全点不动。
        XCTAssertFalse(AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: .keyDown,
            keyCode: UInt16(GlobalHotKeyShortcut.nativeDockAutoHide.keyCode),
            modifierFlags: [.option, .command],
            isSystemShortcutAvailable: false
        ))
    }

    func testResolvedStoreDelayCoversWriteAndReadQuadrants() {
        let target = 0.5
        let previous = AppSettingsStore.neverHideDelay

        // 系统可读 → 一律以系统真值为准，与写入是否成功无关。
        XCTAssertEqual(
            AutoHideToggleMenuModel.resolvedStoreDelay(
                writeSucceeded: true,
                systemState: NativeDockAutohideState(enabled: true, delay: 0.5),
                target: target,
                previous: previous
            ),
            0.5
        )
        XCTAssertEqual(
            AutoHideToggleMenuModel.resolvedStoreDelay(
                writeSucceeded: false,
                systemState: NativeDockAutohideState(enabled: true, delay: 0.5),
                target: target,
                previous: previous
            ),
            0.5,
            "多步写入可能已部分生效，读得到就按读到的来"
        )
        // 写成功但读不回来 → 保留 target。回滚会让 UI 和已经生效的系统设置相反。
        XCTAssertEqual(
            AutoHideToggleMenuModel.resolvedStoreDelay(
                writeSucceeded: true,
                systemState: nil,
                target: target,
                previous: previous
            ),
            target
        )
        // 写失败又读不回来 → 只能整体退回改动前。
        XCTAssertEqual(
            AutoHideToggleMenuModel.resolvedStoreDelay(
                writeSucceeded: false,
                systemState: nil,
                target: target,
                previous: previous
            ),
            previous
        )
    }

    func testPreferenceSliderCommitIsConsumedExactlyOnce() {
        var tracker = PreferenceSliderCommitTracker()
        tracker.begin(currentDelay: 0.5)
        tracker.stage(1.0)
        // 拖动过程中反复 begin 不得覆盖起点，否则 previous 变成中间值。
        tracker.begin(currentDelay: 0.9)
        tracker.stage(1.5)

        let first = tracker.consume()
        XCTAssertEqual(first?.previous, 0.5)
        XCTAssertEqual(first?.target, 1.5)
        // 松手、debounce timer、菜单关闭三个触发源都会调 consume，只有第一个拿得到值，
        // 否则每多一次就多一遍 defaults 写入 + killall Dock。
        XCTAssertNil(tracker.consume())
        XCTAssertNil(tracker.consume())
    }

    func testPreferenceSliderCommitSkipsUnchangedAndUnstartedAdjustments() {
        var unchanged = PreferenceSliderCommitTracker()
        unchanged.begin(currentDelay: 0.5)
        unchanged.stage(0.5)
        XCTAssertNil(unchanged.consume(), "值没变不该写系统")

        var neverStarted = PreferenceSliderCommitTracker()
        neverStarted.stage(1.0)
        XCTAssertNil(neverStarted.consume(), "没有起点就没有 previous，不能提交")

        // 消费过之后重新开一轮仍然正常工作。
        var reused = PreferenceSliderCommitTracker()
        reused.begin(currentDelay: 0.2)
        reused.stage(0.4)
        XCTAssertNotNil(reused.consume())
        reused.begin(currentDelay: 0.4)
        reused.stage(0.8)
        XCTAssertEqual(reused.consume()?.previous, 0.4)
    }

    func testToggleMenuKeyEquivalentShownOnlyWhenHotKeyRegistered() {
        let shortcut = GlobalHotKeyShortcut.edgeAutoHideMode

        let shown = AutoHideToggleMenuModel.keyEquivalentPresentation(isHotKeyRegistered: true, shortcut: shortcut)
        XCTAssertEqual(shown.key, "d")
        XCTAssertEqual(shown.mask, [.option, .shift, .command])

        let hidden = AutoHideToggleMenuModel.keyEquivalentPresentation(isHotKeyRegistered: false, shortcut: shortcut)
        XCTAssertEqual(hidden.key, "")
        XCTAssertEqual(hidden.mask, [])

        // 系统 Dock 行传 true：⌥⌘D 归 macOS，没有注册环节，提示恒显示。
        let native = AutoHideToggleMenuModel.keyEquivalentPresentation(
            isHotKeyRegistered: true,
            shortcut: .nativeDockAutoHide
        )
        XCTAssertEqual(native.key, "d")
        XCTAssertEqual(native.mask, [.option, .command])
        XCTAssertNotEqual(
            GlobalHotKeyShortcut.nativeDockAutoHide.id,
            GlobalHotKeyShortcut.edgeAutoHideMode.id,
            "两条快捷键共用 signature，id 必须不同"
        )
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

    func testOpenSystemDockSettingsUsesDeepLinkFirst() {
        var openedURLs: [URL] = []
        let service = NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: false),
            runner: { _, _ in },
            autohideReader: { nil },
            urlOpener: { url in
                openedURLs.append(url)
                return true
            }
        )

        XCTAssertTrue(service.openSystemSettings())
        XCTAssertEqual(openedURLs.map(\.absoluteString), ["x-apple.systempreferences:com.apple.preference.dock"])
    }

    func testOpenSystemDockSettingsFallsBackToPreferencePane() {
        var openedURLs: [URL] = []
        let service = NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: false),
            runner: { _, _ in },
            autohideReader: { nil },
            urlOpener: { url in
                openedURLs.append(url)
                return url.isFileURL
            }
        )

        XCTAssertTrue(service.openSystemSettings())
        XCTAssertEqual(openedURLs.count, 2)
        XCTAssertEqual(openedURLs[0].absoluteString, "x-apple.systempreferences:com.apple.preference.dock")
        XCTAssertEqual(openedURLs[1].path, "/System/Library/PreferencePanes/Dock.prefPane")
    }

    func testOpenSystemDockSettingsReportsFailureAfterBothAttempts() {
        let service = NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: false),
            runner: { _, _ in },
            autohideReader: { nil },
            urlOpener: { _ in false }
        )

        XCTAssertFalse(service.openSystemSettings())
    }

    func testOpenSystemDockSettingsIsNotBlockedBySandboxWriteGate() {
        var openedURLs: [URL] = []
        let service = NativeDockPreferencesService(
            sandbox: SandboxEnvironment(isSandboxed: true),
            runner: { _, _ in },
            autohideReader: { nil },
            urlOpener: { url in
                openedURLs.append(url)
                return true
            }
        )

        XCTAssertFalse(service.isAvailable)
        XCTAssertTrue(service.openSystemSettings())
        XCTAssertEqual(openedURLs.count, 1)
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
