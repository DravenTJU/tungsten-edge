import Foundation

/// Single mutation boundary for app membership conversions.
///
/// Pinned membership is exclusive with drawer, launch-favorite, and messaging
/// membership. Existing relationships among the latter three remain unchanged.
@MainActor
final class AppMembershipController: ObservableObject {
    private let pinnedAppStore: PinnedAppStore
    private let drawerStore: DrawerStore
    private let launchFavoriteStore: LaunchFavoriteStore
    private let messagingStore: MessagingAppStore

    init(
        pinnedAppStore: PinnedAppStore,
        drawerStore: DrawerStore,
        launchFavoriteStore: LaunchFavoriteStore,
        messagingStore: MessagingAppStore
    ) {
        self.pinnedAppStore = pinnedAppStore
        self.drawerStore = drawerStore
        self.launchFavoriteStore = launchFavoriteStore
        self.messagingStore = messagingStore
    }

    func pinToStrip(_ bundleID: String) {
        guard pinnedAppStore.canPin(bundleID) else { return }
        pinnedAppStore.add(bundleID)
        if drawerStore.contains(bundleID) {
            drawerStore.remove(bundleID)
        }
        if launchFavoriteStore.contains(bundleID) {
            launchFavoriteStore.remove(bundleID)
        }
        if messagingStore.contains(bundleID) {
            messagingStore.unmark(bundleID)
        }
    }

    func moveToDrawer(_ bundleID: String) {
        guard canChangeMembership(bundleID) else { return }
        pinnedAppStore.remove(bundleID)
        drawerStore.add(bundleID)
    }

    func pinToLaunchpad(_ bundleID: String) {
        guard canChangeMembership(bundleID) else { return }
        pinnedAppStore.remove(bundleID)
        launchFavoriteStore.add(bundleID)
        if messagingStore.contains(bundleID) {
            messagingStore.unmark(bundleID)
        }
    }

    func markMessaging(_ bundleID: String) {
        guard canChangeMembership(bundleID) else { return }
        pinnedAppStore.remove(bundleID)
        messagingStore.mark(bundleID)
        if drawerStore.contains(bundleID) {
            drawerStore.remove(bundleID)
        }
        if launchFavoriteStore.contains(bundleID) {
            launchFavoriteStore.remove(bundleID)
        }
    }

    func unpinFromStrip(_ bundleID: String) {
        pinnedAppStore.remove(bundleID)
    }

    /// Startup repair. Finder is removed from memberships that could replace its
    /// dedicated slot, then persistent pinned membership wins before messaging
    /// auto-register starts. Display projections remain a separate defensive layer.
    func reconcilePinnedWins() {
        let finder = PinnedAppStore.forbiddenBundleID
        if drawerStore.contains(finder) {
            drawerStore.remove(finder)
        }
        if launchFavoriteStore.contains(finder) {
            launchFavoriteStore.remove(finder)
        }
        if messagingStore.contains(finder) {
            messagingStore.unmark(finder)
        }

        for bundleID in pinnedAppStore.bundleIDs {
            if drawerStore.contains(bundleID) {
                drawerStore.remove(bundleID)
            }
            if launchFavoriteStore.contains(bundleID) {
                launchFavoriteStore.remove(bundleID)
            }
            if messagingStore.contains(bundleID) {
                messagingStore.unmark(bundleID)
            }
        }
    }

    private func canChangeMembership(_ bundleID: String) -> Bool {
        !bundleID.isEmpty && bundleID != PinnedAppStore.forbiddenBundleID
    }
}

/// Defensive, side-effect-free projections used by the strip, drawer, and capsule.
enum AppMembershipProjection {
    static func drawerMembers(
        drawerIDs: [String],
        launchFavoriteIDs: [String],
        pinnedIDs: [String]
    ) -> [String] {
        filteredUnique(drawerIDs + launchFavoriteIDs, excluding: Set(pinnedIDs))
    }

    static func drawerPreview(
        drawerIDs: [String],
        pinnedIDs: [String],
        limit: Int = 9
    ) -> [String] {
        Array(filteredUnique(drawerIDs, excluding: Set(pinnedIDs)).prefix(max(0, limit)))
    }

    static func messagingIDs(
        _ messagingIDs: [String],
        excludingPinnedIDs pinnedIDs: [String]
    ) -> [String] {
        filteredUnique(messagingIDs, excluding: Set(pinnedIDs))
    }

    private static func filteredUnique(_ bundleIDs: [String], excluding excluded: Set<String>) -> [String] {
        var seen = Set<String>()
        return bundleIDs.filter { bundleID in
            !bundleID.isEmpty && !excluded.contains(bundleID) && seen.insert(bundleID).inserted
        }
    }
}
