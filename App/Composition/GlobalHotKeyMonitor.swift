import AppKit
import Carbon.HIToolbox

/// 全局快捷键定义。Carbon 注册与 AppKit 菜单展示是两套修饰符常量，必须成对维护。
struct GlobalHotKeyShortcut {
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let keyEquivalent: String
    let keyEquivalentModifierMask: NSEvent.ModifierFlags
    let signature: OSType
    let id: UInt32

    var hotKeyID: EventHotKeyID { EventHotKeyID(signature: signature, id: id) }

    /// ⌥⇧⌘D：系统 Dock 的 ⌥⌘D 加 Shift，释放原 ⌥⌘E 给 Safari / Finder。
    /// 四键略重，但这是低频模式切换；组合仍避开 VoiceOver 的 Control+Option，
    /// 也避开 macOS 15 已知失效的纯 Option / Option+Shift（FB15168205）。
    static let edgeAutoHideMode = GlobalHotKeyShortcut(
        keyCode: UInt32(kVK_ANSI_D),
        carbonModifiers: UInt32(optionKey | shiftKey | cmdKey),
        keyEquivalent: "d",
        keyEquivalentModifierMask: [.option, .shift, .command],
        signature: 0x5467_4567, // 'TgEg'
        id: 1
    )
}

/// 热键事件，backend 已解包成纯值，便于单测构造。
enum HotKeyEvent: Equatable {
    case pressed(signature: OSType, id: UInt32)
    case released(signature: OSType, id: UInt32)
}

/// Carbon 调用的可注入抽象：单测用 fake 模拟安装/注册失败与事件序列。
/// 约定：所有方法只在主线程调用；onEvent 返回 true 表示事件已被处理。
protocol HotKeyBackend: AnyObject {
    func installHandler(onEvent: @escaping (HotKeyEvent) -> Bool) -> OSStatus
    /// exclusive 明确走接口：独占注册（组合键被他人持有时确定性失败）是被测试锁住的行为，不是实现细节。
    func register(keyCode: UInt32, modifiers: UInt32, hotKeyID: EventHotKeyID, exclusive: Bool) -> OSStatus
    func unregister()
    func removeHandler()
}

/// 一条全局快捷键的生命周期管理。选 Carbon RegisterEventHotKey 而不是 NSEvent 全局键盘监听：
/// 只在命中注册的组合键时收到通知，不经手其它按键；系统级派发，不依赖本应用前台状态。
/// 硬约束：onPressed 只允许轻量状态切换，不得同步读取跨应用 AX/CG 清单或导出快照。
@MainActor
final class GlobalHotKeyMonitor {
    enum RegistrationStatus: Equatable {
        case registered
        case handlerInstallFailed(OSStatus)
        case registrationFailed(OSStatus)
    }

    let shortcut: GlobalHotKeyShortcut
    private let backend: HotKeyBackend
    private let onPressed: () -> Void
    private(set) var isRegistered = false
    /// 按下-抬起门控：吞掉按住不放时系统按键重复产生的连续 pressed。
    private var isPressedDown = false
    /// 每次成功注册都会推进代次，避免上一轮排进主队列的回调在 stop/start 后误触发。
    private var registrationGeneration: UInt64 = 0
    /// 每实例只尝试一次；重复 start() 返回上次结果，本次启动不自动重试。
    private var attemptedStatus: RegistrationStatus?

    init(shortcut: GlobalHotKeyShortcut,
         backend: HotKeyBackend = CarbonHotKeyBackend(),
         onPressed: @escaping () -> Void) {
        self.shortcut = shortcut
        self.backend = backend
        self.onPressed = onPressed
    }

    deinit {
        MainActor.assumeIsolated { stop() }
    }

