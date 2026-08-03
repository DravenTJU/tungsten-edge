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

    /// 系统 Dock 这一组的分组标题（不可点）。两条滑块长得一模一样，没有标题分不清谁管谁。
    ///
    /// ⌥⌘D 以**纯文字**写进标题，不设 `keyEquivalent`：这一行本就不可点，设了会被菜单捕获，
    /// 也会让禁用行看起来能点。这个键归 macOS 持有、恒生效，我们只是告诉用户它在——
    /// 删掉显隐命令之后，它就是「把 Dock 临时叫回来」的一键入口。
    static let nativeDockSectionTitle = "系统 Dock（⌥⌘D 显隐）"

    /// 滑块档位的显示名。滑块本体与确认行必须共用这一份口径，
    /// 否则确认行说的档位和滑块上显示的不是一回事。
    static func delayDisplayName(sliderIndex index: Int) -> String {
        switch index {
        case 0:
            return "常驻"
        case AppSettingsStore.sliderIndexMax:
            return "不唤醒"
        default:
            return String(format: "%.1fs", AppSettingsStore.delayFromSliderIndex(index))
        }
    }

    /// 系统 Dock 的每次写入都以 `killall Dock` 收尾，屏幕必然闪一下——这一下消除不了
    /// （改 `autohide-delay` 在 macOS 上只有这条生效路径），只能让它发生在用户主动确认**之后**，
    /// 预期之中的闪不觉得怪。所以滑块不再自动提交，草稿与已生效值不同时才浮出这一行。
    ///
    /// 比**整数档位**而不是浮点值：滑块本来就只能停在档位上，比浮点会被表示误差咬到。
    static func shouldShowNativeApply(draft: Double, applied: Double) -> Bool {
        AppSettingsStore.sliderIndexFromDelay(draft) != AppSettingsStore.sliderIndexFromDelay(applied)
    }

    /// 标题带上目标档位是有意的：它同时在提醒「你拖到的这一档现在还没生效」。
    static func nativeApplyTitle(draft: Double) -> String {
        let name = delayDisplayName(sliderIndex: AppSettingsStore.sliderIndexFromDelay(draft))
        return "应用「\(name)」（Dock 会重启一下）"
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

/// 系统 Dock 滑块的草稿账本。记的是**改动前**的值：写入是 defaults + killall 的多步非事务序列，
/// 失败时要靠 previous 回滚本地镜像（见 `AutoHideToggleMenuModel.resolvedStoreDelay` 四象限）。
///
/// 提交源现在只有确认行一个（滑块本身不再自动写系统），但 `consume()` 的**原子**语义保留：
/// 它同时承担「值没变就不写」「没有起点就不写」两道闸，重复调用一律拿到 nil。
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
    private let hoverStyleItem = NSMenuItem(title: "鼠标悬停显示应用名", action: #selector(toggleHoverStyle), keyEquivalent: "")
    private let windowLiftItem = NSMenuItem(title: "最大化窗口避开任务条", action: #selector(toggleWindowLift), keyEquivalent: "")
    private let dockSizeItem = NSMenuItem(title: "任务条大小", action: nil, keyEquivalent: "")
    private var dockSizeItems: [DockSize: NSMenuItem] = [:]
    /// 分组标题，恒不可点（title 在 configureMenu 里落）。
    private let nativeDockSectionItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    /// 滑块草稿的唯一提交入口，默认隐藏。承载的是**真按钮**而不是普通菜单文字行：
    /// 做成菜单行时它和邻居（「打开系统 Dock 设置…」）视觉权重一样，混在菜单里不显眼，
    /// 而用户刚拖完滑块视线还在滑块上，错过它就从「会闪但生效了」变成
    /// 「以为设好了其实没生效」——比原来的闪更糟（owner 2026-08-02 验收时指出）。
    private let nativeDockApplyItem = NSMenuItem()
    private let nativeDockApplyRow = NativeDockApplyRowView()
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

        nativeDockSectionItem.title = AutoHideToggleMenuModel.nativeDockSectionTitle
        nativeDockSectionItem.isEnabled = false
        menu.addItem(nativeDockSectionItem)

        // 系统 Dock 滑块**不接** store：`setNativeDockAutoHideDelay` 一调用就把 active + remembered
        // 一起落盘，而系统那边要等用户点确认行才写，拖到一半的值不该变成持久状态。
        // onDraftChange 只用来刷新确认行，不碰任何持久状态。
        nativeDockSliderView.onDraftChange = { [weak self] draft in
            self?.refreshNativeDockApplyItem(draft: draft)
        }
        nativeDockSliderView.onDelayCommit = { [weak self] previous, target in
            self?.commitNativeDockDelay(previous: previous, target: target)
        }
        let nativeDockSliderItem = NSMenuItem()
        nativeDockSliderItem.view = nativeDockSliderView
        menu.addItem(nativeDockSliderItem)

        nativeDockApplyRow.onApply = { [weak self] in
            self?.applyNativeDockDelay()
        }
        nativeDockApplyItem.view = nativeDockApplyRow
        nativeDockApplyItem.isHidden = true
        menu.addItem(nativeDockApplyItem)

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

        hoverStyleItem.target = self
        menu.addItem(hoverStyleItem)

        // 自动隐藏档位下避让本来就不工作（只在常驻可见时抬窗口），但这一项**恒可点**：
        // 它是偏好不是当前状态，置灰只会让人以为功能没了（owner 2026-08-03 定）。
        windowLiftItem.target = self
        menu.addItem(windowLiftItem)

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
        // 没点确认就关菜单 = 作废：什么都不写，下次打开一切从系统真值重新起步。
        // （否则「随手拨一下看看」也会招来一次 killall Dock——关个菜单屏幕突然闪一下，
        // 正是这次要消除的怪异感。）
        //
        // **作废放在「打开时」而不是 `menuDidClose`**，是为了不依赖确认控件的形态。
        // 现在的确认是自定义 view 里的 `NSButton`，action 直接发送，放哪儿都安全；
        // 但只要有人把它改回普通 `NSMenuItem`，`menuDidClose` 就会变成陷阱——AppKit 的顺序是
        // 先关菜单、`menuDidClose` 回调、**然后**才发送菜单项 action，草稿会赶在确认之前
        // 被清空，`commitDraft()` 拿到 nil，整个确认功能静默失效（本轮踩过并修掉）。
        nativeDockSliderView.discardDraft()
        nativeDockSliderView.sync(delay: store.nativeDockAutoHideDelay)
        nativeDockApplyItem.isHidden = true
        edgeSliderView.sync(delay: store.edgeAutoHideDelay)
        refreshEdgeAutoHideToggleItem(delay: store.edgeAutoHideDelay)
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

    /// 草稿与已生效值不同才浮出确认行。已生效值取本地镜像——`menuWillOpen` 刚把它对齐过系统真值。
    private func refreshNativeDockApplyItem(draft: Double) {
        let shouldShow = AutoHideToggleMenuModel.shouldShowNativeApply(
            draft: draft,
            applied: store.nativeDockAutoHideDelay
        )
        nativeDockApplyItem.isHidden = !shouldShow
        if shouldShow {
            // 按钮标题恒为「应用」，目标档位只进 accessibility——滑块上已经用数值和端点圆点
            // 表达过一次，按钮里再重复反而挤；但 VoiceOver 只听得到这一句，必须带上档位。
            nativeDockApplyRow.updateTarget(description: AutoHideToggleMenuModel.nativeApplyTitle(draft: draft))
            // 上一轮可能停在 hover 态，而这一轮浮出时鼠标还在滑块上，不在按钮上。
            nativeDockApplyRow.resetInteractionState()
        }
    }

    @objc private func toggleEdgeAutoHideModeFromMenu() {
        store.toggleEdgeAutoHideMode()
    }

    private func applyNativeDockDelay() {
        nativeDockSliderView.commitDraft()
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
        hoverStyleItem.state = store.hoverStyle.isExpressive ? .on : .off
        windowLiftItem.state = store.windowLiftEnabled ? .on : .off
        for (size, item) in dockSizeItems {
            item.state = store.dockSize == size ? .on : .off
        }
    }

    @objc private func toggleShowShelf() {
        store.setShowShelf(!store.showShelf)
        refreshCheckmarks()
    }

    /// 勾选 = 标准悬停（放大图标 + 冒名字 + 文件夹格放大），取消 = 完全静止。
    /// 标题只提了「应用名」，是 owner 有意选的短名字，不是漏写——别据此缩小行为范围（见 `Docs/27`）。
    @objc private func toggleHoverStyle() {
        store.setHoverStyle(store.hoverStyle.isExpressive ? .quiet : .standard)
        refreshCheckmarks()
    }

    /// 勾选 = 前台铺满窗口的底边抬到任务条上方；取消勾选立刻停止避让，
    /// 并把已经抬起来的窗口还原回原生尺寸（`WindowLiftAvoidanceController.stop()` 全套）。
    @objc private func toggleWindowLift() {
        store.setWindowLiftEnabled(!store.windowLiftEnabled)
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

    /// 系统 Dock 的唯一写入路径。先收菜单——写入以 `killall Dock` 收尾，
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
        // 写完之后草稿即已生效值，确认行没有存在意义了（菜单此时已收起，这里只是把状态摆正，
        // 免得下次打开菜单前有人读到过期的可见性）。
        nativeDockSliderView.sync(delay: resolved)
        nativeDockApplyItem.isHidden = true

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
    /// 草稿落定（鼠标松手，或键盘每调一格）。确认型滑块用它刷新确认行，
    /// **绝不能拿来写任何持久状态**——草稿的全部意义就是「还没生效」。
    var onDraftChange: ((Double) -> Void)?
    /// 确认提交。**设了它就启用草稿机制**：系统 Dock 每次写入都以 `killall Dock` 收尾、
    /// 屏幕必然闪一下，那一下只能发生在用户主动确认之后。
    var onDelayCommit: ((_ previous: Double, _ target: Double) -> Void)?

    private let accessibilityTitle: String
    private var delay = 0.0
    private var commitTracker = PreferenceSliderCommitTracker()
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
            // 拖动全程不碰确认行：每经过一格就增删一次菜单项会让整个菜单反复重排。
            // 松手才刷新这一次。
            guard let self else { return }
            self.onDraftChange?(self.delay)
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
        // 键盘 / VoiceOver 没有「松手」这个时刻，只能当场刷新确认行。它们因此和鼠标
        // 走同一条确认路径，不再需要 debounce 自动提交，也就不会再被静默丢弃。
        if !slider.isMouseTracking {
            onDraftChange?(delay)
        }
    }

    /// 用户按下确认行。**唯一**的提交入口——滑块自己在任何情况下都不写系统。
    func commitDraft() {
        guard let commit = commitTracker.consume() else { return }
        onDelayCommit?(commit.previous, commit.target)
    }

    /// 未确认的草稿作废，滑块拨回草稿开始前的已生效值。
    /// 调用点是**菜单打开时**（`menuWillOpen`），不是关闭时——理由见那里。
    /// 已被 `commitDraft` 消费过就拿到 nil，不会把刚确认的新值又拨回去。
    func discardDraft() {
        guard let discarded = commitTracker.consume() else { return }
        sync(delay: discarded.previous)
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

    /// 与确认行共用一份档位口径，免得确认行说的和滑块上显示的不是一回事。
    private func displayString(for index: Int) -> String {
        AutoHideToggleMenuModel.delayDisplayName(sliderIndex: index)
    }
}

/// 系统 Dock 滑块的确认按钮行。做成**按钮**而不是普通菜单文字行是有意的：
/// 菜单行和它的邻居视觉权重相同，用户刚拖完滑块、视线还在滑块上，很容易整行错过；
/// 一旦错过就直接关菜单，结果是「以为设好了其实没生效」——比原本那一下闪更糟。
/// 按钮的形态本身就在说「这是要点的东西」。
///
/// 左侧那句小灰字不是装饰：`killall Dock` 的闪消除不了，提前说明白它才不显得怪。
@MainActor
final class NativeDockApplyRowView: NSView {
    var onApply: (() -> Void)?

    private let hintLabel = NSTextField(labelWithString: "Dock 会重启一下")
    private let applyButton = MenuActionButton(title: "应用")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 42))
        autoresizingMask = [.width]
        configureSubviews()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 按钮标题恒为「应用」，目标档位只走 accessibility：滑块上已经显示过档位，
    /// 但 VoiceOver 用户听不到滑块，这句是他们唯一的信息来源。
    func updateTarget(description: String) {
        applyButton.setAccessibilityLabel(description)
        setAccessibilityLabel(description)
    }

    /// 每次浮出都从静息态开始：上一轮可能停在 hover 态，而菜单重开时鼠标未必还在按钮上。
    func resetInteractionState() {
        applyButton.resetInteractionState()
    }

    private func configureSubviews() {
        wantsLayer = true

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.setAccessibilityElement(false)
        addSubview(hintLabel)

        applyButton.onClick = { [weak self] in
            self?.onApply?()
        }
        addSubview(applyButton)

        setAccessibilityRole(.group)
    }

    override func layout() {
        super.layout()
        let contentX = StatusMenuLayout.textInsetX
        let rightEdge = bounds.width - StatusMenuLayout.trailingInsetX

        let buttonSize = applyButton.intrinsicContentSize
        applyButton.frame = NSRect(
            x: rightEdge - buttonSize.width,
            y: (bounds.height - buttonSize.height) / 2,
            width: buttonSize.width,
            height: buttonSize.height
        )

        let hintWidth = max(0, applyButton.frame.minX - 8 - contentX)
        hintLabel.frame = NSRect(x: contentX, y: (bounds.height - 14) / 2, width: hintWidth, height: 14)
    }

}

/// 菜单里的强调按钮，**自绘**。
///
/// 用 `NSButton` 试过：一旦设了 `bezelColor` 把底色改成强调色，AppKit 自己那套按下变暗
/// 基本被盖住；而菜单打开时 run loop 处在事件追踪模式，标准按钮的 hover / 按下态在这里
/// 都不可靠——按上去像块死图（owner 2026-08-02 报「按钮怎么没有反馈交互」）。
/// 自绘之后三态完全可控：静息 / 悬停（提亮）/ 按下（压暗）。
final class MenuActionButton: NSView {
    var onClick: (() -> Void)?

    private let title: String
    private let iconView = NSImageView()
    private let titleLabel: NSTextField
    private var isHovering = false { didSet { if isHovering != oldValue { needsDisplay = true } } }
    private var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }

    private static let cornerRadius: CGFloat = 6
    private static let horizontalPadding: CGFloat = 12
    private static let iconTitleGap: CGFloat = 5
    private static let height: CGFloat = 25

    /// 通透而不是实心（owner 2026-08-02 定）：菜单本身是半透明材质，压一块强调色实心
    /// 在上面显得又厚又重。改成淡强调色底 + 强调色字，颜色还在、分量降下来。
    private static let restingAlpha: CGFloat = 0.16
    private static let hoverAlpha: CGFloat = 0.30
    private static let pressedAlpha: CGFloat = 0.42

    init(title: String) {
        self.title = title
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: NSRect(x: 0, y: 0, width: 92, height: Self.height))
        wantsLayer = true

        // 字重用常规（owner 2026-08-02 定）；文字取强调色本身而不是白色——
        // 白字要靠实心底才立得住，通透底上只有强调色字才够清楚。
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .controlAccentColor
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)

        iconView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        iconView.contentTintColor = .controlAccentColor
        iconView.setAccessibilityElement(false)
        addSubview(iconView)

        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let titleWidth = titleLabel.intrinsicContentSize.width
        let iconWidth = iconView.image?.size.width ?? 0
        return NSSize(
            width: Self.horizontalPadding * 2 + iconWidth + Self.iconTitleGap + titleWidth,
            height: Self.height
        )
    }

    /// 菜单里的自定义 view 不属于 key window，不重写这个第一次点击会被整个吞掉——
    /// 用户会以为按钮坏了。`MenuTrackingSlider` 同理。
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 子视图（文字、图标）不能把鼠标事件截走，否则按钮中间一块点不动。
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    func resetInteractionState() {
        isHovering = false
        isPressed = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // `.activeAlways`：菜单面板不是 key window，`.activeInKeyWindow` 在这里永远不触发。
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    /// 菜单事件追踪期间 `mouseUp` 不会自然回到这里，必须自己跑一轮 tracking——
    /// 这和 `MenuTrackingSlider` 靠 `super.mouseDown` 阻塞到松手是同一个道理。
    /// 期间跟踪指针在不在按钮内：拖出去再松手 = 取消，和系统按钮的行为一致。
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        var releasedInside = true

        window?.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { trackedEvent, stop in
            guard let trackedEvent else {
                stop.pointee = true
                return
            }
            let local = self.convert(trackedEvent.locationInWindow, from: nil)
            releasedInside = self.bounds.contains(local)
            self.isPressed = releasedInside
            if trackedEvent.type == .leftMouseUp {
                stop.pointee = true
            }
        }

        isPressed = false
        isHovering = releasedInside
        if releasedInside {
            onClick?()
        }
    }

    /// 单测入口：真实路径是上面那轮 tracking loop，测试环境跑不了事件循环。
    func performClickForTesting() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 三态只改透明度，不改色相：底始终是同一个强调色，按下去只是"更实"一点。
        let alpha: CGFloat
        if isPressed {
            alpha = Self.pressedAlpha
        } else if isHovering {
            alpha = Self.hoverAlpha
        } else {
            alpha = Self.restingAlpha
        }
        let shape = NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSColor.controlAccentColor.withAlphaComponent(alpha).setFill()
        shape.fill()
    }

    override func layout() {
        super.layout()
        let iconSize = iconView.image?.size ?? .zero
        let titleSize = titleLabel.intrinsicContentSize
        let contentWidth = iconSize.width + Self.iconTitleGap + titleSize.width
        let startX = (bounds.width - contentWidth) / 2

        iconView.frame = NSRect(
            x: startX,
            y: (bounds.height - iconSize.height) / 2,
            width: iconSize.width,
            height: iconSize.height
        )
        titleLabel.frame = NSRect(
            x: iconView.frame.maxX + Self.iconTitleGap,
            y: (bounds.height - titleSize.height) / 2,
            width: titleSize.width,
            height: titleSize.height
        )
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
