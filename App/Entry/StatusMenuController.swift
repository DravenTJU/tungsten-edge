import AppKit
import Combine

private enum StatusMenuLayout {
    static let textInsetX: CGFloat = 28
    static let trailingInsetX: CGFloat = 14
}

/// 两个「自动隐藏」勾选行（系统 Dock 组 + 钨极组）的纯展示/去重决策（单测覆盖）。
@MainActor
enum AutoHideToggleMenuModel {
    /// 勾选样式：文字恒定，状态用 checkmark 表达（和「登录时启动」同款习惯用法）。
    static let title = "自动隐藏"

    /// 钨极行勾选：本地存值权威（没有外部写者）。
    static func isChecked(delay: Double) -> Bool {
        delay != AppSettingsStore.neverHideDelay
    }

    /// 系统 Dock 行勾选：优先系统实际值（用户随时可用 ⌥⌘D / 系统设置改），读不到回退存值推导。
    static func nativeIsChecked(liveAutohide: Bool?, storeDelay: Double) -> Bool {
        liveAutohide ?? isChecked(delay: storeDelay)
    }

    /// 系统 Dock 行点击后应写入的延迟值。方向必须由实际勾选状态（live 优先）决定，
    /// 不能盲翻存值——存值可能已被外部改动甩在身后。
    static func nativeToggleTarget(liveAutohide: Bool?, storeDelay: Double, remembered: Double) -> Double {
        nativeIsChecked(liveAutohide: liveAutohide, storeDelay: storeDelay)
            ? AppSettingsStore.neverHideDelay
            : remembered
    }

    /// autohide-delay 键不存在时系统 Dock 的实际默认延迟。
    static let systemDefaultAutohideDelay = 0.5

    /// 菜单打开时把系统实际状态回灌进本地存值，让滑杆、勾选、点击方向从同一真值出发
    /// （否则外部按过 ⌥⌘D 后，勾选显示实情而滑杆还停在过期位置，同组自相矛盾）。
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

    /// keyEquivalent 提示只在对应全局热键真实生效时显示——菜单不许展示一个不生效的快捷键。
    /// （系统 Dock 行传 true：⌥⌘D 由 macOS 持有，恒生效，无注册环节。）
    static func keyEquivalentPresentation(isHotKeyRegistered: Bool,
                                          shortcut: GlobalHotKeyShortcut) -> (key: String, mask: NSEvent.ModifierFlags) {
        isHotKeyRegistered ? (shortcut.keyEquivalent, shortcut.keyEquivalentModifierMask) : ("", [])
    }

