import Combine
import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    static let delayStep: Double = 0.1
    static let finiteDelayMin: Double = 0.1
    static let finiteDelayMax: Double = 3.0
    static let neverHideDelay: Double = -1.0
    static let neverWakeDelay: Double = 999.0
    static let sliderIndexMax = 31
    // nonisolated：要在 snapDelay 的默认参数（nonisolated 求值上下文）里引用。
    nonisolated static let defaultNativeDockAutoHideDelay: Double = 1.0
    nonisolated static let defaultEdgeAutoHideDelay: Double = 0.1

    @Published private(set) var launchAtLogin: Bool
    /// 中转格是否显示在固定文件夹区头位。关掉后它不再渲染，暂存的文件不受影响。
    @Published private(set) var showShelf: Bool
    @Published private(set) var nativeDockAutoHideDelay: Double
    @Published private(set) var edgeAutoHideDelay: Double
    /// 「自动隐藏」切换（菜单/全局快捷键）从常驻恢复时要回到的延迟值。
    /// 只允许有限档位（0.1...3.0）或不唤醒（999），绝不允许常驻（-1）本身。
    private(set) var lastEnabledEdgeAutoHideDelay: Double
    /// 系统 Dock 组的镜像 remembered，规则同上（回退默认档位是 1.0）。
    private(set) var lastEnabledNativeDockAutoHideDelay: Double

    var nativeDockAutoHideEnabled: Bool { nativeDockAutoHideDelay != Self.neverHideDelay }
    var edgeAutoHideEnabled: Bool { edgeAutoHideDelay != Self.neverHideDelay }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.migrateLegacyEnabledKey(
            defaults: defaults,
            enabledKey: Keys.nativeDockAutoHideEnabled,
            delayKey: Keys.nativeDockAutoHideDelay
        )
        Self.migrateLegacyEnabledKey(
            defaults: defaults,
            enabledKey: Keys.edgeAutoHideEnabled,
            delayKey: Keys.edgeAutoHideDelay
        )
        // remembered 键（lastEnabledDelay）不注册默认值：区分「从未写过」和「真实写过」，
        // 从未写过时由下面的播种逻辑决定，而不是静默拿到一个注册出来的假历史值。
        defaults.register(defaults: [
            Keys.launchAtLogin: false,
            Keys.showShelf: true,
            Keys.nativeDockAutoHideDelay: Self.defaultNativeDockAutoHideDelay,
            Keys.edgeAutoHideDelay: Self.defaultEdgeAutoHideDelay,
        ])

        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        showShelf = defaults.bool(forKey: Keys.showShelf)
        let nativeDelay = Self.sanitizedStoredDelay(
            defaults.object(forKey: Keys.nativeDockAutoHideDelay),
            fallback: Self.defaultNativeDockAutoHideDelay
        )
        nativeDockAutoHideDelay = nativeDelay
        if nativeDelay == Self.neverHideDelay {
            lastEnabledNativeDockAutoHideDelay = Self.sanitizedLastEnabledDelay(
                Self.storedNumericValue(defaults.object(forKey: Keys.nativeDockAutoHideLastEnabledDelay)),
                fallback: Self.defaultNativeDockAutoHideDelay
            )
        } else {
            lastEnabledNativeDockAutoHideDelay = nativeDelay
        }
        let edgeDelay = Self.sanitizedStoredDelay(
            defaults.object(forKey: Keys.edgeAutoHideDelay),
            fallback: Self.defaultEdgeAutoHideDelay
        )
        edgeAutoHideDelay = edgeDelay
        if edgeDelay == Self.neverHideDelay {
            lastEnabledEdgeAutoHideDelay = Self.sanitizedLastEnabledDelay(
                Self.storedNumericValue(defaults.object(forKey: Keys.edgeAutoHideLastEnabledDelay)),
                fallback: Self.defaultEdgeAutoHideDelay
            )
        } else {
            lastEnabledEdgeAutoHideDelay = edgeDelay
        }
        defaults.set(nativeDelay, forKey: Keys.nativeDockAutoHideDelay)
        defaults.set(lastEnabledNativeDockAutoHideDelay, forKey: Keys.nativeDockAutoHideLastEnabledDelay)
        defaults.set(edgeDelay, forKey: Keys.edgeAutoHideDelay)
        defaults.set(lastEnabledEdgeAutoHideDelay, forKey: Keys.edgeAutoHideLastEnabledDelay)
    }

    func setShowShelf(_ value: Bool) {
        guard showShelf != value else { return }
        showShelf = value
        defaults.set(value, forKey: Keys.showShelf)
    }

    func setLaunchAtLogin(_ value: Bool) {
        guard launchAtLogin != value else { return }
        launchAtLogin = value
        defaults.set(value, forKey: Keys.launchAtLogin)
    }

    func setNativeDockAutoHideDelay(_ value: Double) {
        guard value.isFinite else { return }
        let snapped = Self.snapDelay(value, fallbackForNonFinite: Self.defaultNativeDockAutoHideDelay)
        // remembered 同步先于 active 去重：active 未变时也要修正 remembered。
        if snapped != Self.neverHideDelay, lastEnabledNativeDockAutoHideDelay != snapped {
            lastEnabledNativeDockAutoHideDelay = snapped
            defaults.set(snapped, forKey: Keys.nativeDockAutoHideLastEnabledDelay)
        }
        guard nativeDockAutoHideDelay != snapped else { return }
        nativeDockAutoHideDelay = snapped
        defaults.set(snapped, forKey: Keys.nativeDockAutoHideDelay)
    }

    // 系统 Dock 组刻意不提供盲翻的 toggle 方法：它的翻转方向必须由系统实际完整隐藏状态决定
    // （AutoHideToggleMenuModel.nativeToggleTargetHidden）——系统状态可被外部改（⌥⌘D / 系统设置），
    // 盲翻本地存值会在两者脱节时翻错方向。

    func setEdgeAutoHideDelay(_ value: Double) {
        guard value.isFinite else { return }
        let snapped = Self.snapDelay(value, fallbackForNonFinite: Self.defaultEdgeAutoHideDelay)
        // remembered 同步先于 active 去重：active 未变时也要修正 remembered。
        if snapped != Self.neverHideDelay, lastEnabledEdgeAutoHideDelay != snapped {
            lastEnabledEdgeAutoHideDelay = snapped
            defaults.set(snapped, forKey: Keys.edgeAutoHideLastEnabledDelay)
        }
        guard edgeAutoHideDelay != snapped else { return }
        edgeAutoHideDelay = snapped
        defaults.set(snapped, forKey: Keys.edgeAutoHideDelay)
    }

    /// 钨极的「自动隐藏」切换：常驻 ⇄ 上一次的延迟（含不唤醒 999）。
    /// 命名避免 "Now"——切到自动隐藏侧不是立即隐藏，仍走原空闲计时与鼠标判定。
    func toggleEdgeAutoHideMode() {
        if edgeAutoHideDelay == Self.neverHideDelay {
            setEdgeAutoHideDelay(lastEnabledEdgeAutoHideDelay)
        } else {
            setEdgeAutoHideDelay(Self.neverHideDelay)
        }
    }

    static func delayFromSliderIndex(_ index: Int) -> Double {
        let clamped = min(max(index, 0), sliderIndexMax)
        switch clamped {
        case 0:
            return neverHideDelay
        case sliderIndexMax:
            return neverWakeDelay
        case sliderIndexMax - 1:
            return finiteDelayMax
        default:
            return ((finiteDelayMin + Double(clamped - 1) * delayStep) * 10).rounded() / 10
        }
    }

    static func sliderIndexFromDelay(_ value: Double) -> Int {
        guard value > neverHideDelay else { return 0 }
        guard value < neverWakeDelay else { return sliderIndexMax }
        let clamped = min(max(value, finiteDelayMin), finiteDelayMax)
        return Int(((clamped - finiteDelayMin) / delayStep).rounded()) + 1
    }

    static func snapDelay(_ value: Double, fallbackForNonFinite fallback: Double = AppSettingsStore.defaultEdgeAutoHideDelay) -> Double {
        // NaN/±inf 穿透到下面的 Int(...) 转换会直接 crash（NaN 的比较全为 false，clamp 不生效）。
        guard value.isFinite else { return fallback }
        if value <= neverHideDelay { return neverHideDelay }
        if value >= neverWakeDelay { return neverWakeDelay }
        let clamped = min(max(value, finiteDelayMin), finiteDelayMax)
        return delayFromSliderIndex(Int(((clamped - finiteDelayMin) / delayStep).rounded()) + 1)
    }

    /// UserDefaults 的 active delay 读取入口。只接受真正的数值对象；字符串、布尔值和非有限值
    /// 都按该组默认档位回退，避免 `double(forKey:)` 把坏类型静默变成 0.0。
    static func sanitizedStoredDelay(_ value: Any?, fallback: Double) -> Double {
        guard let value = storedNumericValue(value) else { return fallback }
        return snapDelay(value, fallbackForNonFinite: fallback)
    }

    /// remembered 值的防御收口：缺失、类型错误、非有限、吸附后为常驻，一律回退默认档位
    /// （edge 组 0.1，系统 Dock 组 1.0）。
    static func sanitizedLastEnabledDelay(_ value: Double?, fallback: Double = AppSettingsStore.defaultEdgeAutoHideDelay) -> Double {
        guard let value, value.isFinite else { return fallback }
        let snapped = snapDelay(value, fallbackForNonFinite: fallback)
        return snapped == neverHideDelay ? fallback : snapped
    }

    private static func storedNumericValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        // Bool/CFBoolean 也能桥接成 NSNumber，必须先按 CF 类型排除，否则 true 会被误读成 1.0。
        guard CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID(),
              let number = value as? NSNumber else {
            return nil
        }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }

    private static func migrateLegacyEnabledKey(defaults: UserDefaults, enabledKey: String, delayKey: String) {
        if let storedEnabled = defaults.object(forKey: enabledKey) as? Bool, storedEnabled == false {
            defaults.set(neverHideDelay, forKey: delayKey)
        }
        defaults.removeObject(forKey: enabledKey)
    }
}

private enum Keys {
    static let launchAtLogin = "com.tungsten.edge.launchAtLogin"
    static let showShelf = "com.tungsten.edge.showShelf"
    static let nativeDockAutoHideEnabled = "com.tungsten.edge.autoHide.nativeDock.enabled"
    static let nativeDockAutoHideDelay = "com.tungsten.edge.autoHide.nativeDock.delay"
    static let nativeDockAutoHideLastEnabledDelay = "com.tungsten.edge.autoHide.nativeDock.lastEnabledDelay"
    static let edgeAutoHideEnabled = "com.tungsten.edge.autoHide.edge.enabled"
    static let edgeAutoHideDelay = "com.tungsten.edge.autoHide.edge.delay"
    static let edgeAutoHideLastEnabledDelay = "com.tungsten.edge.autoHide.edge.lastEnabledDelay"
}
