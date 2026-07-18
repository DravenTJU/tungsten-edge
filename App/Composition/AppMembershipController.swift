import Foundation

/// Single mutation boundary for app membership conversions.
///
/// Drawer membership is placement; kept membership means an entry survives app
/// exit. They may coexist. Messaging remains an alternative persistent identity.
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

    /// Native check-menu toggle. It never changes placement. Messaging apps use
    /// their own persistent identity and therefore cannot also become kept.
    func setKept(_ bundleID: String, enabled: Bool) {
        guard keptAppStore.canKeep(bundleID) else { return }
        if enabled {
            guard !messagingStore.contains(bundleID) else { return }
            keptAppStore.add(bundleID)
        } else {
            keptAppStore.remove(bundleID)
        }
    }

    /// Placement-only move. An explicit kept choice survives drawer round-trips.
    func moveToDrawer(_ bundleID: String) {
        guard canChangeMembership(bundleID) else { return }
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

    /// Startup repair. Finder keeps its dedicated slot. Kept wins only over the
    /// alternative messaging identity; drawer placement is deliberately preserved.
    func reconcileKeptWins() {
        let finder = KeptAppStore.forbiddenBundleID
        if drawerStore.contains(finder) {
            drawerStore.remove(finder)
        }
        if messagingStore.contains(finder) {
            messagingStore.unmark(finder)
        }

        for bundleID in keptAppStore.bundleIDs {
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
    /// Full placement list. Hidden members remain here so their drawer order is
    /// stable when a later launch makes them visible again.
    static func drawerMembers(drawerIDs: [String]) -> [String] {
        filteredUnique(drawerIDs, excluding: [])
    }

    /// Core drawer visibility rule: placement is durable, but a chip is rendered
    /// only while the app runs or another persistent identity keeps it reachable.
    static func visibleDrawerIDs(
        drawerIDs: [String],
        keptIDs: [String],
        messagingIDs: [String],
        runningIDs: Set<String>
    ) -> [String] {
        let retained = Set(keptIDs).union(messagingIDs).union(runningIDs)
        return filteredUnique(drawerIDs, excluding: []).filter { retained.contains($0) }
    }

    static func drawerPreview(
        drawerIDs: [String],
        keptIDs: [String],
        messagingIDs: [String],
        runningIDs: Set<String>,
        limit: Int = 9
    ) -> [String] {
        Array(visibleDrawerIDs(
            drawerIDs: drawerIDs,
            keptIDs: keptIDs,
            messagingIDs: messagingIDs,
            runningIDs: runningIDs
        ).prefix(max(0, limit)))
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
