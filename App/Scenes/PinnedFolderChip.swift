import AppKit
import SwiftUI

/// 固定文件夹的堆叠 chip（Dock Stacks 观感）：背后两片低透明度圆角「纸」错位叠出堆叠感，
/// 前景是该文件夹最新文件的缩略图封面（PinnedFolderCoverStore 供图；空文件夹时是文件夹图标）。
/// 不显示文字；悬停浮出名字气泡（同 bareIconChip 样式）+ .help 原生气泡。
/// 点击一律 onTapGesture（nonactivatingPanel 上勿用 Button）；右键 = 手搓 NSMenu。
struct PinnedFolderChip: View {
    let path: String
    let cover: FolderCover?
    /// 当前排序方式（菜单打勾用;menu builder 每次右键现建,读到的总是最新值）。
    let sortOrder: FolderSortOrder
    let onTap: () -> Void
    let onAddFolder: () -> Void
    let onRemove: () -> Void
    let onSetSortOrder: (FolderSortOrder) -> Void

    @State private var isHovering = false

    private var folderName: String {
        FileManager.default.displayName(atPath: path)
    }

    var body: some View {
        let coverSize: CGFloat = isHovering ? 24 : 34
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            stackedCover(size: coverSize)
            if isHovering {
                Text(folderName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 64)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 44, height: 52)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        .nativeContextMenu { buildMenu() }
        .help(folderName)
        .animation(.easeInOut(duration: 0.18), value: isHovering)
    }

    /// 堆叠观感：两片「纸」垫底（依次上移、略小），封面盖最前。封面是缩略图时方形裁切 + 细白边；
    /// 是文件夹图标时不裁不描边（图标本身有形状）。背景片本身抽成 `StackedChipBackdrop`。
    private func stackedCover(size: CGFloat) -> some View {
        StackedChipBackdrop(size: size) { coverImage(size: size) }
    }

    @ViewBuilder
    private func coverImage(size: CGFloat) -> some View {
        if let cover, cover.isThumbnail {
            // 真缩略图：方形裁切 + 细白边,Stacks 封面观感。
            Image(nsImage: cover.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
                )
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
        menu.addItem(ClosureMenuItem("打开") { onTap() })
        menu.addItem(ClosureMenuItem("在访达中打开") {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        })
        menu.addItem(.separator())
        // 排序方式 ▸（原生 Stacks 同款）：弹窗网格与堆叠封面都跟随,逐文件夹记忆。
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

/// 固定区 chip 家族（目前为文件夹 chip）的"堆叠纸片"背景。
/// 两片纸依次上移、略小,前景内容由调用方叠加（自带阴影，同旧版 stackedCover 数值）。
struct StackedChipBackdrop<Content: View>: View {
    let size: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.14))
                .frame(width: size - 4, height: size - 4)
                .offset(y: -4)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.28))
                .frame(width: size - 2, height: size - 2)
                .offset(y: -2)
            content()
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
    }
}
