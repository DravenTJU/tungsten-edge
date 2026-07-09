import AppKit
import os
import SwiftUI

/// A chip that represents an app by bundle identifier rather than a concrete window.
/// Renders the three launcher states (not running / running-no-window / running-hidden)
/// and handles tap-to-launch, tap-to-reopen, and the launch bounce animation.
///
/// Shared by the drawer (collected apps, scale 0.7) and the main strip (pinned
/// messaging apps, scale 1.0). Call-site differences are injected via
/// `membershipItems` (移回任务栏 / 取消固定 / 取消标记消息应用) + `menuMode`.

/// 一条成员 / 管理菜单项（标签 + 动作）。LauncherChip 右键菜单末尾按序渲染，
/// 可多项——共存图标（既收纳又固定）同时给「移回任务栏」+「取消固定」。
struct LauncherMembershipItem {
    let label: String
    let action: () -> Void
}

struct LauncherChip: View {
    let bundleID: String
    let isRunning: Bool   // derived from runtime.snapshot by the parent view
    let isHidden: Bool    // derived from runtime.snapshot by the parent view
    var scale: CGFloat = 0.7
    /// Drawer chips dim by run/hidden state; pinned messaging chips on the strip
    /// stay full-opacity (product decision: "always reachable", not degraded).
    var dimsWhenInactive: Bool = true
    /// 成员 / 管理菜单项（右键菜单末尾），如「移回任务栏」「取消固定」「取消标记消息应用」。
    /// 空数组 = 无成员项。共存图标可同时含「移回任务栏」+「取消固定」两项。
    var membershipItems: [LauncherMembershipItem] = []
    /// 菜单模式：`.full` 运行 / 收纳图标完整菜单；`.removeOnly` 纯固定启动图标只留成员项。
    var menuMode: LauncherMenuMode = .full
    /// When set, replaces the default tap behavior (drawer show/hide toggle). Used by
    /// the strip's messaging app chip, whose tap must always reopen the main window.
    var onTap: (() -> Void)? = nil
    /// Fired when this chip actually kicks off a launch (tap on a not-running app).
    /// The drawer wires it to `runtime.beginLaunch` for the 窗口出现门控 (keeps the
    /// app bouncing in the launch zone until its window shows, not just its process).
    var onLaunch: () -> Void = {}
    /// Fired when the tap dispatches an "open" action: unhide+activate (running but not active) or launch (not running).
    /// Hide taps (app is active → minimize) do NOT fire this — the drawer stays open for those.
    /// Only set by DrawerView; strip messaging chips leave it nil.
    var onPrimaryAction: (() -> Void)? = nil

