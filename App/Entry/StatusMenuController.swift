import AppKit
import Combine

private enum StatusMenuLayout {
    static let textInsetX: CGFloat = 28
    static let trailingInsetX: CGFloat = 14
}

/// 两条动态显隐命令（系统 Dock + 钨极）的纯展示/去重决策（单测覆盖）。
@MainActor
enum AutoHideToggleMenuModel {
    static func isAutoHideEnabled(delay: Double) -> Bool {
        delay != AppSettingsStore.neverHideDelay
    }

    static func edgeTitle(delay: Double) -> String {
        isAutoHideEnabled(delay: delay)
            ? "显示 Tungsten Edge 钨极"
            : "隐藏 Tungsten Edge 钨极"
    }

    /// 系统 Dock 是否处于自动隐藏。优先读系统真值（用户随时可用 ⌥⌘D / 系统设置改），
    /// 读不到才回退本地镜像推导。
    static func nativeIsAutoHideEnabled(liveAutohide: Bool?, storeDelay: Double) -> Bool {
        liveAutohide ?? isAutoHideEnabled(delay: storeDelay)
    }

    static func nativeTitle(liveAutohide: Bool?, storeDelay: Double) -> String {
        nativeIsAutoHideEnabled(liveAutohide: liveAutohide, storeDelay: storeDelay)
            ? "显示系统 Dock"
            : "隐藏系统 Dock"
    }

    /// 命令翻转方向必须由**实际状态**（live 优先）决定，不能盲翻本地镜像——镜像可能已被外部改动甩在身后。
    static func nativeToggleTargetEnabled(liveAutohide: Bool?, storeDelay: Double) -> Bool {
        !nativeIsAutoHideEnabled(liveAutohide: liveAutohide, storeDelay: storeDelay)
    }

    /// 系统 ⌥⌘D 在菜单追踪期间仍由 macOS 处理；菜单 action 只跳过这一条精确 keyDown，
    /// 否则系统和菜单项各执行一次，等于连按两下。
    static func shouldSkipNativeDockMenuAction(eventType: NSEvent.EventType?,
                                               keyCode: UInt16?,
                                               modifierFlags: NSEvent.ModifierFlags,
                                               isSystemShortcutAvailable: Bool) -> Bool {
        guard isSystemShortcutAvailable,
              eventType == .keyDown else { return false }
        let shortcut = GlobalHotKeyShortcut.nativeDockAutoHide
        guard let keyCode, UInt32(keyCode) == shortcut.keyCode else { return false }
        let normalized = modifierFlags.intersection([.command, .option, .control, .shift])
        return normalized == shortcut.keyEquivalentModifierMask
    }

    /// autohide-delay 键不存在时系统 Dock 的实际默认延迟。
    static let systemDefaultAutohideDelay = 0.5

    /// 系统真值 → 本地镜像应有的档位值。
    static func storeDelay(systemEnabled: Bool, systemDelay: Double?) -> Double {
        guard systemEnabled else { return AppSettingsStore.neverHideDelay }
        let rawDelay = systemDelay ?? systemDefaultAutohideDelay
        // 系统开关已经明确为开；负 delay 只能视为外部自定义的极短延迟，
        // 不能穿透 snapDelay 被误解释成本 App 的「常驻」哨兵 -1。
        let enabledDelay = rawDelay.isFinite
            ? max(rawDelay, AppSettingsStore.finiteDelayMin)
            : AppSettingsStore.defaultNativeDockAutoHideDelay
        return AppSettingsStore.snapDelay(
            enabledDelay,
            fallbackForNonFinite: AppSettingsStore.defaultNativeDockAutoHideDelay
        )
    }

    /// 菜单打开时把系统实际状态回灌进本地镜像，让滑块、标题、点击方向从同一真值出发。
    /// 返回 nil = 已一致，无需改动。
    static func reconciledStoreDelay(systemEnabled: Bool, systemDelay: Double?, currentStoreDelay: Double) -> Double? {
        let target = storeDelay(systemEnabled: systemEnabled, systemDelay: systemDelay)
        return currentStoreDelay == target ? nil : target
    }

