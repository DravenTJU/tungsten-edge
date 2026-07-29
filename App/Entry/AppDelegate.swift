import AppKit
import Combine
import SwiftUI
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var runtime = AppRuntime()
    let drawerStore = DrawerStore()
    let messagingStore = MessagingAppStore()
    let badgeStore = BadgeStore()
    let keptAppStore = KeptAppStore()
    lazy var stripOrderStore = StripOrderStore(keptIDsProvider: { [keptAppStore] in Set(keptAppStore.bundleIDs) })
    let drawerOrderStore = DrawerOrderStore()
    let settingsStore = AppSettingsStore()
    let pinnedFolderStore = PinnedFolderStore()
    let shelfStore = ShelfStore()
    let runningApplicationStore = RunningApplicationStore()
    private(set) lazy var appMembershipController = AppMembershipController(
        keptAppStore: keptAppStore,
        drawerStore: drawerStore,
        messagingStore: messagingStore
    )
    /// lazy：sortOrderProvider 要引用 pinnedFolderStore（封面跟随该文件夹当前排序的第一个文件）。
    private(set) lazy var folderCoverStore = PinnedFolderCoverStore(
        sortOrderProvider: { [pinnedFolderStore] path in pinnedFolderStore.sortOrder(for: path) }
    )
    private var panelCoordinator: PanelCoordinator?
    private var windowLiftAvoidanceController: WindowLiftAvoidanceController?
    /// 常驻切换全局快捷键。回调只切设置（经 settingsStore），不经过 panelCoordinator——
    /// 后者在权限引导完成前是 nil，settingsStore 从 AppDelegate 构造起即存在。
    private var edgeToggleHotKey: GlobalHotKeyMonitor?
    private var terminationTask: Task<Void, Never>?
    private var debugWindow: NSWindow?
    private var permissionWindow: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var messagingAutoRegisterSubscription: AnyCancellable?
    private var permissionModel: AccessibilityPermissionModel?
    private lazy var statusMenuController = StatusMenuController(
        store: settingsStore,
        launchAtLoginService: LaunchAtLoginService(),
        nativeDockPreferencesService: NativeDockPreferencesService(),
        updateChecker: GitHubUpdateChecker(),
        isAccessibilityTrusted: { PermissionService().hasRequiredPermissions() },
        onShowDebugConsole: { [weak self] in self?.showDebugConsole() },
        onExportDebugSnapshot: { [weak self] in self?.exportDebugSnapshot() },
        onQuit: { NSApp.terminate(nil) },
        toggleHotKeyShortcut: .edgeAutoHideMode,
        isToggleHotKeyRegistered: { [weak self] in self?.edgeToggleHotKey?.isRegistered ?? false }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 行缓冲 stdout：从命令行/后台启动时，print() 输出到文件默认是块缓冲，
        // 日志要攒满缓冲区才落盘。改成行缓冲后每条 print 立即写出，便于实时读日志。
        setvbuf(stdout, nil, _IOLBF, 0)

        terminateOtherInstances()

        // 先注册热键再建状态菜单：菜单构建时要读注册状态决定是否显示快捷键提示。
        // Carbon 热键不依赖辅助功能权限，不用等权限引导分支。
        let hotKey = GlobalHotKeyMonitor(shortcut: .edgeAutoHideMode) { [weak self] in
            self?.settingsStore.toggleEdgeAutoHideMode()
        }
        edgeToggleHotKey = hotKey
        let hotKeyStatus = hotKey.start()
        if hotKeyStatus != .registered {
            Logger(subsystem: "com.caye.macosdockcc.v2", category: "hotkey")
                .warning("常驻切换全局快捷键注册失败：\(String(describing: hotKeyStatus), privacy: .public)，本次启动不重试")
        }

        _ = statusMenuController

        if AXIsProcessTrusted() {
            NSApp.setActivationPolicy(.accessory)
            startApp()
        } else {
            // 没有权限时任务条不会创建任何面板，保持 accessory 会让用户只能看到一个
            // 不一定明显的状态栏图标；先用普通应用策略把权限引导窗口带到前台。
            NSApp.setActivationPolicy(.regular)
            requestAccessibilityPermission()
        }
    }

    /// 同一个 bundle id 的另一份包（`/Applications` 正式包 vs 构建目录里的开发包）可以
    /// 同时运行，屏幕上就会出现两条一模一样的任务条，测到的是哪个版本谁也说不清——
    /// 2026-07-21 因此把一个其实没验证过的修复判成「不行」并整个回退。
    ///
    /// 采取「后启动的接管」：新实例踢掉旧实例。反过来（新的自己退出）会挡住开发时的
    /// 验证构建，也和 `Scripts/build_and_run.sh` 先 pkill 再启动的既有行为矛盾。
    /// 用礼貌的 `terminate()` 而不是强杀，让旧实例的 `stopAndRestore` 把被抬起的窗口
    /// 还原回去；只有它迟迟不退时才强制结束，避免"两个任务条"这个原始症状复发。
    private func terminateOtherInstances() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID && !$0.isTerminated }
        guard !others.isEmpty else { return }

        let logger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "instance")
        for app in others {
            logger.warning("""
                发现另一个钨极实例，终止它：pid=\(app.processIdentifier, privacy: .public) \
                path=\(app.bundleURL?.path ?? "(unknown)", privacy: .public)
                """)
            app.terminate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            for app in others where !app.isTerminated {
                logger.error("旧实例 pid=\(app.processIdentifier, privacy: .public) 3 秒内未退出，强制结束")
                app.forceTerminate()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 收尾等待（stopAndRestore）期间事件循环还在跑：先切断热键输入，避免设置被继续切换。
        edgeToggleHotKey?.stop()
        guard let controller = windowLiftAvoidanceController else { return .terminateNow }
        guard terminationTask == nil else { return .terminateLater }

        terminationTask = Task { @MainActor [weak self] in
            await controller.stopAndRestore()
            self?.terminationTask = nil
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        edgeToggleHotKey?.stop()
        windowLiftAvoidanceController?.stop()
        runtime.stop()
    }

    private func requestAccessibilityPermission() {
        showPermissionWindow()
        // 系统原生提示框：把本应用注册进辅助功能列表，并在首次请求时提示用户打开设置。
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        let model = AccessibilityPermissionModel()
        model.onGranted = { [weak self] in self?.handlePermissionGranted() }
        permissionModel = model
        model.startPolling()
    }

    private func handlePermissionGranted() {
        permissionModel?.stop()
        permissionModel = nil
        permissionWindow?.orderOut(nil)
        permissionWindow?.close()
        permissionWindow = nil
        NSApp.setActivationPolicy(.accessory)
        startApp()
    }

    private func showPermissionWindow() {
        if let permissionWindow {
            permissionWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 250),
            styleMask: [.titled, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Tungsten Edge 钨极"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PermissionOnboardingView(
            onOpenSettings: { [weak self] in self?.openAccessibilitySettings() },
            onQuit: { NSApp.terminate(nil) }
        ))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        permissionWindow = window
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func startApp() {
        appMembershipController.reconcileInvalidMemberships()
        runningApplicationStore.start()
        runtime.start()

        // Auto tier of the messaging list: register an app only when it both matches the
        // whitelist / social-networking category **and** currently has an identifiable main
        // window, then seed kept on first registration (default-keep). Kept no longer excludes
        // messaging, so there is no kept filter.
        //
        // The window snapshot is combined in because the capability gate needs titles — the
        // process store alone cannot tell whether the zone can represent the app. Registration
        // is once-and-for-all (see `MessagingAppStore.autoRegister`), so the "identifiable right
        // now" reading is only ever consumed for apps not yet in the list; existing members are
        // never re-tested and therefore never flap out of the zone.
        messagingAutoRegisterSubscription = runningApplicationStore.$runningBundleIDs
            .combineLatest(runtime.$snapshot)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] running, snapshot in
                guard let self else { return }
                let identifiable = MessagingZoneAdmission.mainWindowIdentifiableBundleIDs(
                    windows: StripItem.items(from: snapshot).map {
                        .init(bundleID: $0.bundleIdentifier ?? "",
                              title: $0.title,
                              isAppLevelFallback: $0.isAppLevelFallback)
                    },
                    titleMatchesAppName: { title, bundleID in
                        AppDisplayNameResolver.titleMatchesAppName(title, bundleID: bundleID)
                    }
                )
                self.appMembershipController.autoRegisterMessaging(
                    runningBundleIDs: running,
                    mainWindowIdentifiableBundleIDs: identifiable
                )
            }

        let coordinator = PanelCoordinator(
            runtime: runtime,
            drawerStore: drawerStore,
            messagingStore: messagingStore,
            badgeStore: badgeStore,
            stripOrderStore: stripOrderStore,
            drawerOrderStore: drawerOrderStore,
            settingsStore: settingsStore,
            pinnedFolderStore: pinnedFolderStore,
            folderCoverStore: folderCoverStore,
            shelfStore: shelfStore,
            keptAppStore: keptAppStore,
            runningApplicationStore: runningApplicationStore,
            appMembershipController: appMembershipController
        )
        panelCoordinator = coordinator
        runtime.onToggleDrawer = { [weak coordinator] in coordinator?.toggleDrawer() }
        coordinator.onAddFolder = { [weak self] in self?.presentAddPinnedFolderPanel() }
        coordinator.start()
        let windowLiftAvoidanceController = WindowLiftAvoidanceController(host: coordinator)
        self.windowLiftAvoidanceController = windowLiftAvoidanceController
        windowLiftAvoidanceController.start()
        badgeStore.start()
        // 探针结论（2026-07-06,阶段0探针3）：访达窗口 AX 属性表虽列有 AXDocument 但恒无值
        // （kAXErrorNoValue），AXProxy/AXTitleUIElement 也只有文件夹名无路径——「拖任务条访达
        // 窗口图标固定文件夹」不可行,已按预案砍掉,拖入固定区只走真实文件 URL（系统拖放）。
    }

    /// 文件夹 chip / 中转格右键的「添加固定文件夹…」入口。
    /// accessory app 必须先 activate，否则 NSOpenPanel 不上前台。
    func presentAddPinnedFolderPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "固定"
        panel.message = "选择要固定到任务条的文件夹"
        if panel.runModal() == .OK {
            for url in panel.urls { pinnedFolderStore.add(url.path) }
        }
    }

    func exportDebugSnapshot() {
        runtime.exportDebugSnapshot()
    }

    func showDebugConsole() {
        if let existing = debugWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "任务条调试台"
        window.contentView = NSHostingView(rootView: DebugConsoleView().environmentObject(runtime))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        debugWindow = window
    }

}
