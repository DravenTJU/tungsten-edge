import Combine
import Foundation

struct NativeDockApplyOutcome {
    let resolvedDelay: Double
    let error: Error?
}

/// 状态栏菜单与设置窗口**共用**的动作层。
///
/// 职责刻意收窄到「会写到本 App 之外」的三件事：登录项、系统 Dock、检查更新。
/// 钨极自己的本地开关（中转站 / 悬停 / 避让 / 任务条大小 / 唤醒延迟）不经这里——
/// 它们是即时生效的本地值，两套界面直接观察同一个 `AppSettingsStore` 就不会脱节。
@MainActor
final class SettingsCoordinator: ObservableObject {
    /// 登录项状态**不做长期缓存**：`SMAppService` 的状态会被系统设置里的操作改掉。
    /// 这个 `@Published` 只是「最近一次现读的结果」，用来让两套界面同时刷新——
    /// 每次展示前都会调 `refreshLaunchAtLoginState()` 重新问服务。
    @Published private(set) var launchAtLoginState: LaunchAtLoginState
    /// 在飞守卫放在共享层：两套界面各有一个「检查更新」入口，
    /// 各自守卫的话同时点两下会发两次请求。
    @Published private(set) var updateCheckState = UpdateCheckMenuState()

    private let store: AppSettingsStore
    private let launchAtLoginService: LaunchAtLoginServicing
    private let nativeDockPreferencesService: NativeDockPreferencesServicing
    private let updateChecker: UpdateChecking

    init(
        store: AppSettingsStore,
        launchAtLoginService: LaunchAtLoginServicing,
        nativeDockPreferencesService: NativeDockPreferencesServicing,
        updateChecker: UpdateChecking
    ) {
        self.store = store
        self.launchAtLoginService = launchAtLoginService
        self.nativeDockPreferencesService = nativeDockPreferencesService
        self.updateChecker = updateChecker
        launchAtLoginState = launchAtLoginService.state
    }

    // MARK: 登录项

    func refreshLaunchAtLoginState() {
        let next = launchAtLoginService.state
        if launchAtLoginState != next { launchAtLoginState = next }
    }

    /// 只有**写成功**才更新本地镜像：镜像存在的意义是「我们以为的状态」，
    /// 写失败时系统那边没变，镜像跟着变会让下次展示说谎。
    func setLaunchAtLogin(_ enabled: Bool) -> Result<Void, Error> {
        do {
            try launchAtLoginService.setEnabled(enabled)
            store.setLaunchAtLogin(enabled)
            refreshLaunchAtLoginState()
            return .success(())
        } catch {
            refreshLaunchAtLoginState()
            return .failure(error)
        }
    }

    func openLoginItemsSettings() {
        launchAtLoginService.openSystemSettings()
    }

    // MARK: 系统 Dock

    /// 只改本地镜像让 UI 对齐系统真值，**绝不反向应用**——展示一次设置界面
    /// 不该招来一次 `killall Dock`。返回值是对齐之后的镜像值，
    /// `applyNativeDock` 拿它当 previous。
    @discardableResult
    func reconcileNativeDockMirror() -> Double {
        guard let state = nativeDockPreferencesService.currentAutohideState() else {
            // 读不到系统真值（沙箱等）时保持镜像不动，调用方按当前镜像继续。
            return store.nativeDockAutoHideDelay
        }
        if let target = AutoHideToggleMenuModel.reconciledStoreDelay(
            systemEnabled: state.enabled,
            systemDelay: state.delay,
            currentStoreDelay: store.nativeDockAutoHideDelay
        ) {
            store.setNativeDockAutoHideDelay(target)
        }
        return store.nativeDockAutoHideDelay
    }

    /// 系统 Dock 的**唯一**写入路径。
    ///
    /// `previous` 不由界面传进来：草稿摊在屏幕上的这段时间里，用户随时可能用 ⌥⌘D 或
    /// 系统设置改掉真值，界面手里那个起点早就过期了。所以写之前先重读一次系统真值。
    ///
    /// defaults + killall 是多步非事务序列，写完一律重读系统真值再决定镜像落什么
    /// （四象限见 `AutoHideToggleMenuModel.resolvedStoreDelay`）。这里**不弹窗**：
    /// 弹窗归调用方，两套界面的弹法不一样（菜单用 NSAlert，设置窗口用附着式 alert）。
    func applyNativeDock(target: Double) -> NativeDockApplyOutcome {
        guard nativeDockPreferencesService.isAvailable else {
            return NativeDockApplyOutcome(
                resolvedDelay: store.nativeDockAutoHideDelay,
                error: NativeDockPreferencesError.sandboxed
            )
        }

        let previous = reconcileNativeDockMirror()
        var writeError: Error?
        do {
            try nativeDockPreferencesService.apply(delay: target)
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
        return NativeDockApplyOutcome(resolvedDelay: resolved, error: writeError)
    }

    func openNativeDockSettings() -> Bool {
        nativeDockPreferencesService.openSystemSettings()
    }

    // MARK: 检查更新

    /// 版本行同时给菜单和设置窗口用。发布后主线不 bump 版本号，光看数字分不出开发构建和
    /// 用户装的包，所以把来源一并显示出来（判定在纯 `BuildProvenance` 里，有单测）。
    var versionTitle: String? {
        let info = Bundle.main.infoDictionary
        #if DEBUG
        let isDebugBuild = true
        #else
        let isDebugBuild = false
        #endif
        return BuildProvenance.versionTitle(
            version: info?["CFBundleShortVersionString"] as? String,
            build: info?["CFBundleVersion"] as? String,
            isDebugBuild: isDebugBuild,
            bundlePath: Bundle.main.bundleURL.path
        )
    }

    /// 返回 false = 已经有一次检查在飞，本次忽略。
    func beginUpdateCheck() -> Bool {
        updateCheckState.begin()
    }

    func finishUpdateCheck() {
        updateCheckState.finish()
    }

    func performUpdateCheck() async -> UpdateCheckAlertContent {
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        do {
            let outcome = try await updateChecker.check(currentVersion: currentVersion)
            return UpdateCheckAlertContent(outcome: outcome)
        } catch {
            return .failure
        }
    }
}
