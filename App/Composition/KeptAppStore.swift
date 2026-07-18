import Foundation
import os

/// 「在程序坞中保留」的 app 列表。运行时照常显示窗口卡片；退出后收敛成一个 app 图标留在原位。
///
/// Finder 永远有独立常驻槽位，不由此 store 管理（`forbiddenBundleID`）。
/// 顺序由 `StripOrderStore` 统一管，此 store 只负责成员身份与持久化。
@MainActor
final class KeptAppStore: ObservableObject {
    static let forbiddenBundleID = "com.apple.finder"
    /// V2 separates "where the app is placed" (DrawerStore) from "keep an entry
    /// after the app exits". Key existence is the migration marker, including an
    /// explicitly persisted empty array on a fresh install.
    static let defaultsKey = "keptAppBundleIDsV2"
    static let previousDefaultsKey = "keptAppBundleIDs"
    private static let legacyKey = "pinnedAppBundleIDs"
    private static let drawerKey = "drawerBundleIDs"
    private static let messagingKey = "messagingBundleIDs"

    @Published private(set) var bundleIDs: [String]

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "kept-app-store")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Self.defaultsKey) != nil {
            let stored = defaults.stringArray(forKey: Self.defaultsKey) ?? []
            bundleIDs = Self.cleaned(stored)
            defaults.removeObject(forKey: Self.legacyKey)
            if bundleIDs != stored { persist() }
            return
        }

        // V1 treated every drawer placement as implicitly kept. Preserve that
        // visible behavior once, while leaving the old kept key untouched so a
        // code rollback still reads the exact pre-upgrade kept list.
        let previous = defaults.stringArray(forKey: Self.previousDefaultsKey) ?? []
        let legacy = defaults.stringArray(forKey: Self.legacyKey) ?? []
        let drawer = defaults.stringArray(forKey: Self.drawerKey) ?? []
        let messaging = Set(defaults.stringArray(forKey: Self.messagingKey) ?? [])
        bundleIDs = Self.cleaned(previous + legacy + drawer.filter { !messaging.contains($0) })
        defaults.removeObject(forKey: Self.legacyKey)
        persist() // Empty is intentional: V2 key existence is the migration marker.
        logger.info("initialized keptAppBundleIDsV2 with \(self.bundleIDs.count) entries")
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
