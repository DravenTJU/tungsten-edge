import CoreGraphics

/// 固定文件夹 chip 拖动松手时的落点分类（纯函数，进单测）。
///
/// 坐标系：调用方先把 `DragController.globalLocation`（屏幕坐标）通过 `stripPoint(from:)`
/// 换算成 "strip" 局部坐标点，再传给 `classify`。`stripVisibleRect` 是任务条内容可见区域
/// （"strip" 局部坐标下就是 `(0,0)`–`stripRootScreenRect.size`，天然不含 shadowPadding 透明边，
/// 不需要额外换算）。`folderZoneMaxX` 是固定区（中转格 + 文件夹 chip）在同一坐标系下的右边界。
/// 边界不加缓冲——owner 反馈明确要求「命中范围按可见区域算，不留大缓冲区」。
enum FolderChipDropZone: Equatable {
    /// 仍在固定区内：区内重排已在拖动过程中实时提交，松手无额外动作。
    case folderZone
    /// 落在任务条窗口区：取消固定 + 打开该文件夹的真实 Finder 窗口（调用方负责，非本类型职责）。
    case liveZone
    /// 落在任务条可见范围外：移除固定。
    case outsideStrip

    static func classify(point: CGPoint, stripVisibleRect: CGRect, folderZoneMaxX: CGFloat) -> FolderChipDropZone {
        guard stripVisibleRect.contains(point) else { return .outsideStrip }
        return point.x <= folderZoneMaxX ? .folderZone : .liveZone
    }
}

/// 固定文件夹拖拽的屏幕坐标几何快照。
///
/// `DragController` 的最终 mouseUp 坐标是屏幕坐标；这里封装成纯转换，避免最终落定再依赖
/// SwiftUI 手势回调。`stripScreenRect` 是任务条可见内容区屏幕 frame，不含 shadowPadding。
struct FolderChipDropGeometry: Equatable {
    let stripScreenRect: CGRect
    let folderZoneMaxX: CGFloat

    func classify(screenPoint: CGPoint) -> FolderChipDropZone {
        guard stripScreenRect != .zero else { return .outsideStrip }
        let localPoint = CGPoint(
            x: screenPoint.x - stripScreenRect.minX,
            y: stripScreenRect.maxY - screenPoint.y
        )
        return FolderChipDropZone.classify(
            point: localPoint,
            stripVisibleRect: CGRect(origin: .zero, size: stripScreenRect.size),
            folderZoneMaxX: folderZoneMaxX
        )
    }
}
