import AppKit
import SwiftUI

/// 中转格：固定在文件夹区头位的暂存格。
/// 拖文件到格上松手即暂存（引用不搬家），点击弹出暂存网格。**不可拖拽**（固定头位）。
/// 视觉上采用普通 app 图标的圆角与阴影风格，不再使用文件夹的堆叠样式。
/// 数量**不做外凸角标**，改成悬停名字气泡里的文字，避免与固定区其余 chip 的"零装饰"视觉基调冲突。
struct ShelfChip: View {
    let itemCount: Int
    let isDropTargeted: Bool
    let onTap: () -> Void
    let onClear: () -> Void
    let onAddFolder: () -> Void

    @State private var isHovering = false

    var body: some View {
        let coverSize: CGFloat = isHovering ? 24 : 36
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            shelfIcon(size: coverSize)
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
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        .nativeContextMenu { buildMenu() }
        .help("中转：拖文件到这里暂存")
        .animation(.easeInOut(duration: 0.18), value: isHovering)
        .animation(.easeInOut(duration: 0.12), value: isDropTargeted)
    }

    /// 固定入口图标：外层保持普通 app chip 的 36/24 槽位，内部半透明底板缩到视觉尺寸。
    /// 投放反馈：在内部底板进行提亮与加亮描边，消除外层大框。
    private func shelfIcon(size: CGFloat) -> some View {
        let innerSize: CGFloat = size > 30 ? 32 : 22
        let bgColor = isDropTargeted 
            ? Color.white.opacity(0.28)
            : Color.white.opacity(0.12)
        let strokeOpacity = isDropTargeted ? 0.4 : 0.18
        
        return ZStack {
            RoundedRectangle(cornerRadius: innerSize / 4, style: .continuous)
                .fill(bgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: innerSize / 4, style: .continuous)
                        .strokeBorder(.white.opacity(strokeOpacity), lineWidth: 0.5)
                )
                .shadow(color: .white.opacity(isDropTargeted ? 0.25 : 0), radius: isDropTargeted ? 2 : 0)
            Image(systemName: "tray.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: innerSize * 0.46, height: innerSize * 0.46)
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: innerSize, height: innerSize)
        .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
        .frame(width: size, height: size)
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