    @discardableResult
    func start() -> RegistrationStatus {
        if let attemptedStatus { return attemptedStatus }

        let installStatus = backend.installHandler { [weak self] event in
            self?.handle(event) ?? false
        }
        guard installStatus == noErr else {
            let status = RegistrationStatus.handlerInstallFailed(installStatus)
            attemptedStatus = status
            return status
        }

        let registerStatus = backend.register(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.carbonModifiers,
            hotKeyID: shortcut.hotKeyID,
            exclusive: true
        )
        guard registerStatus == noErr else {
            // 注册失败回滚已装好的处理器，不留半成品。
            backend.removeHandler()
            let status = RegistrationStatus.registrationFailed(registerStatus)
            attemptedStatus = status
            return status
        }

        isRegistered = true
        registrationGeneration &+= 1
        attemptedStatus = .registered
        return .registered
    }

    func stop() {
        // 先标记 inactive、清按下门控，再注销热键、移除处理器；重复调用安全。
        let wasRegistered = isRegistered
        isRegistered = false
        isPressedDown = false
        guard wasRegistered else { return }
        backend.unregister()
        backend.removeHandler()
        // 主动 stop 过的实例允许再次 start（真实重新注册），否则缓存的 .registered 会谎报。
        // 失败结果仍然缓存：「本次启动不自动重试」只针对失败。
        attemptedStatus = nil
    }

    fileprivate func handle(_ event: HotKeyEvent) -> Bool {
        guard isRegistered else { return false }
        switch event {
        case .pressed(let signature, let id):
            guard signature == shortcut.signature, id == shortcut.id else { return false }
            // 已在按下态的重复 pressed：属于我们的键，吞掉但不再回调。
            guard !isPressedDown else { return true }
            isPressedDown = true
            let queuedGeneration = registrationGeneration
            DispatchQueue.main.async { [weak self] in
                // 已排队回调只属于捕获它的注册生命周期；stop/start 会换代。
                guard let self,
                      self.isRegistered,
                      self.registrationGeneration == queuedGeneration else { return }
                self.onPressed()
            }
            return true
        case .released(let signature, let id):
            guard signature == shortcut.signature, id == shortcut.id else { return false }
            isPressedDown = false
            return true
        }
    }
}

/// 生产实现：真实 Carbon 调用。热键事件由系统投递到应用事件目标（主线程 run loop）。
final class CarbonHotKeyBackend: HotKeyBackend {
    private var handlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    fileprivate var onEvent: ((HotKeyEvent) -> Bool)?

    func installHandler(onEvent: @escaping (HotKeyEvent) -> Bool) -> OSStatus {
        guard handlerRef == nil else { return OSStatus(paramErr) }
        self.onEvent = onEvent
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        var installed: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotKeyEventCallback,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &installed
        )
        if status == noErr {
            handlerRef = installed
        } else {
            self.onEvent = nil
        }
        return status
    }

    func register(keyCode: UInt32, modifiers: UInt32, hotKeyID: EventHotKeyID, exclusive: Bool) -> OSStatus {
        guard hotKeyRef == nil else { return OSStatus(paramErr) }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            exclusive ? OptionBits(kEventHotKeyExclusive) : 0,
            &ref
        )
        if status == noErr { hotKeyRef = ref }
        return status
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    func removeHandler() {
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        onEvent = nil
    }
}

/// Carbon C 回调：解包事件种类与 EventHotKeyID 转交 backend.onEvent；
/// 解包失败、未知事件、或 onEvent 判定不属于我们时交还系统（eventNotHandledErr）。
private let carbonHotKeyEventCallback: EventHandlerUPP = { _, eventRef, userData in
    guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let paramStatus = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard paramStatus == noErr else { return OSStatus(eventNotHandledErr) }

    let event: HotKeyEvent
    switch Int(GetEventKind(eventRef)) {
    case kEventHotKeyPressed:
        event = .pressed(signature: hotKeyID.signature, id: hotKeyID.id)
    case kEventHotKeyReleased:
        event = .released(signature: hotKeyID.signature, id: hotKeyID.id)
    default:
        return OSStatus(eventNotHandledErr)
    }

    let backend = Unmanaged<CarbonHotKeyBackend>.fromOpaque(userData).takeUnretainedValue()
    let handled = backend.onEvent?(event) ?? false
    return handled ? noErr : OSStatus(eventNotHandledErr)
}
