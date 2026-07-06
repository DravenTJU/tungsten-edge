import AppKit

/// 废纸篓空/满状态。**只覆盖用户主目录废纸篓**——外置卷文件经 trashItem 会进该卷
/// `.Trashes/<uid>`，第一批不枚举 per-volume trash（评审 P1 范围决策，见 AGENTS）。
/// 无「完全磁盘访问」权限时列不到内容：isReadable=false、isFull 保持 false，弹窗给权限提示。
@MainActor
final class TrashStateStore: ObservableObject {
    @Published private(set) var isFull = false
    @Published private(set) var isReadable = true
    /// Finder 文件拖到垃圾桶上方的悬停高亮（TrashDropContainerView 驱动）。
    @Published var isDropHovering = false

    static var userTrashURL: URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
    }

    private var watcher: DirectoryWatcher?

    func start() {
        guard watcher == nil else { return }
        watcher = DirectoryWatcher(path: Self.userTrashURL.path) { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        let url = Self.userTrashURL
        Task.detached(priority: .utility) { [weak self] in
            let names = try? FileManager.default.contentsOfDirectory(atPath: url.path)
            await MainActor.run { [weak self] in
                guard let self else { return }
                if let names {
                    self.isReadable = true
                    // 只剩 .DS_Store 也算空，与系统 Dock 的空/满图标口径一致。
                    self.isFull = names.contains { $0 != ".DS_Store" }
                } else {
                    self.isReadable = false
                    self.isFull = false
                }
            }
        }
    }
}
