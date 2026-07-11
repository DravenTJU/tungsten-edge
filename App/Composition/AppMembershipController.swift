import Foundation

/// Single mutation boundary for app membership conversions.
///
/// Kept (在程序坞中保留) membership is exclusive with drawer and messaging
/// membership. Conversions go through this controller to maintain exclusivity
/// and messaging opt-out semantics.
@MainActor
final class AppMembershipController: ObservableObject {
    private let keptAppStore: KeptAppStore
    private let drawerStore: DrawerStore
    private let messagingStore: MessagingAppStore

    init(
        keptAppStore: KeptAppStore,
        drawerStore: DrawerStore,
        messagingStore: MessagingAppStore
    ) {
        self.keptAppStore = keptAppStore
        self.drawerStore = drawerStore
        self.messagingStore = messagingStore
    }

    /// 「在程序坞中保留」：kept.add + drawer.remove + messaging.unmark（保 opt-out）。
    func keepInDock(_ bundleID: String) {
        guard keptAppStore.canKeep(bundleID) else { return }
        keptAppStore.add(bundleID)
        if drawerStore.contains(bundleID) {
            drawerStore.remove(bundleID)
        }
        if messagingStore.contains(bundleID) {
            messagingStore.unmark(bundleID)
        }
    }

    /// 「从程序坞中移除」——唯一退出动词，通用退出（owner 2026-07-11：抽屉即程序坞的一部分）：
    /// kept、抽屉、消息身份全部清除。消息 unmark 自带 opt-out，防止下轮 autoRegister 悄悄加回；
    /// 想回来可重新「标记为消息应用」。运行中的窗口照常显示（任务条天职，与保留无关）。
    func removeFromDock(_ bundleID: String) {
        keptAppStore.remove(bundleID)
        if drawerStore.contains(bundleID) {
            drawerStore.remove(bundleID)
        }
        if messagingStore.contains(bundleID) {
            messagingStore.unmark(bundleID)
        }
    }

    /// 「收进抽屉」：kept.remove + drawer.add。
    func moveToDrawer(_ bundleID: String) {
        guard canChangeMembership(bundleID) else { return }
        keptAppStore.remove(bundleID)
        drawerStore.add(bundleID)
    }

    /// 「标记为消息应用」：清 kept + messaging.mark + drawer.remove。
    func markMessaging(_ bundleID: String) {
        guard canChangeMembership(bundleID) else { return }
        keptAppStore.remove(bundleID)
        messagingStore.mark(bundleID)
        if drawerStore.contains(bundleID) {
            drawerStore.remove(bundleID)
        }
    }

    /// Startup repair. Finder is removed from memberships that could replace its
    /// dedicated slot, then persistent kept membership wins before messaging
    /// auto-register starts. Display projections remain a separate defensive layer.
    func reconcileKeptWins() {
        let finder = KeptAppStore.forbiddenBundleID
        if drawerStore.contains(finder) {
            drawerStore.remove(finder)
        }
        if messagingStore.contains(finder) {
            messagingStore.unmark(finder)
        }

        for bundleID in keptAppStore.bundleIDs {
            if drawerStore.contains(bundleID) {
                drawerStore.remove(bundleID)
            }
            if messagingStore.contains(bundleID) {
                messagingStore.unmark(bundleID)
            }
        }
    }

    private func canChangeMembership(_ bundleID: String) -> Bool {
        !bundleID.isEmpty && bundleID != KeptAppStore.forbiddenBundleID
    }
}

/// Defensive, side-effect-free projections used by the strip, drawer, and capsule.
enum AppMembershipProjection {
    /// 抽屉成员全集 = drawer − kept（顺序层按全集记）。
    static func drawerMembers(
        drawerIDs: [String],
        keptIDs: [String]
    ) -> [String] {
        filteredUnique(drawerIDs, excluding: Set(keptIDs))
    }

    static func drawerPreview(
        drawerIDs: [String],
        keptIDs: [String],
        limit: Int = 9
    ) -> [String] {
        Array(filteredUnique(drawerIDs, excluding: Set(keptIDs)).prefix(max(0, limit)))
    }

    static func messagingIDs(
        _ messagingIDs: [String],
        excludingKeptIDs keptIDs: [String]
    ) -> [String] {
        filteredUnique(messagingIDs, excluding: Set(keptIDs))
    }

    private static func filteredUnique(_ bundleIDs: [String], excluding excluded: Set<String>) -> [String] {
        var seen = Set<String>()
        return bundleIDs.filter { bundleID in
            !bundleID.isEmpty && !excluded.contains(bundleID) && seen.insert(bundleID).inserted
        }
    }
}
