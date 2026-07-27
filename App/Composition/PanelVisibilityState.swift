import ApplicationServices

enum PanelVisibilityReason: Hashable {
    case fullscreen
    case edgeAutoHide
}

// 异步 AX 全屏探测的纯判定（PanelCoordinator.detectFullscreenViaAX 调用）。
// role 门禁是硬约束：Finder 挂着一个桌面伪窗口（role=AXScrollArea，frame 恰好等于整屏），
// 恢复最小化窗口的瞬间它会成为 AXFocusedWindow —— 没有门禁就命中 frame≈整屏兜底，任务条被误隐藏。
enum FullscreenWindowClassifier {
    static let frameTolerance: CGFloat = 8

    static func isFullscreen(
        role: String?,
        isAXFullscreen: Bool,
        windowFrame: CGRect?,
        screenCGFrame: CGRect
    ) -> Bool {
        guard role == kAXWindowRole else { return false }

        if isAXFullscreen {
            guard let wf = windowFrame else { return true }
            return wf.intersects(screenCGFrame) && wf.width > screenCGFrame.width * 0.7
        }

        // Fallback: frame ≈ full screen (games / HTML5 that skip the AXFullScreen flag)
        if let wf = windowFrame {
            let t = frameTolerance
            return abs(wf.width  - screenCGFrame.width)  < t
                && abs(wf.height - screenCGFrame.height) < t
                && abs(wf.minX   - screenCGFrame.minX)   < t
                && abs(wf.minY   - screenCGFrame.minY)   < t
        }

        return false
    }
}

enum EdgeAutoHideInhibitor: Hashable {
    case dragging
    case drawerOpen
    case folderPopupOpen
    /// 钨极菜单（状态栏图标或任务条右键弹出的那一个）正开着。
    /// 不挡的话，自动隐藏档位下空闲计时照跑，任务条会从菜单底下缩掉。
    case taskbarMenuOpen
}

struct PanelVisibilityState: Equatable {
    var hideReasons: Set<PanelVisibilityReason> = []
    var autoHideInhibitors: Set<EdgeAutoHideInhibitor> = []

    var isVisible: Bool { hideReasons.isEmpty }

    mutating func setFullscreen(_ active: Bool) {
        setReason(.fullscreen, active: active)
    }

    mutating func setEdgeAutoHidden(_ active: Bool) {
        setReason(.edgeAutoHide, active: active)
    }

    mutating func setInhibitor(_ inhibitor: EdgeAutoHideInhibitor, active: Bool) {
        if active {
            autoHideInhibitors.insert(inhibitor)
        } else {
            autoHideInhibitors.remove(inhibitor)
        }
    }

    mutating func reconcileEdgeAutoHide(isEnabled: Bool) {
        if !isEnabled || !autoHideInhibitors.isEmpty {
            hideReasons.remove(.edgeAutoHide)
        }
    }

    private mutating func setReason(_ reason: PanelVisibilityReason, active: Bool) {
        if active {
            hideReasons.insert(reason)
        } else {
            hideReasons.remove(reason)
        }
    }

    /// 一条任务条最终可不可见 = 全局部分 × 该屏部分（每屏常驻任务条，2026-07-27）。
    ///
    /// - 全局部分：边缘自动隐藏。owner 不使用自动隐藏，所以刻意保持**全局同步**语义，
    ///   不做按屏自动隐藏。
    /// - 每屏部分：这块屏上有没有应用处于全屏。副屏全屏只藏副屏那条（owner 决策）。
    ///
    /// 注意全局 `hideReasons` 里的 `.fullscreen` 现在表示「**所有**已接显示器都在全屏」，
    /// 它只用来给 `EdgeAutoHideRuntimeRules` 的唤醒/隐藏门槛把关；单屏时两者等价，
    /// 行为与改造前逐位一致。
    static func barIsVisible(global: Bool, screenFullscreen: Bool) -> Bool {
        global && !screenFullscreen
    }
}

@MainActor
enum EdgeAutoHideRuntimeRules {
    static let fixedIdleHideDelay: Double = 0.2

    static func canArmWake(state: PanelVisibilityState, delay: Double) -> Bool {
        state.hideReasons.contains(.edgeAutoHide)
            && !state.hideReasons.contains(.fullscreen)
            && state.autoHideInhibitors.isEmpty
            && delay != AppSettingsStore.neverHideDelay
            && delay < AppSettingsStore.neverWakeDelay
    }

    static func canArmIdleHide(state: PanelVisibilityState, delay: Double) -> Bool {
        !state.hideReasons.contains(.edgeAutoHide)
            && !state.hideReasons.contains(.fullscreen)
            && state.autoHideInhibitors.isEmpty
            && delay != AppSettingsStore.neverHideDelay
    }

    static func idleHideInterval(for delay: Double) -> Double? {
        guard delay > AppSettingsStore.neverHideDelay else { return nil }
        return fixedIdleHideDelay
    }

    /// 底边唤醒热区（贯穿整条屏幕底边）是否应该压住 idle-hide、阻止武装隐藏计时器。
    /// 只在"有限唤醒延迟"（0.1–3.0s）时成立：这个区间唤醒和 idle-hide 都在跑，鼠标停在热区内、
    /// 但任务条矩形外时，两者会互相打架（唤醒→隐藏→唤醒…），必须让热区本身也算"没离开"。
    /// 999（`neverWakeDelay`，自动隐藏但不唤醒）没有唤醒动作，不存在这种打架，隐藏应照常进行；
    /// -1（`neverHideDelay`，常驻显示）本来就不会隐藏，压不压都一样。
    static func bottomHotZoneSuppressesIdleHide(delay: Double) -> Bool {
        delay != AppSettingsStore.neverHideDelay && delay < AppSettingsStore.neverWakeDelay
    }
}
