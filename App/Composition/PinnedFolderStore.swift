import Foundation

/// 固定文件夹区的持久层：有序文件夹路径列表（顺序即显示序，未来拖拽重排改这个数组）。
/// 应用非沙盒，存标准化裸路径即可，无需 security-scoped bookmark。
@MainActor
final class PinnedFolderStore: ObservableObject {
    @Published private(set) var folderPaths: [String] = []
    private let key = "pinnedFolderPaths"

    init() {
        folderPaths = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func contains(_ path: String) -> Bool { folderPaths.contains(Self.normalized(path)) }

    func add(_ path: String) {
        let normalized = Self.normalized(path)
        guard !normalized.isEmpty, !folderPaths.contains(normalized) else { return }
        folderPaths.append(normalized)
        persist()
    }

    func remove(_ path: String) {
        let normalized = Self.normalized(path)
        folderPaths.removeAll { $0 == normalized }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(folderPaths, forKey: key)
    }

    /// 标准化：展开 ~ / 折叠 .. 并去尾斜杠，保证同一文件夹只固定一次。
    static func normalized(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
