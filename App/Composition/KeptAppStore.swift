import Foundation
import os

/// 「在程序坞中保留」的 app 列表。运行时照常显示窗口卡片；退出后收敛成一个 app 图标留在原位。
///
/// Finder 永远有独立常驻槽位，不由此 store 管理（`forbiddenBundleID`）。
/// 顺序由 `StripOrderStore` 统一管，此 store 只负责成员身份与持久化。
@MainActor
final class KeptAppStore: ObservableObject {
    static let forbiddenBundleID = "com.apple.finder"
    /// V3 lets a messaging app also be kept (kept alone now decides post-exit
    /// visibility). Key existence is the migration marker, including an explicitly
    /// persisted empty array on a fresh install. Older kept keys stay frozen
    /// read-only so a code rollback still reads the exact pre-upgrade list.
    static let defaultsKey = "keptAppBundleIDsV3"
    static let previousDefaultsKey = "keptAppBundleIDsV2"
    private static let v1Key = "keptAppBundleIDs"
    private static let legacyKey = "pinnedAppBundleIDs"
    private static let drawerKey = "drawerBundleIDs"
    private static let messagingV2Key = "messagingBundleIDsV2"
    private static let messagingV1Key = "messagingBundleIDs"

    @Published private(set) var bundleIDs: [String]

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "kept-app-store")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Already on V3.
        if defaults.object(forKey: Self.defaultsKey) != nil {
            let stored = defaults.stringArray(forKey: Self.defaultsKey) ?? []
            bundleIDs = Self.cleaned(stored)
            if bundleIDs != stored { persist() }
            return
        }

        // First migration to V3. Messaging apps now join kept so they stay visible
        // after exit under the unified model. Frozen legacy keys (V2 / V1 / pinned)
        // are left untouched for a clean code rollback.
        let messaging = Self.authoritativeMessagingNames(defaults)
        let seed: [String]
        if defaults.object(forKey: Self.previousDefaultsKey) != nil {
            // Kept V2 exists: keep its order first, messaging appended.
            let v2 = defaults.stringArray(forKey: Self.previousDefaultsKey) ?? []
            seed = v2 + messaging
        } else {
            // No kept V2 (upgrading straight past it): fold V1 + pinned + drawer + messaging.
            let v1 = defaults.stringArray(forKey: Self.v1Key) ?? []
            let legacy = defaults.stringArray(forKey: Self.legacyKey) ?? []
            let drawer = defaults.stringArray(forKey: Self.drawerKey) ?? []
            seed = v1 + legacy + drawer + messaging
        }
        bundleIDs = Self.cleaned(seed)
        persist() // Empty is intentional: V3 key existence is the migration marker.
        logger.info("initialized keptAppBundleIDsV3 with \(self.bundleIDs.count) entries")
    }

    /// Authoritative messaging names for the kept-V3 seed, independent of store
    /// init order: if the messaging V2 key exists (even an explicit empty array)
    /// read only it; otherwise fall back to the legacy messaging key. Never union.
    private static func authoritativeMessagingNames(_ defaults: UserDefaults) -> [String] {
        if defaults.object(forKey: messagingV2Key) != nil {
            return defaults.stringArray(forKey: messagingV2Key) ?? []
        }
        return defaults.stringArray(forKey: messagingV1Key) ?? []
    }

    static func canKeep(_ bundleID: String) -> Bool {
        guard let normalized = normalized(bundleID) else { return false }
        return normalized != forbiddenBundleID
    }

    func canKeep(_ bundleID: String) -> Bool {
        Self.canKeep(bundleID)
    }

    func contains(_ bundleID: String) -> Bool {
        guard let normalized = Self.normalized(bundleID) else { return false }
        return bundleIDs.contains(normalized)
    }

    func add(_ bundleID: String) {
        guard Self.canKeep(bundleID),
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

    private static func cleaned(_ bundleIDs: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for bundleID in bundleIDs {
            guard canKeep(bundleID),
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
