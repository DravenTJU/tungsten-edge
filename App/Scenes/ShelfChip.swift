import AppKit
import SwiftUI

/// 中转格：固定在文件夹区头位的暂存格（44×52，与文件夹 chip 完全同规格）。
/// 拖文件到格上松手即暂存（引用不搬家），点击弹出暂存网格。**不可拖拽**（固定头位）。
/// 视觉与 `PinnedFolderChip` 同族（owner 2026-07-06 反馈：风格要统一）：同一个
/// `StackedChipBackdrop` 堆叠纸片背景，前景是最新暂存项的图标/缩略图（有暂存时）或
/// 一个淡淡的托盘图标（空时）；数量**不做外凸角标**，改成悬停名字气泡里的文字（同文件夹
/// chip 悬停显示文件夹名的位置），避免和固定区其余 chip 的"零装饰"视觉基调冲突。
struct ShelfChip: View {
    let itemCount: Int
    /// 最新暂存项的预览图（nil = 空，显示占位托盘图标）。
    let previewImage: NSImage?
    let isDropTargeted: Bool
    let onTap: () -> Void
    let onClear: () -> Void
    let onAddFolder: () -> Void

    @State private var isHovering = false

    var body: some View {
        let coverSize: CGFloat = isHovering ? 24 : 34   // 与 PinnedFolderChip 完全一致的尺寸口径
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            stackedCover(size: coverSize)
            if isHovering {
                Text(itemCount > 0 ? "中转 · \(itemCount)" : "中转")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 44, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isDropTargeted ? 0.22 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        .nativeContextMenu { buildMenu() }
        .help("中转：拖文件到这里暂存")
        .animation(.easeInOut(duration: 0.18), value: isHovering)
        .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
    }

    private func stackedCover(size: CGFloat) -> some View {
        StackedChipBackdrop(size: size) { frontFace(size: size) }
    }

    /// 有暂存：最新项的图标/缩略图，方形裁切 + 细白边（同文件夹 chip 的"缩略图"渲染）。
    /// 空：托盘图标 fit 渲染（同文件夹 chip 空文件夹时的"图标"渲染，不裁不描边）。
    @ViewBuilder
    private func frontFace(size: CGFloat) -> some View {
        if let previewImage {
            Image(nsImage: previewImage)
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
            Image(systemName: "tray.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size * 0.46, height: size * 0.46)
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("打开中转") { onTap() })
        if itemCount > 0 {
            menu.addItem(ClosureMenuItem("清空中转") { onClear() })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("添加文件夹…") { onAddFolder() })
        return menu
    }
}
