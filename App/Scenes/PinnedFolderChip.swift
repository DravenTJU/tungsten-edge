import AppKit
import SwiftUI

/// 固定文件夹 chip：扁平单封面（无堆叠纸片），尺寸与其他 chip 一致。
/// 封面是该文件夹当前排序第一张文件的缩略图（PinnedFolderCoverStore 供图；空文件夹/无缩略图时是图标）。
/// 名称常驻在封面下方，长名截断并用 .help 提供全名。
/// 点击一律 onTapGesture（nonactivatingPanel 上勿用 Button）；右键 = 手搓 NSMenu。
struct PinnedFolderChip: View {
    let path: String
    let cover: FolderCover?
    /// 当前排序方式（菜单打勾用;menu builder 每次右键现建,读到的总是最新值）。
    let sortOrder: FolderSortOrder
    let onTap: () -> Void
    /// 内容预览（右键「预览内容」；左键在 preview 模式下也走这个）。
    let onPreview: () -> Void
    /// 打开该路径访达窗口（右键「在访达中打开」；左键在 openFinderWindow 模式下也走这个）。
    let onOpenInFinder: () -> Void
    let onAddFolder: () -> Void
    let onRemove: () -> Void
    let onSetSortOrder: (FolderSortOrder) -> Void
    var isDropTarget = false

    @State private var isHovering = false

    private var folderName: String {
        FileManager.default.displayName(atPath: path)
    }

    var body: some View {
        let coverSize: CGFloat = 26
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            coverImage(size: coverSize)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(isDropTarget ? 0.9 : 0), lineWidth: 1.5)
                }
                .scaleEffect(isDropTarget ? 1.08 : 1)
            Text(folderName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 48)
            Spacer(minLength: 0)
        }
        .frame(width: 52, height: 52)
        .contentShape(Rectangle())
        // 悬停：整个 chip 放大上顶（原生 Dock 手感）。anchor .bottom 让底部名称基本不动、封面往上顶起。
        // scaleEffect 只是渲染变换，不改布局 frame——拖放命中读的是 .background GeometryReader 上报的未缩放 frame，不受影响。
        .scaleEffect(isHovering ? 1.12 : 1, anchor: .bottom)
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        .nativeContextMenu { buildMenu() }
        .help(folderName)
        .animation(.easeOut(duration: 0.12), value: isDropTarget)
        .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    /// 封面：真缩略图方形裁切 + 细白边；文件图标 / 空文件夹图标 fit 渲染不裁不描边。
    /// 缩略图**满铺无留白**,视觉比 app 图标(.fit 自带约 20% 留白)大,故按 5/6 缩到其可见方块尺寸；
    /// 图标自带留白、本就与 app 图标同口径,维持 size 不缩。
    @ViewBuilder
    private func coverImage(size: CGFloat) -> some View {
        if let cover, cover.isThumbnail {
            // 真缩略图：方形裁切 + 细白边（缩到 app 图标可见方块尺寸;圆角 thumb/4）。
            let thumb = size * 5 / 6
            Image(nsImage: cover.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: thumb, height: thumb)
                .clipShape(RoundedRectangle(cornerRadius: thumb / 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: thumb / 4, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                )
                .frame(width: size, height: size)
        } else {
            // 图标（文件图标垫底 / 空文件夹的文件夹图标）：fit 渲染,不裁不描边。
            Image(nsImage: cover?.image ?? PinnedFolderCoverStore.icon(forPath: path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("预览内容") { onPreview() })
        menu.addItem(ClosureMenuItem("在访达中打开") { onOpenInFinder() })
        menu.addItem(.separator())
        // 排序方式 ▸（原生 Stacks 同款）：弹窗网格与 chip 封面都跟随,逐文件夹记忆。
        let sortItem = NSMenuItem(title: "排序方式", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu()
        for order in FolderSortOrder.allCases {
            let item = ClosureMenuItem(order.menuTitle) { onSetSortOrder(order) }
            item.state = order == sortOrder ? .on : .off
            sortMenu.addItem(item)
        }
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("添加文件夹…") { onAddFolder() })
        menu.addItem(ClosureMenuItem("从固定区移除") { onRemove() })
        return menu
    }
}
