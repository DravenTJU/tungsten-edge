import AppKit
import QuickLookThumbnailing

/// 固定文件夹 chip 的封面：该文件夹「最新文件」的 Quick Look 缩略图。
/// 枚举在后台队列；每个文件夹带 generation 计数，QL 异步回调回来时核对
/// generation 未变才发布，防旧结果覆盖新封面；@Published 只在 MainActor 写。
/// chip 封面：isThumbnail 决定渲染方式——真缩略图方形裁切+细白边,图标（文件/文件夹）fit 不裁。
struct FolderCover: Equatable {
    var image: NSImage
    var isThumbnail: Bool
}

@MainActor
final class PinnedFolderCoverStore: ObservableObject {
    /// path → 封面。兜底链：最新文件缩略图 → 最新文件图标 → 文件夹图标（空文件夹）。
    @Published private(set) var covers: [String: FolderCover] = [:]

    private var watchers: [String: DirectoryWatcher] = [:]
    private var generations: [String: Int] = [:]
    /// newestFilePath|modDate → 缩略图；最新文件没变就不再生成。
    private let thumbnailCache = NSCache<NSString, NSImage>()

    /// 与 PinnedFolderStore.folderPaths 对账：多退少补 watcher，全量刷新一次封面。
    func sync(paths: [String]) {
        let wanted = Set(paths)
        for gone in Array(watchers.keys) where !wanted.contains(gone) {
            watchers[gone]?.stop()
            watchers[gone] = nil
            covers[gone] = nil
            generations[gone] = nil
        }
        for path in paths {
            if watchers[path] == nil {
                // DirectoryWatcher 回调已在主线程；Task 包一层过 MainActor 隔离。
                watchers[path] = DirectoryWatcher(path: path) { [weak self] in
                    Task { @MainActor [weak self] in self?.refresh(path: path) }
                }
            }
            refresh(path: path)
        }
    }

    private func refresh(path: String) {
        let generation = (generations[path] ?? 0) + 1
        generations[path] = generation
        let folderURL = URL(fileURLWithPath: path)

        Task.detached(priority: .utility) { [weak self] in
            let entries = (try? FolderContentsLoader.load(directory: folderURL)) ?? []
            let newest = FolderContentsLoader.newestFile(in: entries)
            await MainActor.run { [weak self] in
                guard let self, self.generations[path] == generation else { return }
                self.publishCover(path: path, newest: newest, generation: generation)
            }
        }
    }

    private func publishCover(path: String, newest: FolderContentsLoader.Entry?, generation: Int) {
        guard let newest else {
            covers[path] = FolderCover(image: Self.icon(forPath: path), isThumbnail: false)
            return
        }
        let cacheKey = "\(newest.url.path)|\(newest.dateModified?.timeIntervalSince1970 ?? 0)" as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            covers[path] = FolderCover(image: cached, isThumbnail: true)
            return
        }
        // 先用最新文件的图标垫底，QL 缩略图好了再无感升级。
        covers[path] = FolderCover(image: Self.icon(forPath: newest.url.path), isThumbnail: false)

        let request = QLThumbnailGenerator.Request(
            fileAt: newest.url,
            size: CGSize(width: 64, height: 64),
            scale: 2,
            representationTypes: .thumbnail
        )
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let cgImage = representation?.cgImage else { return }  // 生成失败保留图标垫底
            let image = NSImage(cgImage: cgImage, size: .zero)
            Task { @MainActor [weak self] in
                guard let self, self.generations[path] == generation else { return }
                self.thumbnailCache.setObject(image, forKey: cacheKey)
                self.covers[path] = FolderCover(image: image, isThumbnail: true)
            }
        }
    }

    /// NSWorkspace 图标是共享缓存对象，必须 `.copy()` 再改 size（AppMenuFragments 同款惯例）。
    static func icon(forPath path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        guard let copy = icon.copy() as? NSImage else { return icon }
        copy.size = NSSize(width: 64, height: 64)
        return copy
    }
}
