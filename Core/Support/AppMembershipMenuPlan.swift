import Foundation

/// 成员菜单的**纯决策层**：给定图标所在面（strip / drawer）+ Finder / kept / messaging
/// 状态，产出应出现的成员项（顺序即渲染顺序，不含 closure）。抽成纯逻辑便于单测；把 `Item`
/// 映射成带动作的菜单项由 `LauncherMembershipItem.items` 完成，四条菜单构造路径统一消费。
///
/// 固定矩阵：
/// - strip 普通：在程序坞中保留 + 标记为消息应用
/// - strip 消息：在程序坞中保留 + 取消标记消息应用
/// - drawer 普通：仅在程序坞中保留
/// - drawer 消息：在程序坞中保留 + 取消标记消息应用
/// - Finder：无成员项
enum AppMembershipMenuPlan {
    enum Surface: Equatable { case strip, drawer }

    /// 无 closure 的展示态，供渲染层映射成具体动作。
    enum Item: Equatable {
        case keep(isChecked: Bool)
        case markMessaging
        case unmarkMessaging
    }

    static func items(surface: Surface,
                      isFinder: Bool,
                      isKept: Bool,
                      isMessaging: Bool) -> [Item] {
        guard !isFinder else { return [] }
        // 保留勾选恒在前，消息命令在后。
        var items: [Item] = [.keep(isChecked: isKept)]
        if isMessaging {
            items.append(.unmarkMessaging)
        } else if surface == .strip {
            // 「标记为消息应用」只在 strip 的普通应用出现：抽屉里标记不改 placement（抽屉优先级更高），
            // 没有可见效果，故 drawer 面不提供该命令。
            items.append(.markMessaging)
        }
        return items
    }
}
