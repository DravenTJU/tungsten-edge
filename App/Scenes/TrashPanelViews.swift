import AppKit
import SwiftUI

/// 垃圾桶卫星面板的 AppKit 容器：**全仓第一个 NSDraggingDestination**——接收 Finder 文件拖放，
/// 逐个 `FileManager.trashItem` 移入废纸篓（无需完全磁盘访问,可在访达撤销）。
/// hosting 子视图没注册拖放类型,系统把拖放一律路由到本容器；MenuHostNSView 仍只接管右键,互不冲突。
@MainActor
final class TrashDropContainerView: NSView {
    var trashState: TrashStateStore?
    var onDropCompleted: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) else { return [] }
        trashState?.isDropHovering = true
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        trashState?.isDropHovering = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        trashState?.isDropHovering = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        trashState?.isDropHovering = false
        let urls = (sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []
        var movedAny = false
        for url in urls where (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil {
            movedAny = true
        }
        if movedAny { onDropCompleted?() }
        return movedAny
    }
}

/// 垃圾桶按钮视图（外观同 DrawerCapsuleButton 的磨砂胶囊）。图标随空/满切换；
/// Finder 拖放悬停时微微发光放大（对称胶囊的收纳反馈）。点击/右键遵循全仓惯例。
struct TrashCapsuleView: View {
    @ObservedObject var trashState: TrashStateStore
    let onTap: () -> Void
    let onEmptyTrash: () -> Void
    let onHide: () -> Void

    var body: some View {
        ZStack {
            DockVisualEffectView()
                .padding(-2)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .ignoresSafeArea()

            Image(systemName: trashState.isFull ? "trash.fill" : "trash")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        }
        .scaleEffect(trashState.isDropHovering ? 1.06 : 1.0)
        .shadow(color: .white.opacity(trashState.isDropHovering ? 0.22 : 0),
                radius: trashState.isDropHovering ? 6 : 0)
        .animation(.easeInOut(duration: 0.15), value: trashState.isDropHovering)
        .shadow(color: .black.opacity(0.35), radius: 15, x: 0, y: 8)
        .padding(PanelCoordinator.shadowPadding)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .nativeContextMenu { buildMenu() }
        .help("废纸篓")
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem("打开废纸篓") { onTap() })
        menu.addItem(ClosureMenuItem("在访达中打开") {
            NSWorkspace.shared.open(TrashStateStore.userTrashURL)
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("清倒废纸篓…") { onEmptyTrash() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("隐藏垃圾桶") { onHide() })
        return menu
    }
}