    /// 系统 ⌥⌘D 在菜单追踪期间仍由 macOS 处理；菜单 action 只跳过这一条精确 keyDown。
    /// 鼠标、Return、辅助功能触发和其它键盘事件仍执行菜单 action。
    /// 使用物理 D 键码而非字符，避免非美式布局下字符与系统快捷键脱节。
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
    // 同上闭包注入：NSOpenPanel 归 AppDelegate 管，本文件不碰 PinnedFolderStore。
    private let onAddPinnedFolder: () -> Void
    private let toggleHotKeyShortcut: GlobalHotKeyShortcut
    // 闭包注入：注册状态归 AppDelegate 持有的 GlobalHotKeyMonitor，菜单每次刷新时现查。
    private let isToggleHotKeyRegistered: () -> Bool
    private var edgeDelaySubscription: AnyCancellable?
    private var nativeDockDelaySubscription: AnyCancellable?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let permissionWarningItem = NSMenuItem(title: "辅助功能权限未开启", action: #selector(openAccessibilitySettings), keyEquivalent: "")
    private let permissionWarningSeparator = NSMenuItem.separator()
    private let launchAtLoginItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let openLoginItemsSettingsItem = NSMenuItem(title: "打开登录项设置…", action: #selector(openLoginItemsSettings), keyEquivalent: "")
    private let addPinnedFolderItem = NSMenuItem(title: "添加固定文件夹…", action: #selector(addPinnedFolder), keyEquivalent: "")
    private let checkForUpdatesItem = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
    private let edgeAutoHideToggleItem = NSMenuItem(title: AutoHideToggleMenuModel.title, action: #selector(toggleEdgeAutoHideModeFromMenu), keyEquivalent: "")
    private let nativeDockToggleItem = NSMenuItem(title: AutoHideToggleMenuModel.title, action: #selector(toggleNativeDockAutoHideFromMenu), keyEquivalent: "")
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
         onAddPinnedFolder: @escaping () -> Void = {},
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
        self.onAddPinnedFolder = onAddPinnedFolder
        self.toggleHotKeyShortcut = toggleHotKeyShortcut
        self.isToggleHotKeyRegistered = isToggleHotKeyRegistered
        // 提示小字已升级成滑块下方的真按钮行，滑块标题不再带 subtitle。
        nativeDockSliderView = PreferenceSliderMenuItemView(title: "系统 Dock")
        edgeSliderView = PreferenceSliderMenuItemView(title: "Tungsten Edge 钨极")
        super.init()
        configureStatusItem()
        configureMenu()
        refreshCheckmarks()
        refreshUpdateCheckItem()
        // 滑块与「自动隐藏」勾选行同处一个打开着的菜单：菜单开着时值可能被滑块拖动改掉，
        // 只靠 menuWillOpen 刷新会出现勾选与行为相反的窗口期，必须订阅实时同步。
        // sink 用 publisher 发出的新值：@Published 在赋值完成前发布，此刻回读 store 是旧值。
        edgeDelaySubscription = store.$edgeAutoHideDelay
            .removeDuplicates()
            .sink { [weak self] delay in
                self?.edgeSliderView.sync(delay: delay)
                self?.refreshEdgeAutoHideToggleItem(delay: delay)
            }
        nativeDockDelaySubscription = store.$nativeDockAutoHideDelay
            .removeDuplicates()
            .sink { [weak self] delay in
                self?.nativeDockSliderView.sync(delay: delay)
                self?.refreshNativeDockToggleItem(storeDelay: delay)
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

        nativeDockSliderView.onDelayChange = { [weak store] delay in
            store?.setNativeDockAutoHideDelay(delay)
        }
        nativeDockSliderView.onDelayCommit = { [weak self] _ in
            self?.scheduleNativeDockPreferencesConfirmation()
        }
        let nativeDockItem = NSMenuItem()
        nativeDockItem.view = nativeDockSliderView
        menu.addItem(nativeDockItem)
        nativeDockToggleItem.target = self
        // ⌥⌘D 由 macOS 自己持有、恒生效，提示恒显示（不同于钨极行的注册门控）。
        let nativeHint = AutoHideToggleMenuModel.keyEquivalentPresentation(
            isHotKeyRegistered: true,
            shortcut: .nativeDockAutoHide
        )
        nativeDockToggleItem.keyEquivalent = nativeHint.key
        nativeDockToggleItem.keyEquivalentModifierMask = nativeHint.mask
        menu.addItem(nativeDockToggleItem)
        menu.addItem(.separator())

        edgeSliderView.onDelayChange = { [weak store] delay in
            store?.setEdgeAutoHideDelay(delay)
        }
        let edgeItem = NSMenuItem()
        edgeItem.view = edgeSliderView
        menu.addItem(edgeItem)
        edgeAutoHideToggleItem.target = self
        menu.addItem(edgeAutoHideToggleItem)

        menu.addItem(.separator())
        addPinnedFolderItem.target = self
        menu.addItem(addPinnedFolderItem)

        #if DEBUG
        menu.addItem(.separator())
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
        #endif

        menu.addItem(.separator())
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
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        switch (version, build) {
        case let (version?, build?): return "版本 \(version) (\(build))"
        case let (version?, nil): return "版本 \(version)"
        case let (nil, build?): return "版本 (\(build))"
        case (nil, nil): return nil
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        let granted = isAccessibilityTrusted()
        permissionWarningItem.isHidden = granted
        permissionWarningSeparator.isHidden = granted
        // 先把系统实际状态回灌进本地存值（滑杆/勾选经 Combine 订阅自动跟上），再做防御性校准。
        reconcileNativeDockStoreWithSystem()
        refreshCheckmarks()
        refreshUpdateCheckItem()
        nativeDockSliderView.sync(delay: store.nativeDockAutoHideDelay)
        edgeSliderView.sync(delay: store.edgeAutoHideDelay)
        // 防御性校准（实时同步靠 init 里的订阅）：钨极行刷注册门控，系统 Dock 行刷系统实际勾选。
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
        edgeAutoHideToggleItem.state = AutoHideToggleMenuModel.isChecked(delay: delay) ? .on : .off
        let presentation = AutoHideToggleMenuModel.keyEquivalentPresentation(
            isHotKeyRegistered: isToggleHotKeyRegistered(),
            shortcut: toggleHotKeyShortcut
        )
        edgeAutoHideToggleItem.keyEquivalent = presentation.key
        edgeAutoHideToggleItem.keyEquivalentModifierMask = presentation.mask
    }

    private func refreshNativeDockToggleItem(storeDelay: Double) {
        let live = nativeDockPreferencesService.currentAutohideState()?.enabled
        nativeDockToggleItem.state = AutoHideToggleMenuModel.nativeIsChecked(liveAutohide: live, storeDelay: storeDelay) ? .on : .off
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
        let target = AutoHideToggleMenuModel.nativeToggleTarget(
            liveAutohide: nativeDockPreferencesService.currentAutohideState()?.enabled,
            storeDelay: store.nativeDockAutoHideDelay,
            remembered: store.lastEnabledNativeDockAutoHideDelay
        )
        store.setNativeDockAutoHideDelay(target)
        // 复用滑块松手后的同一条应用路径（收起菜单 → defaults 写入 + 重启系统 Dock）。
        scheduleNativeDockPreferencesConfirmation()
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

    @objc private func addPinnedFolder() { onAddPinnedFolder() }

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
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releaseURL)
            }
        case .upToDate(let currentVersion, let latestVersion):
            alert.messageText = "当前已是最新版本"
            alert.informativeText = "当前版本 \(currentVersion)，GitHub 最新正式版为 \(latestVersion)。"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    private func presentUpdateCheckFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "暂时无法检查更新"
        alert.informativeText = "请检查网络连接后重试，也可以直接打开 GitHub 发布页。"
        alert.addButton(withTitle: "打开发布页")
        alert.addButton(withTitle: "好")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(GitHubUpdateChecker.releasesURL)
        }
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func scheduleNativeDockPreferencesConfirmation() {
        menu.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async { [weak self] in
            self?.confirmAndApplyNativeDockPreferences()
        }
    }

    private func confirmAndApplyNativeDockPreferences() {
        guard nativeDockPreferencesService.isAvailable else {
            presentError(title: "系统 Dock 设置失败", message: NativeDockPreferencesError.sandboxed.localizedDescription)
            return
        }

        do {
            try nativeDockPreferencesService.apply(delay: store.nativeDockAutoHideDelay)
        } catch {
            // defaults/killall 是多步非事务序列；任一步失败后都重新读取偏好层，
            // 尽可能让滑杆与勾选回到系统实际值，而不是保留未必写成功的目标值。
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
        alert.runModal()
    }

    @objc private func showDebugConsole() { onShowDebugConsole() }
    @objc private func exportDebugSnapshot() { onExportDebugSnapshot() }
    @objc private func quit() { onQuit() }
}

@MainActor
final class PreferenceSliderMenuItemView: NSView {
    var onDelayChange: ((Double) -> Void)?
    var onDelayCommit: ((Double) -> Void)?

    private let title: String
    private let subtitle: String?
    private let titleVerticalOffset: CGFloat
    private var delay = 0.0
    private var commitTracker = PreferenceSliderCommitTracker()
    private var displayString = "0.0s"
    private let leftEndpointDot = EndpointDotView()
    private let rightEndpointDot = EndpointDotView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let delayLabel = NSTextField(labelWithString: "")
    private let leftEndpointLabel = NSTextField(labelWithString: "常驻")
    private let rightEndpointLabel = NSTextField(labelWithString: "不唤醒")
    private let slider = MenuTrackingSlider()

    init(title: String, subtitle: String? = nil, titleVerticalOffset: CGFloat = 0) {
        self.title = title
        self.subtitle = subtitle
        self.titleVerticalOffset = titleVerticalOffset
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 92))
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

        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 10)
        // secondary（与标题同色系）而非 tertiary：快捷键提示要读得清，层级差靠 10pt/12pt 字号差撑住。
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.isHidden = subtitle == nil
        addSubview(subtitleLabel)

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
            self?.commitDelayIfChanged()
        }
        addSubview(slider)

        setAccessibilityRole(.group)
    }

    override func layout() {
        super.layout()
        let dotSize: CGFloat = 8
        let hasSubtitle = subtitle != nil
        let contentX = StatusMenuLayout.textInsetX
        let contentWidth = bounds.width - contentX - StatusMenuLayout.trailingInsetX
        let titleY = bounds.height - 30 + titleVerticalOffset
        let labelY: CGFloat = 28
        let sliderY: CGFloat = 10
        if hasSubtitle {
            let titleWidth = min(contentWidth, max(ceil(titleLabel.intrinsicContentSize.width), 76))
            let subtitleGap: CGFloat = 2
            let subtitleX = contentX + titleWidth + subtitleGap
            titleLabel.frame = NSRect(x: contentX, y: titleY, width: titleWidth, height: 20)
            subtitleLabel.frame = NSRect(x: subtitleX, y: titleY, width: max(0, contentWidth - titleWidth - subtitleGap), height: 18)
        } else {
            titleLabel.frame = NSRect(x: contentX, y: titleY, width: contentWidth, height: 20)
            subtitleLabel.frame = NSRect(x: contentX, y: titleY, width: 0, height: 18)
        }

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

    private func commitDelayIfChanged() {
        guard let committedDelay = commitTracker.commitIfChanged(currentDelay: delay) else { return }
        onDelayCommit?(committedDelay)
    }

    private func updateDisplay() {
        let index = slider.integerValue
        displayString = displayString(for: index)
        delay = AppSettingsStore.delayFromSliderIndex(index)
        titleLabel.stringValue = title
        subtitleLabel.stringValue = subtitle ?? ""
        delayLabel.stringValue = displayString
        // 两端「常驻/不唤醒」小字恒定可见，端点圆点在选中时变实心强调；
        // 中间数值文字到达端点时改为隐藏，避免和恒定可见的端点小字重复显示同一个词。
        let isAtLeftEnd = index == 0
        let isAtRightEnd = index == AppSettingsStore.sliderIndexMax
        delayLabel.isHidden = isAtLeftEnd || isAtRightEnd
        leftEndpointDot.isOn = isAtLeftEnd
        rightEndpointDot.isOn = isAtRightEnd
        var accessibilityParts = [title]
        if let subtitle {
            accessibilityParts.append(subtitle)
        }
        accessibilityParts.append(displayString)
        setAccessibilityLabel(accessibilityParts.joined(separator: "，"))
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onTrackingStarted?()
        super.mouseDown(with: event)
        onTrackingEnded?()
    }

    override func accessibilityValue() -> Any? {
        displayString
    }
}

struct PreferenceSliderCommitTracker {
    private var startDelay: Double?

    mutating func begin(currentDelay: Double) {
        startDelay = currentDelay
    }

    mutating func commitIfChanged(currentDelay: Double) -> Double? {
        defer { startDelay = nil }
        guard let startDelay, startDelay != currentDelay else { return nil }
        return currentDelay
    }
}