    private static let logger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "LauncherChip")

    @State private var isLaunching = false
    @State private var isHovering = false

    /// 弹跳动画：偏移量由 isLaunching 声明式推导，动画类型也跟着 isLaunching 切换。
    /// 关键——绝不能用「withAnimation(.repeatForever) 起跳 + withAnimation 把值设回 0」
    /// 这种命令式写法：另一个动画停不掉已在运行的 .repeatForever，会留下永远跳动的
    /// 僵尸动画（2026-06-18 实测：弹跳不止的真凶）。声明式 .animation(value:) 在
    /// isLaunching 变 false 时自动换成有限动画，循环动画从根上消失。
    private var bounceAnimation: Animation {
        isLaunching
            ? .easeInOut(duration: 0.25).repeatForever(autoreverses: true)
            : .easeOut(duration: 0.15)
    }

    var body: some View {
        let iconSize: CGFloat = isHovering ? 24 * scale : 36 * scale
        let iconOpacity: Double = dimsWhenInactive ? (!isRunning ? 0.35 : (isHidden ? 0.45 : 1.0)) : 1.0
        return VStack(spacing: 2) {
            Spacer(minLength: 0)
            Image(nsImage: AppIconResolver.icon(for: bundleID))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: iconSize / 4, style: .continuous))
                .opacity(iconOpacity)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                .offset(y: isLaunching ? -6 : 0)
                .animation(bounceAnimation, value: isLaunching)
            if isHovering {
                Text(displayName)
                    .font(.system(size: max(8, 10 * scale), weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 64 * scale)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 44 * scale, height: 52 * scale)
        .overlay(alignment: .bottom) {
            if isRunning {
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .padding(.bottom, 2)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture {
            if let onTap { onTap() } else { handleTap() }
        }
        .nativeContextMenu { buildLauncherMenu() }
        .help(displayName)
        .onDisappear { stopBounce() }
        .onChange(of: isRunning) { newValue in
            if newValue { stopBounce() }
        }
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }

    private func buildLauncherMenu() -> NSMenu {
        let menu = NSMenu()
        // 菜单运行态跟随「图标所在区的显示态」(isRunning prop)，不再独立问 NSWorkspace——否则待启动区里
        // 进程仍活（关窗不退 / 常驻）的图标会误报「隐藏 / 退出」，与其「已退出」的灰显外观矛盾。
        let kinds = LauncherMenuPlan.itemKinds(mode: menuMode,
                                               isRunning: isRunning,
                                               isHidden: isHidden,
                                               hasMembership: !membershipItems.isEmpty)
        // 仅在真要执行 显示/隐藏/退出 时才取 app 对象；取不到就跳过该项（快照短暂陈旧的兜底）。
        let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID })
        var didAppendAppActions = false
        for kind in kinds {
            switch kind {
            case .recentDocuments:
                AppMenuBuilder.appendRecentDocuments(to: menu, bundleID: bundleID)
            case .show:
                if let app = runningApp {
                    menu.addItem(ClosureMenuItem("显示") {
                        _ = app.unhide()
                        app.activate(options: .activateIgnoringOtherApps)
                    })
                    didAppendAppActions = true
                }
            case .hide:
                if let app = runningApp {
                    menu.addItem(ClosureMenuItem("隐藏") { _ = app.hide() })
                    didAppendAppActions = true
                }
            case .quit:
                if let app = runningApp {
                    AppMenuBuilder.appendQuitItems(to: menu, bundleID: bundleID) { _ = app.terminate() }
                    didAppendAppActions = true
                }
            case .membership:
                // 分隔线按**实际渲染态**判断：真加过 app 动作项且菜单非空才补，避免 isRunning 为真但
                // NSWorkspace 竞态取不到 app、动作被跳过时多出一条空分隔线。
                if didAppendAppActions && !menu.items.isEmpty { menu.addItem(.separator()) }
                for item in membershipItems {
                    menu.addItem(ClosureMenuItem(item.label) { item.action() })
                }
            }
        }
        return menu
    }

    private func handleTap() {
        if isRunning {
            let app = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
            if let app, app.isActive {
                // 在前台 → 收起（最小化）：抽屉保持打开
                _ = app.hide()
            } else {
                // 未激活 / 隐藏 / 窗口已关 → 唤出：关闭抽屉
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
                _ = app?.unhide()
                NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
                onPrimaryAction?()
            }
        } else {
            guard !isLaunching else { return }
            launch()   // onPrimaryAction fired inside launch() after URL guard
        }
    }

    private var displayName: String {
        AppDisplayNameResolver.displayName(for: bundleID)
    }

    /// 停跳：只翻 isLaunching。偏移量与动画类型都声明式绑定它，置 false 即换成
    /// 有限动画收敛到 0，循环动画随之消失（见 bounceAnimation 注释）。
    private func stopBounce() {
        isLaunching = false
    }

    private func launch() {
        Self.logger.info("launch() 入口，bundleID=\(bundleID, privacy: .public)")
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            Self.logger.warning("launch()：找不到 app URL，bundleID=\(bundleID, privacy: .public)")
            return
        }

        isLaunching = true
        onLaunch()
        onPrimaryAction?()

        // 8s timeout backstop（对 menubar-only app 无窗口回调的情况兜底）
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8 * 1_000_000_000)
            stopBounce()
        }

        NSWorkspace.shared.openApplication(at: appURL, configuration: .init()) { _, error in
            if let error {
                Self.logger.error("launch()：openApplication 失败，bundleID=\(bundleID, privacy: .public)，error=\(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                stopBounce()
            }
        }
    }
}

// MARK: - App Display Name Resolver

/// Resolves human-readable names for a bundle identifier, with caching (bundle plist
/// reads involve disk IO and these get called from SwiftUI body evaluations).
/// Also answers "does this window title look like the app's main window?" — the
/// 方案 B heuristic: a messaging app's main window is the one titled like the app
/// itself (微信 / WeChat / Telegram…), verified to hold for WeChat/QQ/Telegram.
enum AppDisplayNameResolver {
    private static var bundleNameCache: [String: Set<String>] = [:]

    static func displayName(for bundleID: String) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName, !name.isEmpty {
            return name
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return Bundle(url: url)?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String
            ?? url.deletingPathExtension().lastPathComponent
    }

    static func titleMatchesAppName(_ title: String, bundleID: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
           let name = running.localizedName,
           normalized == name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return true
        }
        return bundleDerivedNames(for: bundleID).contains(normalized)
    }

    /// Localized + unlocalized bundle names (covers e.g. 微信 vs WeChat), cached.
    private static func bundleDerivedNames(for bundleID: String) -> Set<String> {
        if let cached = bundleNameCache[bundleID] { return cached }
        var names: Set<String> = []
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let bundle = Bundle(url: url)
            for dict in [bundle?.localizedInfoDictionary, bundle?.infoDictionary] {
                for key in ["CFBundleDisplayName", "CFBundleName"] {
                    if let name = dict?[key] as? String, !name.isEmpty {
                        names.insert(name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                    }
                }
            }
            names.insert(url.deletingPathExtension().lastPathComponent.lowercased())
        }
        bundleNameCache[bundleID] = names
        return names
    }
}