    /// 写系统之后本地镜像该落什么值。四象限，**不能一律「失败就回 previous」**：
    /// 写成功但读不回来时回滚，会让 UI 显示得和已经生效的系统设置相反。
    ///
    /// |            | 系统可读     | 系统不可读   |
    /// |------------|--------------|--------------|
    /// | **写成功** | 按读到的值   | 保留 target  |
    /// | **写失败** | 按读到的值（可能是部分写入的结果） | 保留 previous |
    static func resolvedStoreDelay(writeSucceeded: Bool,
                                   systemState: NativeDockAutohideState?,
                                   target: Double,
                                   previous: Double) -> Double {
        if let systemState {
            return storeDelay(systemEnabled: systemState.enabled, systemDelay: systemState.delay)
        }
        return writeSucceeded ? target : previous
    }

    /// keyEquivalent 提示只在对应全局热键真实生效时显示。
    /// （系统 Dock 行传 true：⌥⌘D 由 macOS 持有，恒生效，无注册环节。）
    static func keyEquivalentPresentation(isHotKeyRegistered: Bool,
                                          shortcut: GlobalHotKeyShortcut) -> (key: String, mask: NSEvent.ModifierFlags) {
        isHotKeyRegistered ? (shortcut.keyEquivalent, shortcut.keyEquivalentModifierMask) : ("", [])
    }

}

/// 系统 Dock 滑块的提交去重。三个触发源会互相撞车——鼠标松手、键盘/辅助功能调整的 debounce、
/// 菜单关闭——各跑一次 `apply` 就是两次 `killall Dock`。pending 必须被**原子消费**：
/// 谁先 `consume()` 谁负责提交，其余全部拿到 nil。
struct PreferenceSliderCommitTracker {
    private var baseline: Double?
    private var pending: Double?

    var hasPending: Bool { pending != nil }

    /// 记录草稿起点。一轮调整里只认第一次，中途重复调用不覆盖（拖动过程中会反复触发）。
    mutating func begin(currentDelay: Double) {
        if baseline == nil { baseline = currentDelay }
    }

    mutating func stage(_ value: Double) {
        pending = value
    }

