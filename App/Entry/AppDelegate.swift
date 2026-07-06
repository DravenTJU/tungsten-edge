import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var runtime = AppRuntime()
    let drawerStore = DrawerStore()
    let messagingStore = MessagingAppStore()
    let launchFavoriteStore = LaunchFavoriteStore()
    let badgeStore = BadgeStore()
    let stripOrderStore = StripOrderStore()
    let drawerOrderStore = DrawerOrderStore()
    let settingsStore = AppSettingsStore()
    let pinnedFolderStore = PinnedFolderStore()
    let shelfStore = ShelfStore()
    /// lazy：sortOrderProvider 要引用 pinnedFolderStore（封面跟随该文件夹当前排序的第一个文件）。
    private(set) lazy var folderCoverStore = PinnedFolderCoverStore(
        sortOrderProvider: { [pinnedFolderStore] path in pinnedFolderStore.sortOrder(for: path) }
    )
    private var panelCoordinator: PanelCoordinator?
    private var debugWindow: NSWindow?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var messagingAutoRegisterSubscription: AnyCancellable?
    private var permissionModel: AccessibilityPermissionModel?
    private lazy var statusMenuController = StatusMenuController(
        store: settingsStore,
        launchAtLoginService: LaunchAtLoginService(),
        nativeDockPreferencesService: NativeDockPreferencesService(),
        isAccessibilityTrusted: { PermissionService().hasRequiredPermissions() },
        onShowDebugConsole: { [weak self] in self?.showDebugConsole() },
        onExportDebugSnapshot: { [weak self] in self?.exportDebugSnapshot() },
        onQuit: { NSApp.terminate(nil) },
        onAddPinnedFolder: { [weak self] in self?.presentAddPinnedFolderPanel() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 行缓冲 stdout：从命令行/后台启动时，print() 输出到文件默认是块缓冲，
        // 日志要攒满缓冲区才落盘。改成行缓冲后每条 print 立即写出，便于实时读日志。
        setvbuf(stdout, nil, _IOLBF, 0)
        NSApp.setActivationPolicy(.accessory)
        _ = statusMenuController

        // 调试旗：本地签名的开发版无法用 tccutil 可靠撤销辅助功能权限，
        // 设 DOCK_FORCE_ONBOARDING=1 可强制展示权限引导窗口（演示/截图用），
        // 窗口停在真实新用户看到的「待开启」状态。
        if AXIsProcessTrusted() {
            startApp()
        } else {
            requestAccessibilityPermission()
        }
    }

    private func requestAccessibilityPermission() {
        // 系统原生提示框：既弹出"打开系统设置"按钮，又把本应用注册进辅助功能列表。
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)

        let model = AccessibilityPermissionModel()
        model.onGranted = { [weak self] in self?.handlePermissionGranted() }
        permissionModel = model
        model.startPolling()
    }

    private func handlePermissionGranted() {
        permissionModel?.stop()
        permissionModel = nil
        startApp()
    }

    private func startApp() {
        runtime.start()

        // Auto tier of the messaging list: whenever the snapshot updates, register any
        // running app that matches the whitelist / social-networking category.
        // Launch favorites are excluded: 待启动 is an explicit membership and the four
        // memberships are mutually exclusive — auto detection must not pull a
        // just-registered favorite back into the messaging zone.
        messagingAutoRegisterSubscription = runtime.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                let running = Set(snapshot.windows.values.compactMap(\.bundleIdentifier))
                    .filter { !self.launchFavoriteStore.contains($0) }
                self.messagingStore.autoRegister(runningBundleIDs: running)
            }

        let coordinator = PanelCoordinator(runtime: runtime, drawerStore: drawerStore, messagingStore: messagingStore, launchFavoriteStore: launchFavoriteStore, badgeStore: badgeStore, stripOrderStore: stripOrderStore, drawerOrderStore: drawerOrderStore, settingsStore: settingsStore, pinnedFolderStore: pinnedFolderStore, folderCoverStore: folderCoverStore, shelfStore: shelfStore)
        panelCoordinator = coordinator
        runtime.onToggleDrawer = { [weak coordinator] in coordinator?.toggleDrawer() }
        coordinator.onAddFolder = { [weak self] in self?.presentAddPinnedFolderPanel() }
        coordinator.start()
        badgeStore.start()
        // 探针结论（2026-07-06,阶段0探针3）：访达窗口 AX 属性表虽列有 AXDocument 但恒无值
        // （kAXErrorNoValue），AXProxy/AXTitleUIElement 也只有文件夹名无路径——「拖任务条访达
        // 窗口图标固定文件夹」不可行,已按预案砍掉,拖入固定区只走真实文件 URL（系统拖放）。
    }

    /// 「添加固定文件夹…」统一入口（状态菜单 + 文件夹 chip 右键共用）。
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
