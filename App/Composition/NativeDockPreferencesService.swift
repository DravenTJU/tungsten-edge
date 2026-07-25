import AppKit
import Foundation
import Security

typealias ShellRunner = @MainActor (_ executable: String, _ arguments: [String]) throws -> Void
typealias URLOpener = @MainActor (URL) -> Bool

/// 系统 Dock 自动隐藏的实际状态快照。delay 为 nil = autohide-delay 键不存在（系统默认值）。
struct NativeDockAutohideState: Equatable {
    var enabled: Bool
    var delay: Double?
}

@MainActor
protocol NativeDockPreferencesServicing {
    var isAvailable: Bool { get }
    func setAutohideEnabled(_ enabled: Bool) throws
    /// 系统 Dock 当前的自动隐藏状态。nil = 读不到（沙箱等），调用方回退本地存值推导。
    /// 必须读系统实际值：用户随时可用 ⌥⌘D / 系统设置改它，本地存值会过期。
    func currentAutohideState() -> NativeDockAutohideState?
    /// 只打开系统设置里的 Dock 页面，不修改偏好，也不受写入路径的沙箱门控。
    func openSystemSettings() -> Bool
}

struct SandboxEnvironment {
    var isSandboxed: Bool

    static var current: SandboxEnvironment {
        let key = "com.apple.security.app-sandbox" as CFString
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, key, nil) else {
            return SandboxEnvironment(isSandboxed: false)
        }
        return SandboxEnvironment(isSandboxed: (value as? Bool) == true)
    }
}

@MainActor
final class NativeDockPreferencesService: NativeDockPreferencesServicing {
    private let sandbox: SandboxEnvironment
    private let runner: ShellRunner
    private let autohideReader: @MainActor () -> NativeDockAutohideState?
    private let urlOpener: URLOpener

    init(sandbox: SandboxEnvironment = .current,
         runner: @escaping ShellRunner = NativeDockPreferencesService.runProcess,
         autohideReader: @escaping @MainActor () -> NativeDockAutohideState? = NativeDockPreferencesService.readAutohideStateFromSystem,
         urlOpener: @escaping URLOpener = NativeDockPreferencesService.openURL) {
        self.sandbox = sandbox
        self.runner = runner
        self.autohideReader = autohideReader
        self.urlOpener = urlOpener
    }

    var isAvailable: Bool { !sandbox.isSandboxed }

    func currentAutohideState() -> NativeDockAutohideState? {
        guard isAvailable else { return nil }
        return autohideReader()
    }

    /// Monterey 使用「程序坞与菜单栏」，Ventura 及以上映射到「桌面与程序坞」。
    /// 深链失败时交给系统打开 Dock.prefPane；两条路径都不启动子进程。
    func openSystemSettings() -> Bool {
        if let primary = URL(string: "x-apple.systempreferences:com.apple.preference.dock"),
           urlOpener(primary) {
            return true
        }
        return urlOpener(URL(fileURLWithPath: "/System/Library/PreferencePanes/Dock.prefPane"))
    }

    private static func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    static func readAutohideStateFromSystem() -> NativeDockAutohideState? {
        let domain = "com.apple.dock" as CFString
        // 外部修改（⌥⌘D / 系统设置 / killall Dock）不会自动进入本进程的 CFPreferences 缓存，
        // 每次读取前必须先同步，否则可能一直拿到旧值。
        return readAutohideState(
            synchronize: { CFPreferencesAppSynchronize(domain) },
            valueForKey: { key in
                CFPreferencesCopyAppValue(key as CFString, domain)
            }
        )
    }

    /// 注入同步与取值动作，既隔离 CFPreferences I/O，也让同步失败等分支可直接单测。
    static func readAutohideState(
        synchronize: () -> Bool,
        valueForKey: (String) -> Any?
    ) -> NativeDockAutohideState? {
        guard synchronize() else { return nil }
        return decodeAutohideState(
            autohideValue: valueForKey("autohide"),
            delayValue: valueForKey("autohide-delay")
        )
    }

    /// 纯解码规则：autohide 缺键代表关闭；存在却不是布尔值代表整份快照不可读。
    /// 开启时，delay 缺键代表系统默认，坏类型代表不可读；关闭时 delay 不影响开关真值。
    static func decodeAutohideState(
        autohideValue: Any?,
        delayValue: Any?
    ) -> NativeDockAutohideState? {
        let enabled: Bool
        if let autohideValue {
            guard let decoded = strictBooleanValue(autohideValue) else { return nil }
            enabled = decoded
        } else {
            enabled = false
        }

        if !enabled {
            let delay = delayValue.flatMap { finiteNumericValue($0) }
            return NativeDockAutohideState(enabled: false, delay: delay)
        }

        let delay: Double?
        if let delayValue {
            guard let decoded = finiteNumericValue(delayValue) else { return nil }
            delay = decoded
        } else {
            delay = nil
        }
        return NativeDockAutohideState(enabled: enabled, delay: delay)
    }

    func setAutohideEnabled(_ enabled: Bool) throws {
        guard isAvailable else { throw NativeDockPreferencesError.sandboxed }
        for command in Self.commands(autohideEnabled: enabled) {
            try runner(command.executable, command.arguments)
        }
    }

    static func commands(autohideEnabled enabled: Bool) -> [(executable: String, arguments: [String])] {
        return [
            ("/usr/bin/defaults", ["write", "com.apple.dock", "autohide", "-bool", enabled ? "true" : "false"]),
            ("/usr/bin/killall", ["Dock"]),
        ]
    }

    private static func runProcess(executable: String, arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NativeDockPreferencesError.commandFailed(executable: executable, status: process.terminationStatus)
        }
    }

    private static func strictBooleanValue(_ value: Any) -> Bool? {
        guard CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID(),
              let number = value as? NSNumber else {
            return nil
        }
        return number.boolValue
    }

    private static func finiteNumericValue(_ value: Any) -> Double? {
        guard CFGetTypeID(value as CFTypeRef) != CFBooleanGetTypeID(),
              let number = value as? NSNumber else {
            return nil
        }
        let result = number.doubleValue
        return result.isFinite ? result : nil
    }
}

enum NativeDockPreferencesError: LocalizedError {
    case sandboxed
    case commandFailed(executable: String, status: Int32)

    var errorDescription: String? {
        switch self {
        case .sandboxed:
            return "沙箱环境不能直接修改系统 Dock 设置。"
        case .commandFailed(let executable, let status):
            return "\(executable) 执行失败（状态码 \(status)）。"
        }
    }
}