    /// 原子取出待提交值。无起点、无变化、或已被别人消费过 → nil。
    mutating func consume() -> (previous: Double, target: Double)? {
        defer {
            baseline = nil
            pending = nil
        }
        guard let baseline, let pending, baseline != pending else { return nil }
        return (baseline, pending)
    }
}

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let store: AppSettingsStore
    private let launchAtLoginService: LaunchAtLoginServicing
    private let nativeDockPreferencesService: NativeDockPreferencesServicing
    private let updateChecker: UpdateChecking
    // 闭包注入而非直接依赖 PermissionService：测试 target 编译本文件但不含 PermissionService.swift。
    private let isAccessibilityTrusted: () -> Bool
    private let onShowDebugConsole: () -> Void
    private let onExportDebugSnapshot: () -> Void
    private let onQuit: () -> Void
    private let toggleHotKeyShortcut: GlobalHotKeyShortcut
    // 闭包注入：注册状态归 AppDelegate 持有的 GlobalHotKeyMonitor，菜单每次刷新时现查。
    private let isToggleHotKeyRegistered: () -> Bool
    private var edgeDelaySubscription: AnyCancellable?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let permissionWarningItem = NSMenuItem(title: "辅助功能权限未开启", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let permissionWarningSeparator = NSMenuItem.separator()
    private let launchAtLoginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let openLoginItemsSettingsItem = NSMenuItem(title: "打开登录项设置…", action: #selector(openLoginItemsSettings), keyEquivalent: "")
    private let checkForUpdatesItem = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
    private let edgeAutoHideToggleItem = NSMenuItem(title: "", action: #selector(toggleEdgeAutoHideModeFromMenu), keyEquivalent: "")
    private let showShelfItem = NSMenuItem(title: "显示中转站", action: #selector(toggleShowShelf), keyEquivalent: "")
    private let dockSizeItem = NSMenuItem(title: "任务条大小", action: nil, keyEquivalent: "")
    private var dockSizeItems: [DockSize: NSMenuItem] = [:]
    private let nativeDockToggleItem = NSMenuItem(title: "", action: #selector(toggleNativeDockAutoHideFromMenu), keyEquivalent: "")
    private let openNativeDockSettingsItem = NSMenuItem(title: "打开系统 Dock 设置…", action: #selector(openNativeDockSettings), keyEquivalent: "")
    private let nativeDockSliderView: PreferenceSliderMenuItemView
    private let edgeSliderView: PreferenceSliderMenuItemView
    private var updateCheckState = UpdateCheckMenuState()

    init(store: AppSettingsStore,
         launchAtLoginService: LaunchAtLoginServicing,
         nativeDockPreferencesService: NativeDockPreferencesServicing,
         updateChecker: UpdateChecking,
         isAccessibilityTrusted: @escaping () -> Bool,
         onShowDebugConsole: @escaping () -> Void,
         onExportDebugSnapshot: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         toggleHotKeyShortcut: GlobalHotKeyShortcut = .edgeAutoHideMode,
         isToggleHotKeyRegistered: @escaping () -> Bool = { false }) {
        self.store = store
        self.launchAtLoginService = launchAtLoginService
        self.nativeDockPreferencesService = nativeDockPreferencesService
        self.updateChecker = updateChecker
        self.isAccessibilityTrusted = isAccessibilityTrusted
        self.onShowDebugConsole = onShowDebugConsole
        self.onExportDebugSnapshot = onExportDebugSnapshot
        self.onQuit = onQuit
        self.toggleHotKeyShortcut = toggleHotKeyShortcut
        self.isToggleHotKeyRegistered = isToggleHotKeyRegistered
        nativeDockSliderView = PreferenceSliderMenuItemView(accessibilityTitle: "系统 Dock 唤醒时间")
        edgeSliderView = PreferenceSliderMenuItemView(accessibilityTitle: "Tungsten Edge 钨极唤醒时间")
        super.init()
        configureStatusItem()
        configureMenu()
        refreshCheckmarks()
        refreshUpdateCheckItem()
        // 钨极组：动态命令与滑块同处一个打开着的菜单，拖动时要实时同步标题（本地值即时生效）。
        // sink 用 publisher 发出的新值：@Published 在赋值完成前发布，此刻回读 store 是旧值。
        //
        // 系统 Dock 组刻意**没有**同款订阅：它的标题描述的是系统真值，而草稿在松手写进系统之前
        // 系统没变，标题就不该变。滑块位置由 menuWillOpen 与提交完成后各同步一次。
        edgeDelaySubscription = store.$edgeAutoHideDelay
            .removeDuplicates()
            .sink { [weak self] delay in
                self?.edgeSliderView.sync(delay: delay)
                self?.refreshEdgeAutoHideToggleItem(delay: delay)
            }
    }

    private func configureStatusItem() {
        let image = NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "rectangle.3.offgrid.fill", accessibilityDescription: "Tungsten Edge")
        image?.isTemplate = true
        image?.accessibilityDescription = "Tungsten Edge"
        statusItem.button?.image = image
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.delegate = self

        permissionWarningItem.target = self
        permissionWarningItem.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "警告")
        permissionWarningItem.isHidden = true
        permissionWarningSeparator.isHidden = true
        menu.addItem(permissionWarningItem)
        menu.addItem(permissionWarningSeparator)

        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        openLoginItemsSettingsItem.target = self
        menu.addItem(openLoginItemsSettingsItem)
        menu.addItem(.separator())

        nativeDockToggleItem.target = self
        // ⌥⌘D 由 macOS 自己持有、恒生效，提示恒显示（不同于钨极行的注册门控）。
        let nativeHint = AutoHideToggleMenuModel.keyEquivalentPresentation(
            isHotKeyRegistered: true,
            shortcut: .nativeDockAutoHide
        )
        nativeDockToggleItem.keyEquivalent = nativeHint.key
        nativeDockToggleItem.keyEquivalentModifierMask = nativeHint.mask
        menu.addItem(nativeDockToggleItem)

        // 系统 Dock 滑块刻意不接 onDelayChange：草稿只留在视图里。setNativeDockAutoHideDelay
        // 一调用就把 active + remembered 一起落盘，而系统那边还没写，拖到一半的值不该变成持久状态。
        nativeDockSliderView.onDelayCommit = { [weak self] previous, target in
            self?.commitNativeDockDelay(previous: previous, target: target)
        }
        let nativeDockSliderItem = NSMenuItem()
        nativeDockSliderItem.view = nativeDockSliderView
        menu.addItem(nativeDockSliderItem)

        openNativeDockSettingsItem.target = self
        menu.addItem(openNativeDockSettingsItem)
        menu.addItem(.separator())

        edgeAutoHideToggleItem.target = self
        menu.addItem(edgeAutoHideToggleItem)
        edgeSliderView.onDelayChange = { [weak store] delay in
            store?.setEdgeAutoHideDelay(delay)
        }
        let edgeItem = NSMenuItem()
        edgeItem.view = edgeSliderView
        menu.addItem(edgeItem)

        // 钨极自己的外观开关跟在钨极这一组里（标题恒定，状态用勾表达，同「登录时启动」）。
        showShelfItem.target = self
        menu.addItem(showShelfItem)

        let dockSizeMenu = NSMenu()
        for size in DockSize.allCases {
            let item = NSMenuItem(title: size.title, action: #selector(selectDockSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size.rawValue
            dockSizeMenu.addItem(item)
            dockSizeItems[size] = item
        }
        dockSizeItem.submenu = dockSizeMenu
        menu.addItem(dockSizeItem)

        menu.addItem(.separator())
        #if DEBUG
        let debugMenu = NSMenu()
        let showDebug = NSMenuItem(title: "显示调试台", action: #selector(showDebugConsole), keyEquivalent: "")
        showDebug.target = self
        debugMenu.addItem(showDebug)
        let exportSnapshot = NSMenuItem(title: "导出任务条快照", action: #selector(exportDebugSnapshot), keyEquivalent: "")
        exportSnapshot.target = self
        debugMenu.addItem(exportSnapshot)
        let debugItem = NSMenuItem(title: "调试", action: nil, keyEquivalent: "")
        debugItem.submenu = debugMenu
        menu.addItem(debugItem)
        menu.addItem(.separator())
        #endif

        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)
        if let versionTitle = Self.versionMenuTitle() {
            let versionItem = NSMenuItem(title: versionTitle, action: nil, keyEquivalent: "")
            versionItem.isEnabled = false
            menu.addItem(versionItem)
        }

        let quitItem = NSMenuItem(title: "退出 Tungsten Edge 钨极", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private static func versionMenuTitle() -> String? {
        let info = Bundle.main.infoDictionary
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        // 版本号在发布后主线不 bump，光看数字分不出开发构建和用户装的包，
        // 因此把来源一并显示出来。判定逻辑在纯 BuildProvenance 里，有单测。
        return BuildProvenance.versionTitle(
            version: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String,
            isDebugBuild: isDebugBuild,
            bundlePath: Bundle.main.bundleURL.path
        )
    }

    func menuWillOpen(_ menu: NSMenu) {
        let granted = isAccessibilityTrusted()
        permissionWarningItem.isHidden = granted
        permissionWarningSeparator.isHidden = granted
        // 先把系统实际状态回灌进本地镜像，再刷新动态命令标题。
        reconcileNativeDockStoreWithSystem()
        refreshCheckmarks()
        refreshUpdateCheckItem()
        nativeDockSliderView.sync(delay: store.nativeDockAutoHideDelay)
        edgeSliderView.sync(delay: store.edgeAutoHideDelay)
        // 钨极行刷注册门控；系统 Dock 行每次都重新读取系统真值。
        refreshEdgeAutoHideToggleItem(delay: store.edgeAutoHideDelay)
        refreshNativeDockToggleItem(storeDelay: store.nativeDockAutoHideDelay)
    }

    func menuDidClose(_ menu: NSMenu) {
        // 键盘 / VoiceOver 改滑块走不到 mouseUp，靠 debounce 提交；菜单先关掉时在这里兜底。
        // 已被松手或 timer 消费过的 pending 在这里拿到 nil，不会重复写系统。
        nativeDockSliderView.flushPendingCommit()
    }

    /// 只改本地存值让 UI 对齐系统真值，绝不反向应用（菜单打开不许 killall Dock）。
    private func reconcileNativeDockStoreWithSystem() {
        guard let state = nativeDockPreferencesService.currentAutohideState() else { return }
        if let target = AutoHideToggleMenuModel.reconciledStoreDelay(
            systemEnabled: state.enabled,
            systemDelay: state.delay,
            currentStoreDelay: store.nativeDockAutoHideDelay
        ) {
            store.setNativeDockAutoHideDelay(target)
        }
    }

    private func refreshEdgeAutoHideToggleItem(delay: Double) {
        edgeAutoHideToggleItem.title = AutoHideToggleMenuModel.edgeTitle(delay: delay)
        edgeAutoHideToggleItem.state = .off
        let presentation = AutoHideToggleMenuModel.keyEquivalentPresentation(
            isHotKeyRegistered: isToggleHotKeyRegistered(),
            shortcut: toggleHotKeyShortcut
        )
        edgeAutoHideToggleItem.keyEquivalent = presentation.key
        edgeAutoHideToggleItem.keyEquivalentModifierMask = presentation.mask
    }

    private func refreshNativeDockToggleItem(storeDelay: Double) {
        let live = nativeDockPreferencesService.currentAutohideState()?.enabled
        nativeDockToggleItem.title = AutoHideToggleMenuModel.nativeTitle(
            liveAutohide: live,
            storeDelay: storeDelay
        )
        nativeDockToggleItem.state = .off
    }

    @objc private func toggleEdgeAutoHideModeFromMenu() {
        store.toggleEdgeAutoHideMode()
    }

    @objc private func toggleNativeDockAutoHideFromMenu() {
        let event = NSApp.currentEvent
        let isKeyEvent = event?.type == .keyDown
        if AutoHideToggleMenuModel.shouldSkipNativeDockMenuAction(
            eventType: event?.type,
            keyCode: isKeyEvent ? event?.keyCode : nil,
            modifierFlags: event?.modifierFlags ?? [],
            isSystemShortcutAvailable: true // ⌥⌘D 由 macOS 持有，恒生效
        ) { return }

        let targetEnabled = AutoHideToggleMenuModel.nativeToggleTargetEnabled(
            liveAutohide: nativeDockPreferencesService.currentAutohideState()?.enabled,
            storeDelay: store.nativeDockAutoHideDelay
        )
        // 命令严格等价 ⌥⌘D：只切 autohide。target 只是本地镜像的预期值，
        // 真正落什么以写完之后重读到的系统真值为准。
        scheduleNativeDockWrite(
            previous: store.nativeDockAutoHideDelay,
            target: targetEnabled ? store.lastEnabledNativeDockAutoHideDelay : AppSettingsStore.neverHideDelay
        ) { [nativeDockPreferencesService] in
            try nativeDockPreferencesService.setAutohideEnabled(targetEnabled)
        }
    }

    @objc private func openNativeDockSettings() {
        guard nativeDockPreferencesService.openSystemSettings() else {
            presentError(
                title: "无法打开系统 Dock 设置",
                message: "请从系统设置进入「桌面与程序坞」（macOS 12 为「程序坞与菜单栏」）。"
            )
            return
        }
    }

    private func refreshCheckmarks() {
        refreshLaunchAtLoginState()
        showShelfItem.state = store.showShelf ? .on : .off
        for (size, item) in dockSizeItems {
            item.state = store.dockSize == size ? .on : .off
        }
    }

    @objc private func toggleShowShelf() {
        store.setShowShelf(!store.showShelf)
        refreshCheckmarks()
    }

    @objc private func selectDockSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let size = DockSize(rawValue: raw) else { return }
        store.setDockSize(size)
        refreshCheckmarks()
    }

    private func refreshLaunchAtLoginState() {
        let presentation = LaunchAtLoginMenuPresentation(state: launchAtLoginService.state)
        launchAtLoginItem.title = presentation.title
        launchAtLoginItem.state = presentation.isChecked ? .on : .off
        launchAtLoginItem.isEnabled = presentation.isEnabled
        openLoginItemsSettingsItem.isHidden = !presentation.showsSettingsItem
    }

    private func refreshUpdateCheckItem() {
        let presentation = updateCheckState.presentation
        checkForUpdatesItem.title = presentation.title
        checkForUpdatesItem.isEnabled = presentation.isEnabled
    }

    @objc private func toggleLaunchAtLogin() {
        guard let enable = LaunchAtLoginMenuModel.requestedEnabledValue(afterSelecting: launchAtLoginService.state) else { return }
        do {
            try launchAtLoginService.setEnabled(enable)
            store.setLaunchAtLogin(enable)
        } catch {
            presentError(title: "登录时启动设置失败", message: error.localizedDescription)
        }
        refreshCheckmarks()
    }

    @objc private func openLoginItemsSettings() {
        launchAtLoginService.openSystemSettings()
    }

    @objc private func checkForUpdates() {
        guard updateCheckState.begin() else { return }
        refreshUpdateCheckItem()
        menu.cancelTrackingWithoutAnimation()

        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        Task { [weak self] in
            guard let self else { return }
            do {
                let outcome = try await updateChecker.check(currentVersion: currentVersion)
                finishUpdateCheck()
                presentUpdateOutcome(outcome)
            } catch {
                finishUpdateCheck()
                presentUpdateCheckFailure()
            }
        }
    }

    private func finishUpdateCheck() {
        updateCheckState.finish()
        refreshUpdateCheckItem()
    }

    private func presentUpdateOutcome(_ outcome: UpdateCheckOutcome) {
        let alert = NSAlert()
        alert.alertStyle = .informational

        switch outcome {
        case .updateAvailable(let currentVersion, let latestVersion, let releaseURL):
            alert.messageText = "发现新版本 \(latestVersion)"
            alert.informativeText = "当前版本 \(currentVersion)。钨极目前仍需手动下载安装。"
            alert.addButton(withTitle: "前往下载")
            alert.addButton(withTitle: "稍后")
            if Self.runModalInForeground(alert) == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releaseURL)
            }
        case .upToDate(let currentVersion, let latestVersion):
            alert.messageText = "当前已是最新版本"
            alert.informativeText = "当前版本 \(currentVersion)，GitHub 最新正式版为 \(latestVersion)。"
            alert.addButton(withTitle: "好")
            Self.runModalInForeground(alert)
        }
    }

    private func presentUpdateCheckFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "暂时无法检查更新"
        alert.informativeText = "请检查网络连接后重试，也可以直接打开 GitHub 发布页。"
        alert.addButton(withTitle: "打开发布页")
        alert.addButton(withTitle: "好")
        if Self.runModalInForeground(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(GitHubUpdateChecker.releasesURL)
        }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = AccessibilitySettingsLink.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func commitNativeDockDelay(previous: Double, target: Double) {
        scheduleNativeDockWrite(previous: previous, target: target) { [nativeDockPreferencesService] in
            try nativeDockPreferencesService.apply(delay: target)
        }
    }

    /// 系统 Dock 的两条写入路径都走这里。先收菜单——写入以 `killall Dock` 收尾，
    /// 菜单不该在系统 Dock 重启时还开着；下一轮再执行。
    private func scheduleNativeDockWrite(previous: Double,
                                         target: Double,
                                         write: @escaping @MainActor () throws -> Void) {
        menu.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async { [weak self] in
            self?.applyNativeDockWrite(previous: previous, target: target, write: write)
        }
    }

    private func applyNativeDockWrite(previous: Double,
                                      target: Double,
                                      write: @MainActor () throws -> Void) {
        guard nativeDockPreferencesService.isAvailable else {
            presentError(title: "系统 Dock 设置失败", message: NativeDockPreferencesError.sandboxed.localizedDescription)
            return
        }

        // defaults/killall 是多步非事务序列，写完一律重读系统真值再决定本地镜像落什么
        // （四象限见 AutoHideToggleMenuModel.resolvedStoreDelay）。
        var writeError: Error?
        do {
            try write()
        } catch {
            writeError = error
        }

        let resolved = AutoHideToggleMenuModel.resolvedStoreDelay(
            writeSucceeded: writeError == nil,
            systemState: nativeDockPreferencesService.currentAutohideState(),
            target: target,
            previous: previous
        )
        store.setNativeDockAutoHideDelay(resolved)
        nativeDockSliderView.sync(delay: resolved)
        refreshNativeDockToggleItem(storeDelay: resolved)

        // 只有写失败才提示。写成功但读不回来时弹窗会让用户以为没生效，其实系统已经改了。
        if let writeError {
            presentError(title: "系统 Dock 设置失败", message: writeError.localizedDescription)
        }
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        Self.runModalInForeground(alert)
    }

    /// 钨极是 `.accessory` 应用（无程序坞图标）。这类应用直接 `runModal()` 时**不会**把自己
    /// 带到前台，弹窗会落在当前前台应用的窗口后面——用户点了菜单项却看不到任何反应，
    /// 表现和「功能坏了」完全一样（真实用户就是这么报的「检查更新失效」）。
    /// 只要前台有任何窗口就中招，也就是几乎总是中招。
    ///
    /// `AppDelegate` 里每个 `runModal()` / 面板展示之前都调了 `NSApp.activate`，
    /// 唯独状态菜单这四处漏了。所有弹窗一律走这里，别再各自 `runModal()`。
    @discardableResult
    private static func runModalInForeground(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    @objc private func showDebugConsole() { onShowDebugConsole() }
    @objc private func exportDebugSnapshot() { onExportDebugSnapshot() }
    @objc private func quit() { onQuit() }
}

@MainActor
final class PreferenceSliderMenuItemView: NSView {
    /// 每一格变化。即时生效型滑块（钨极，本地值）在这里直接写 store。
    var onDelayChange: ((Double) -> Void)?
    /// 落定回调。**设了它就启用提交机制**（系统 Dock：每次应用都要 `killall Dock`，
    /// 逐格触发会把系统 Dock 反复重启）。三个触发源经 `PreferenceSliderCommitTracker` 去重。
    var onDelayCommit: ((_ previous: Double, _ target: Double) -> Void)?

    private let accessibilityTitle: String
    private var delay = 0.0
    private var commitTracker = PreferenceSliderCommitTracker()
    private var keyboardCommitTimer: Timer?
    /// 键盘 / VoiceOver 每按一下方向键就是一格，攒一小会儿再提交。
    private static let keyboardCommitDelay: TimeInterval = 0.2
    private var displayString = "0.0s"
    private let leftEndpointDot = EndpointDotView()
    private let rightEndpointDot = EndpointDotView()
    private let delayLabel = NSTextField(labelWithString: "")
    private let leftEndpointLabel = NSTextField(labelWithString: "常驻")
    private let rightEndpointLabel = NSTextField(labelWithString: "不唤醒")
    private let slider = MenuTrackingSlider()

    init(accessibilityTitle: String) {
        self.accessibilityTitle = accessibilityTitle
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 58))
        autoresizingMask = [.width]
        configureSubviews()
        updateDisplay()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityValue() -> Any? {
        displayString
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let width = window?.frame.width, width > frame.width {
            frame.size.width = width
        }
    }

    func sync(delay: Double) {
        let index = AppSettingsStore.sliderIndexFromDelay(delay)
        self.delay = AppSettingsStore.delayFromSliderIndex(index)
        slider.integerValue = index
        updateDisplay()
    }

    private func configureSubviews() {
        wantsLayer = true

        leftEndpointDot.setAccessibilityElement(false)
        addSubview(leftEndpointDot)

        rightEndpointDot.setAccessibilityElement(false)
        addSubview(rightEndpointDot)

        delayLabel.font = .systemFont(ofSize: 11)
        delayLabel.textColor = .secondaryLabelColor
        delayLabel.alignment = .center
        addSubview(delayLabel)

        leftEndpointLabel.font = .systemFont(ofSize: 9)
        leftEndpointLabel.textColor = .tertiaryLabelColor
        leftEndpointLabel.alignment = .center
        leftEndpointLabel.setAccessibilityElement(false)
        addSubview(leftEndpointLabel)

        rightEndpointLabel.font = .systemFont(ofSize: 9)
        rightEndpointLabel.textColor = .tertiaryLabelColor
        rightEndpointLabel.alignment = .center
        rightEndpointLabel.setAccessibilityElement(false)
        addSubview(rightEndpointLabel)

        slider.minValue = 0
        slider.maxValue = Double(AppSettingsStore.sliderIndexMax)
        slider.integerValue = AppSettingsStore.sliderIndexFromDelay(delay)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.onTrackingStarted = { [weak self] in
            guard let self else { return }
            self.commitTracker.begin(currentDelay: self.delay)
        }
        slider.onTrackingEnded = { [weak self] in
            self?.commitPendingDelay()
        }
        addSubview(slider)

        setAccessibilityRole(.group)
    }

    override func layout() {
        super.layout()
        let dotSize: CGFloat = 8
        let contentX = StatusMenuLayout.textInsetX
        let contentWidth = bounds.width - contentX - StatusMenuLayout.trailingInsetX
        let labelY: CGFloat = 28
        let sliderY: CGFloat = 10

        let sliderSideInset: CGFloat = 34
        let sliderX = contentX + sliderSideInset
        let sliderWidth = max(0, contentWidth - sliderSideInset * 2)
        delayLabel.frame = NSRect(x: sliderX, y: labelY, width: sliderWidth, height: 14)

        let dotY = sliderY + 6
        leftEndpointDot.frame = NSRect(x: contentX + 14, y: dotY, width: dotSize, height: dotSize)
        slider.frame = NSRect(x: sliderX, y: sliderY, width: sliderWidth, height: 20)
        rightEndpointDot.frame = NSRect(x: slider.frame.maxX + 12, y: dotY, width: dotSize, height: dotSize)
        leftEndpointLabel.frame = NSRect(x: contentX, y: labelY, width: sliderSideInset, height: 14)
        rightEndpointLabel.frame = NSRect(x: slider.frame.maxX, y: labelY, width: sliderSideInset, height: 14)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let index = min(max(Int(sender.doubleValue.rounded()), 0), AppSettingsStore.sliderIndexMax)
        sender.integerValue = index
        let previousDelay = delay
        delay = AppSettingsStore.delayFromSliderIndex(index)
        updateDisplay()
        onDelayChange?(delay)

        guard onDelayCommit != nil else { return }
        // 键盘 / VoiceOver 调整不经过 mouseDown，没有 tracking 起点，这里补一个
        // （鼠标路径里 begin 已由 onTrackingStarted 调过，重复调用不覆盖起点）。
        commitTracker.begin(currentDelay: previousDelay)
        commitTracker.stage(delay)
        if !slider.isMouseTracking {
            scheduleKeyboardCommit()
        }
    }

    private func scheduleKeyboardCommit() {
        keyboardCommitTimer?.invalidate()
        let timer = Timer(timeInterval: Self.keyboardCommitDelay, repeats: false) { _ in
            MainActor.assumeIsolated { [weak self] in self?.commitPendingDelay() }
        }
        // 菜单追踪期 run loop 在 .eventTracking 模式，.default 的 timer 不会触发。
        RunLoop.main.add(timer, forMode: .common)
        keyboardCommitTimer = timer
    }

    /// 菜单先于 debounce 关掉时的兜底提交。已被别的触发源消费过就是空操作。
    func flushPendingCommit() {
        commitPendingDelay()
    }

    private func commitPendingDelay() {
        keyboardCommitTimer?.invalidate()
        keyboardCommitTimer = nil
        guard let commit = commitTracker.consume() else { return }
        onDelayCommit?(commit.previous, commit.target)
    }

    private func updateDisplay() {
        let index = slider.integerValue
        displayString = displayString(for: index)
        delay = AppSettingsStore.delayFromSliderIndex(index)
        delayLabel.stringValue = displayString
        // 两端「常驻/不唤醒」小字恒定可见，端点圆点在选中时变实心强调；
        // 中间数值文字到达端点时改为隐藏，避免和恒定可见的端点小字重复显示同一个词。
        let isAtLeftEnd = index == 0
        let isAtRightEnd = index == AppSettingsStore.sliderIndexMax
        delayLabel.isHidden = isAtLeftEnd || isAtRightEnd
        leftEndpointDot.isOn = isAtLeftEnd
        rightEndpointDot.isOn = isAtRightEnd
        setAccessibilityLabel("\(accessibilityTitle)，\(displayString)")
        setAccessibilityValue(displayString)
        slider.displayString = displayString
    }

    private func displayString(for index: Int) -> String {
        switch index {
        case 0:
            return "常驻"
        case AppSettingsStore.sliderIndexMax:
            return "不唤醒"
        default:
            return String(format: "%.1fs", AppSettingsStore.delayFromSliderIndex(index))
        }
    }
}

final class EndpointDotView: NSView {
    var isOn = false {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(ovalIn: rect)
        (isOn ? NSColor.controlAccentColor : .clear).setFill()
        path.fill()
        (isOn ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}

final class MenuTrackingSlider: NSSlider {
    var displayString = "0.0s"
    var onTrackingStarted: (() -> Void)?
    var onTrackingEnded: (() -> Void)?
    /// `mouseDown` 在拖动全程不返回，因此这个标志就是「当前是不是鼠标拖动」的准确答案，
    /// 用来把键盘 / 辅助功能路径分流到 debounce 提交。
    private(set) var isMouseTracking = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        isMouseTracking = true
        onTrackingStarted?()
        super.mouseDown(with: event)
        isMouseTracking = false
        onTrackingEnded?()
    }

    override func accessibilityValue() -> Any? {
        displayString
    }
}
