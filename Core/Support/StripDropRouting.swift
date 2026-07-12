import CoreGraphics
import Foundation

/// 外部文件拖入任务条的落点路由（纯函数，进单测）。
///
/// 所有输入坐标都在 `"strip"` 空间——`onDrop` 必须挂在**定义该坐标空间的同一层视图**上
/// （评审拍板：DropDelegate 的 location 与 `geo.frame(in: .named("strip"))` 必须同源，
/// 绝不能挂到 `.padding(shadowPadding)` 之后的内外层）。只做水平路由：拖到任务条上即算
/// 有效高度，垂直命中由 onDrop 挂载层保证。
enum StripDropRouting {
    enum Target: Equatable {
        /// 落在中转格 → 暂存（任何文件/文件夹，引用不搬家）。
        case stash
        /// 落在某个固定文件夹 chip → 把来源移入该文件夹。
        case moveInto(path: String)
        /// 落在文件夹区 → 固定目录到显示序 index 位（仅目录有效，由调用方过滤）。
        case pin(insertIndex: Int)
        /// 其他位置 → 拒绝。
        case none
    }

    /// - Parameters:
    ///   - location: drop 落点（"strip" 空间）。
    ///   - shelfFrame: 中转格 frame（独立 PreferenceKey 上报，**不混入 folderFrames**）。
    ///   - folderFrames: 文件夹 chip 帧（键 = StripEntry id，即 "folder-<path>"）。
    ///   - orderedPaths: 当前固定文件夹显示序（PinnedFolderStore.folderPaths）。
    ///   - tailSlack: 最后一个文件夹右侧仍算文件夹区的余量（没有文件夹时挂在中转格右侧，
    ///     覆盖「第一次拖目录进来固定」的空区场景）。
    static func route(location: CGPoint,
                      shelfFrame: CGRect,
                      folderFrames: [String: CGRect],
                      orderedPaths: [String],
                      tailSlack: CGFloat = 24) -> Target {
        guard shelfFrame != .zero else { return .none }   // 帧未就绪（首帧）不接
        if location.x < shelfFrame.minX { return .none }
        if location.x <= shelfFrame.maxX { return .stash }

        // onDrop 覆盖整条任务条的有效高度，路由保持既有的纯水平语义；不能用 contains，
        // 否则 chip 上下留白会意外退回 pin。
        if let path = orderedPaths.first(where: { path in
            guard let frame = folderFrames["folder-" + path] else { return false }
            return location.x >= frame.minX && location.x <= frame.maxX
        }) {
            return .moveInto(path: path)
        }

        let frames = orderedPaths.compactMap { folderFrames["folder-" + $0] }
        let zoneMaxX = (frames.map(\.maxX).max() ?? shelfFrame.maxX) + tailSlack
        guard location.x <= zoneMaxX else { return .none }

        // 插入序号 = 中点在落点左侧的文件夹个数（落在某 chip 左半边 → 插它前面）。
        let index = orderedPaths.filter { path in
            guard let frame = folderFrames["folder-" + path] else { return false }
            return frame.midX < location.x
        }.count
        return .pin(insertIndex: index)
    }
}
