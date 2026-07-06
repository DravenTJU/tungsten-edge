import AppKit
import SwiftUI

/// 文件夹 / 废纸篓弹窗的数据层：后台枚举 + 目录监视实时刷新。
/// generation 防串线（评审 P1）：下钻/刷新连发时，旧结果回来一律丢弃。
@MainActor
final class FolderPopupModel: ObservableObject {
    @Published private(set) var entries: [FolderContentsLoader.Entry] = []
    @Published private(set) var loadFailed = false
    @Published private(set) var didFirstLoad = false

    private var watcher: DirectoryWatcher?
    private var generation = 0

    func display(url: URL) {
        watcher?.stop()
        watcher = DirectoryWatcher(path: url.path) { [weak self] in
            Task { @MainActor [weak self] in self?.reload(url: url) }
        }
        reload(url: url)
    }

    func stop() {
        watcher?.stop()
        watcher = nil
    }

    private func reload(url: URL) {
        generation += 1
        let expected = generation
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try FolderContentsLoader.load(directory: url) }
            await MainActor.run { [weak self] in
                guard let self, self.generation == expected else { return }
                switch result {
                case .success(let list):
                    self.entries = FolderContentsLoader.sortedByDateAdded(list)
                    self.loadFailed = false
                case .failure:
                    self.entries = []
                    self.loadFailed = true
                }
                self.didFirstLoad = true
            }
        }
    }
}

/// 文件夹 / 废纸篓弹窗网格（Dock Stacks 网格的等价物）。
/// 单击文件 → 默认应用打开并关弹窗；单击子文件夹 → 面板内下钻（顶部返回）。
/// 排序「最新在前」，与 chip 封面的「最新文件」口径一致。
/// 列数固定 → 面板宽度恒定，只有高度随内容变，避免 fittingSize 宽度反馈环。
struct FolderGridPopupView: View {
    let rootURL: URL
    let rootTitle: String
    /// 废纸篓模式：读取失败时提示「完全磁盘访问」权限而非一般错误。
    let isTrash: Bool
    /// 网格可用高度上限（锚点上方 → 屏幕上沿，PanelCoordinator 算好传入），超出内部滚动。
    let maxContentHeight: CGFloat
    /// 打开文件后回调（协调器关弹窗）。
    var onFileOpened: () -> Void = {}
    /// 下钻/刷新导致内容高度变化 → 协调器动画重定位面板。
    var onContentResize: () -> Void = {}

    @StateObject private var model = FolderPopupModel()
    /// 下钻栈：空 = 根目录；push 子文件夹 URL。
    @State private var drillStack: [URL] = []
    @State private var isPresented = false
    /// 网格自然高度（量出来）。超过可用高度就内部滚动（同 DrawerView 的封顶策略）。
    @State private var gridHeight: CGFloat = 0

    private enum Style {
        static let columnCount = 4
        static let cellWidth: CGFloat = 84
        static let cellHeight: CGFloat = 80
        static let cellSpacing: CGFloat = 8
        static let headerHeight: CGFloat = 34
        static let contentPadding: CGFloat = 12
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Style.cellWidth), spacing: Style.cellSpacing), count: Style.columnCount)
    }

    private var currentURL: URL { drillStack.last ?? rootURL }
    private var currentTitle: String {
        drillStack.isEmpty ? rootTitle : FileManager.default.displayName(atPath: currentURL.path)
    }
    /// 表头之外留给网格的高度。
    private var availableGridHeight: CGFloat {
        max(120, maxContentHeight - Style.headerHeight)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DockVisualEffectView()
                .padding(-2)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if gridHeight > availableGridHeight + 0.5 {
                    ScrollView(.vertical, showsIndicators: true) { gridBody }
                        .frame(height: availableGridHeight)
                } else {
                    gridBody
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
        }
        .scaleEffect(isPresented ? 1 : 0.96, anchor: .bottom)
        .shadow(color: .black.opacity(0.35), radius: 15, x: 0, y: 8)
        .padding(PanelCoordinator.shadowPadding)
        .onAppear {
            model.display(url: rootURL)
            withAnimation(.easeOut(duration: DrawerAnimation.duration)) { isPresented = true }
        }
        .onDisappear { model.stop() }
        .onChange(of: drillStack) { _ in model.display(url: currentURL) }
        .onChange(of: gridHeight) { _ in onContentResize() }
    }

    // MARK: - 表头：返回 / 标题 / 在访达中打开

    private var header: some View {
        HStack(spacing: 8) {
            if !drillStack.isEmpty {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture { _ = drillStack.removeLast() }
                    .help("返回上一级")
            }
            Text(currentTitle)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 12)
            Text("在访达中打开")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .contentShape(Rectangle())
                .onTapGesture {
                    NSWorkspace.shared.open(currentURL)
                    onFileOpened()
                }
        }
        .padding(.horizontal, Style.contentPadding)
        .frame(height: Style.headerHeight)
    }

    // MARK: - 网格

    @ViewBuilder
    private var gridBody: some View {
        Group {
            if model.loadFailed {
                unreadableHint
            } else if model.entries.isEmpty && model.didFirstLoad {
                Text(isTrash ? "废纸篓是空的" : "文件夹是空的")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(columns: columns, spacing: Style.cellSpacing) {
                    ForEach(model.entries, id: \.url) { entry in
                        FolderGridCell(entry: entry) { open(entry) }
                    }
                }
                .animation(.easeInOut(duration: DrawerAnimation.duration), value: model.entries.map(\.url))
            }
        }
        .padding([.horizontal, .bottom], Style.contentPadding)
        // 固定 4 列的总宽度撑住面板宽度，内容多少都不变宽。
        .frame(width: CGFloat(Style.columnCount) * Style.cellWidth
            + CGFloat(Style.columnCount - 1) * Style.cellSpacing
            + Style.contentPadding * 2)
        .background(GeometryReader { g in
            Color.clear.preference(key: FolderGridHeightKey.self, value: g.size.height)
        })
        .onPreferenceChange(FolderGridHeightKey.self) { gridHeight = $0 }
    }

    /// 读取失败提示。废纸篓大概率是缺「完全磁盘访问」，给设置深链；普通文件夹给一般提示。
    private var unreadableHint: some View {
        VStack(spacing: 8) {
            Text(isTrash ? "无法读取废纸篓内容" : "无法读取文件夹内容")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            if isTrash {
                Text("需要在系统设置中授予「完全磁盘访问」权限\n（拖文件进垃圾桶删除不受影响）")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                Text("打开系统设置")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .contentShape(Capsule())
                    .onTapGesture {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func open(_ entry: FolderContentsLoader.Entry) {
        if entry.isDirectory {
            drillStack.append(entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
            onFileOpened()
        }
    }
}

/// 单个格子：40pt 图标 + 两行小字名，悬停浮白底。独立 struct 才能各自持有 hover 态。
private struct FolderGridCell: View {
    let entry: FolderContentsLoader.Entry
    let onTap: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: Self.icon(for: entry.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 40, height: 40)
            Text(entry.name)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .frame(width: 84, height: 80)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        .help(entry.name)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    /// 共享缓存对象必须 copy 再改 size（AppMenuFragments 惯例）。LazyVGrid 只实例化可见格,同步取图标够快。
    private static func icon(for path: String) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        guard let copy = icon.copy() as? NSImage else { return icon }
        copy.size = NSSize(width: 40, height: 40)
        return copy
    }
}

private struct FolderGridHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
