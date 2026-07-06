import Foundation

/// 固定文件夹/废纸篓内容读取与排序。`load` 走文件系统（调用方放后台队列）；
/// 排序与选封面是纯函数，进单测。枚举一律跳过隐藏文件。
enum FolderContentsLoader {
    struct Entry: Equatable {
        var url: URL
        var name: String
        var isDirectory: Bool
        var dateAdded: Date?
        var dateModified: Date?
    }

    static func load(directory: URL) throws -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .addedToDirectoryDateKey, .contentModificationDateKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            return Entry(
                url: url,
                name: FileManager.default.displayName(atPath: url.path),
                isDirectory: values?.isDirectory ?? false,
                dateAdded: values?.addedToDirectoryDate,
                dateModified: values?.contentModificationDate
            )
        }
    }

    /// 加入日期降序（最新在前）；网络卷等场景 dateAdded 可能为 nil，用修改日期兜底；
    /// 同刻再按本地化文件名升序破平，保证排序稳定。
    static func sortedByDateAdded(_ entries: [Entry]) -> [Entry] {
        entries.sorted { a, b in
            let da = a.dateAdded ?? a.dateModified ?? .distantPast
            let db = b.dateAdded ?? b.dateModified ?? .distantPast
            if da != db { return da > db }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    /// 封面用：最新的**文件**（子文件夹不做封面）。
    static func newestFile(in entries: [Entry]) -> Entry? {
        sortedByDateAdded(entries).first { !$0.isDirectory }
    }
}
