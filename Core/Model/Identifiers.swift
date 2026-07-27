import Foundation

struct WindowID: Hashable, Codable, Sendable {
    let rawValue: String
}

struct AppID: Hashable, Codable, Sendable {
    let rawValue: String
}

/// 一块显示器的身份 = `CGDirectDisplayID`（从 `NSScreen.deviceDescription["NSScreenNumber"]` 读）。
///
/// **不持久化**：本项目没有任何按屏保存的数据（卡片顺序是全局一份总表，各屏过滤），
/// 所以只需要在进程生命周期内、跨 `didChangeScreenParametersNotification` 保持稳定即可，
/// 不需要 `CGDisplayCreateUUIDFromDisplayID`。
struct ScreenID: Hashable, Codable, Sendable {
    let rawValue: UInt32
}
