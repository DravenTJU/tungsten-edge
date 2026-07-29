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

    /// 系统 Dock 状态优先读系统真值；读不到时用本地镜像兜底。
    static func nativeIsCompletelyHidden(
        liveState: NativeDockAutohideState?,
        hasPendingRestore: Bool,
        storeDelay: Double
    ) -> Bool {
        if hasPendingRestore { return true }
        if let liveState { return NativeDockPreferencesService.isCompletelyHidden(liveState) }
        return storeDelay >= NativeDockPreferencesService.completeHideDelay
    }

    static func nativeTitle(
        liveState: NativeDockAutohideState?,
        hasPendingRestore: Bool,
        storeDelay: Double
    ) -> String {
        nativeIsCompletelyHidden(
            liveState: liveState,
            hasPendingRestore: hasPendingRestore,
            storeDelay: storeDelay
        )
            ? "显示系统 Dock"
            // 标题按 owner 决定保持简短；命令实际执行的仍是彻底隐藏（含关闭底边唤醒）。
            : "隐藏系统 Dock"
    }

    static func nativeToggleTargetHidden(
        liveState: NativeDockAutohideState?,
        hasPendingRestore: Bool,
        storeDelay: Double
    ) -> Bool {
        !nativeIsCompletelyHidden(
            liveState: liveState,
            hasPendingRestore: hasPendingRestore,
            storeDelay: storeDelay
        )
    }

    /// autohide-delay 键不存在时系统 Dock 的实际默认延迟。
    static let systemDefaultAutohideDelay = 0.5

    /// 菜单打开时把系统实际状态回灌进本地镜像，让读取失败时的标题和点击方向仍有可靠兜底。
    /// 外部通过 ⌥⌘D 或系统设置修改后，本地镜像不能继续保留过期状态。
    /// 返回 nil = 已一致，无需改动。
    static func reconciledStoreDelay(systemEnabled: Bool, systemDelay: Double?, currentStoreDelay: Double) -> Double? {
        let target: Double
        if systemEnabled {
            let rawDelay = systemDelay ?? systemDefaultAutohideDelay
            // 系统开关已经明确为开；负 delay 只能视为外部自定义的极短延迟，
            // 不能穿透 snapDelay 被误解释成本 App 的「常驻」哨兵 -1。
            let enabledDelay = rawDelay.isFinite
                ? max(rawDelay, AppSettingsStore.finiteDelayMin)
                : AppSettingsStore.defaultNativeDockAutoHideDelay
            target = AppSettingsStore.snapDelay(
                enabledDelay,
                fallbackForNonFinite: AppSettingsStore.defaultNativeDockAutoHideDelay
            )
        } else {
            target = AppSettingsStore.neverHideDelay
        }
        return currentStoreDelay == target ? nil : target
    }

    /// keyEquivalent 提示只在对应全局热键真实生效时显示。
    static func keyEquivalentPresentation(isHotKeyRegistered: Bool,
                                          shortcut: GlobalHotKeyShortcut) -> (key: String, mask: NSEvent.ModifierFlags) {
        isHotKeyRegistered ? (shortcut.keyEquivalent, shortcut.keyEquivalentModifierMask) : ("", [])
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
    private let nativeDockToggleItem = NSMenuItem(title: "", action: #selector(toggleNativeDockAutoHideFromMenu), keyEquivalent: "")
    private let openNativeDockSettingsItem = NSMenuItem(title: "打开系统 Dock 设置…", action: #selector(openNativeDockSettings), keyEquivalent: "")
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
        edgeSliderView = PreferenceSliderMenuItemView(accessibilityTitle: "Tungsten Edge 钨极唤醒时间")
        super.init()
        configureStatusItem()
        configureMenu()
        refreshCheckmarks()
        refreshUpdateCheckItem()
        // 动态命令与滑块同处一个打开着的菜单：拖动时要实时同步标题。
        // sink 用 publisher 发出的新值：@Published 在赋值完成前发布，此刻回读 store 是旧值。
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
        // ⌥⌘D 只能切普通自动隐藏，不能表达「彻底隐藏」，因此不再作为本命令快捷键展示。
        nativeDockToggleItem.keyEquivalent = ""
        nativeDockToggleItem.keyEquivalentModifierMask = []
        menu.addItem(nativeDockToggleItem)
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
        edgeSliderView.sync(delay: store.edgeAutoHideDelay)
        // 钨极行刷注册门控；系统 Dock 行每次都重新读取系统真值。
        refreshEdgeAutoHideToggleItem(delay: store.edgeAutoHideDelay)
        refreshNativeDockToggleItem(storeDelay: store.nativeDockAutoHideDelay)
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
        let live = nativeDockPreferencesService.currentAutohideState()
        nativeDockToggleItem.title = AutoHideToggleMenuModel.nativeTitle(
            liveState: live,
            hasPendingRestore: nativeDockPreferencesService.hasPendingRestore,
            storeDelay: storeDelay
        )
        nativeDockToggleItem.state = .off
    }

    @objc private func toggleEdgeAutoHideModeFromMenu() {
        store.toggleEdgeAutoHideMode()
    }

    @objc private func toggleNativeDockAutoHideFromMenu() {
        let targetHidden = AutoHideToggleMenuModel.nativeToggleTargetHidden(
            liveState: nativeDockPreferencesService.currentAutohideState(),
            hasPendingRestore: nativeDockPreferencesService.hasPendingRestore,
            storeDelay: store.nativeDockAutoHideDelay
        )
        scheduleNativeDockVisibilityChange(hidden: targetHidden)
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
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func scheduleNativeDockVisibilityChange(hidden: Bool) {
        menu.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async { [weak self] in
            self?.applyNativeDockVisibility(hidden: hidden)
        }
    }

    private func applyNativeDockVisibility(hidden: Bool) {
        guard nativeDockPreferencesService.isAvailable else {
            presentError(title: "系统 Dock 设置失败", message: NativeDockPreferencesError.sandboxed.localizedDescription)
            return
        }

        do {
            try nativeDockPreferencesService.setCompletelyHidden(hidden)
            reconcileNativeDockStoreWithSystem()
            refreshNativeDockToggleItem(storeDelay: store.nativeDockAutoHideDelay)
        } catch {
            // defaults/killall 是多步非事务序列；失败后重读系统真值校准动态标题。
            reconcileNativeDockStoreWithSystem()
            presentError(title: "系统 Dock 设置失败", message: error.localizedDescription)
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
    var onDelayChange: ((Double) -> Void)?

    private let accessibilityTitle: String
    private var delay = 0.0
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
        delay = AppSettingsStore.delayFromSliderIndex(index)
        updateDisplay()
        onDelayChange?(delay)
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func accessibilityValue() -> Any? {
        displayString
    }
}
