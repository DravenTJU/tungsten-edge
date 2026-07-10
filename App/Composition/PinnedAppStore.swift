import Foundation

/// Ordered app-level entries pinned to the strip's leading zone.
///
/// Finder keeps its dedicated persistent entry and must never be represented by this
/// store. `AppMembershipController` owns cross-store exclusivity; this type owns only
/// validation, order, and persistence of pinned membership. Reordering is persisted
/// even though the current UI does not expose pinned-app drag sorting yet.
@MainActor
final class PinnedAppStore: ObservableObject {
    static let forbiddenBundleID = "com.apple.finder"
    static let defaultsKey = "pinnedAppBundleIDs"

    @Published private(set) var bundleIDs: [String]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        bundleIDs = Self.cleaned(stored)
        if bundleIDs != stored {
            persist()
        }
    }

    static func canPin(_ bundleID: String) -> Bool {
        guard let normalized = normalized(bundleID) else { return false }
        return normalized != forbiddenBundleID
    }

    func canPin(_ bundleID: String) -> Bool {
        Self.canPin(bundleID)
    }

    func contains(_ bundleID: String) -> Bool {
        guard let normalized = Self.normalized(bundleID) else { return false }
        return bundleIDs.contains(normalized)
    }

    func add(_ bundleID: String) {
        guard Self.canPin(bundleID),
              let normalized = Self.normalized(bundleID),
              !bundleIDs.contains(normalized) else { return }
        bundleIDs.append(normalized)
        persist()
    }

    func remove(_ bundleID: String) {
        guard let normalized = Self.normalized(bundleID) else { return }
        let previousCount = bundleIDs.count
        bundleIDs.removeAll { $0 == normalized }
        if bundleIDs.count != previousCount {
            persist()
        }
    }

    func reorder(draggedBundleID: String, relativeTo targetBundleID: String, after: Bool) {
        guard let dragged = Self.normalized(draggedBundleID),
              let target = Self.normalized(targetBundleID) else { return }
        let next = StripOrdering.reordering(
            bundleIDs,
            move: dragged,
            relativeTo: target,
            after: after
        )
        guard next != bundleIDs else { return }
        bundleIDs = next
        persist()
    }

    private static func cleaned(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for bundleID in bundleIDs {
            guard canPin(bundleID),
                  let normalized = normalized(bundleID),
                  seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    private static func normalized(_ bundleID: String) -> String? {
        let normalized = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func persist() {
        defaults.set(bundleIDs, forKey: Self.defaultsKey)
    }
}
