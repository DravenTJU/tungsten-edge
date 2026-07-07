import AppKit
import SwiftUI

/// 固定文件夹弹窗的数据层：后台枚举 + 目录监视实时刷新。
/// generation 防串线（评审 P1）：下钻/刷新连发时，旧结果回来一律丢弃。
@MainActor
final class FolderPopupModel: ObservableObject {
    @Published private(set) var entries: [FolderContentsLoader.Entry] = []
    @Published private(set) var loadFailed = false
    @Published private(set) var didFirstLoad = false

    private var watcher: DirectoryWatcher?
    private var generation = 0
    /// 该文件夹的排序方式（开窗时定死；改排序走协调器原地切换重开,不在窗内热切）。
    var sortOrder: FolderSortOrder = .default

    /// 预载路径：开窗前协调器已在后台读好内容，首帧即完整网格（散装感根因修复）。
    func seed(entries: [FolderContentsLoader.Entry]) {
        self.entries = entries
        didFirstLoad = true
    }

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
                    // 内容没变就不发布——预载后 watcher 挂载时的首次 reload 多为同内容,
                    // 不触发任何刷新/动画（入场期间内容零变化是验收标准）。
                    let sorted = FolderContentsLoader.sorted(list, by: self.sortOrder)
                    if sorted != self.entries { self.entries = sorted }
                    if self.loadFailed { self.loadFailed = false }
                case .failure:
                    if !self.entries.isEmpty { self.entries = [] }
                    if !self.loadFailed { self.loadFailed = true }
                }
                if !self.didFirstLoad { self.didFirstLoad = true }
            }
        }
    }
}

final class PopupState: ObservableObject {
    @Published var isPresented: Bool = false
}

/// 固定文件夹弹窗网格——对齐原生 Stacks 网格（owner 2026-07-06）：
/// **无表头**；「在访达中打开」是网格**尾格**（带访达图标）；下钻后左上角浮小返回箭头。
/// 64pt 大图标、96pt 格宽、列数 = clamp(总格数, 3, 6)——宽度由条目数**推导**（确定值），
/// 不是测量值，无 fittingSize 反馈环；小文件夹面板自动收窄（原生同款）。
/// 排序「最新在前」，与 chip 封面的「最新文件」口径一致。
struct FolderGridPopupView: View {
    let rootURL: URL
    /// 网格可用高度上限（锚点上方 → 屏幕上沿，PanelCoordinator 算好传入），超出内部滚动。
    let maxContentHeight: CGFloat
    /// 打开文件后回调（协调器关弹窗）。右键菜单的「打开类」动作也走它（关闭语义评审拍板）。
    var onFileOpened: () -> Void = {}
    /// 下钻/刷新导致内容尺寸（宽或高）变化 → 协调器动画重定位面板。
    var onContentResize: () -> Void = {}
    /// 目录条目右键「固定到固定区」（协调器接 PinnedFolderStore）。nil = 不显示该项。
    var onPinFolder: ((URL) -> Void)?
    /// 已固定判定（已固定的目录不再显示「固定到固定区」）。
    var isFolderPinned: ((URL) -> Bool)?

    @StateObject private var model: FolderPopupModel
    @EnvironmentObject var popupState: PopupState
    /// 下钻栈：空 = 根目录；push 子文件夹 URL。
    @State private var drillStack: [URL] = []
    /// 网格自然高度（量出来）。超过可用高度就内部滚动（同 DrawerView 的封顶策略）。
    @State private var gridHeight: CGFloat = 0
    /// 首次内容就位**之后**才开网格增删动画——首播（预载或超时回填）一律整块出现,不逐格插入。
    @State private var animatesGridChanges = false

    init(rootURL: URL,
         initialEntries: [FolderContentsLoader.Entry]?,
         sortOrder: FolderSortOrder = .default,
         maxContentHeight: CGFloat,
         onFileOpened: @escaping () -> Void = {},
         onContentResize: @escaping () -> Void = {},
         onPinFolder: ((URL) -> Void)? = nil,
         isFolderPinned: ((URL) -> Bool)? = nil) {
        self.rootURL = rootURL
        self.maxContentHeight = maxContentHeight
        self.onFileOpened = onFileOpened
        self.onContentResize = onContentResize
        self.onPinFolder = onPinFolder
        self.isFolderPinned = isFolderPinned
        _model = StateObject(wrappedValue: {
            let model = FolderPopupModel()
            model.sortOrder = sortOrder
            if let initialEntries { model.seed(entries: initialEntries) }
            return model
        }())
    }

    private typealias Style = FolderPopupStyle

    private var currentURL: URL { drillStack.last ?? rootURL }

    /// 总格数 = 条目 + 尾格「在访达中打开」。列数由它推导（确定值,非测量）。
    private var totalCellCount: Int { model.entries.count + 1 }
    private var columnCount: Int { min(Style.maxColumns, max(Style.minColumns, totalCellCount)) }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Style.cellWidth), spacing: Style.cellSpacing), count: columnCount)
    }
    private var contentWidth: CGFloat {
        CGFloat(columnCount) * Style.cellWidth
            + CGFloat(columnCount - 1) * Style.cellSpacing
            + Style.contentPadding * 2
    }
    private var availableGridHeight: CGFloat { min(max(140, maxContentHeight), Style.maxGridHeight) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            DockVisualEffectView()
                .padding(-2)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .ignoresSafeArea()

            Group {
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
        // 原生同款：下钻后左上角浮返回箭头（无表头,不占布局）。
        .overlay(alignment: .topLeading) { backChip }
        .scaleEffect(popupState.isPresented ? 1 : 0.85, anchor: .bottom)
        .animation(.easeOut(duration: popupState.isPresented ? PopoverAnimation.openDuration : PopoverAnimation.closeDuration), value: popupState.isPresented)
        // 阴影延伸(radius+|y|)必须 ≤ shadowPadding(20),否则在面板透明边处被硬切（owner 反馈的裁切感）。
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 5)
        .padding(PanelCoordinator.shadowPadding)
        .onAppear {
            model.display(url: rootURL)
            if model.didFirstLoad { animatesGridChanges = true }   // 预载路径:首帧已完整,后续变化可动画
        }
        .onDisappear { model.stop() }
        .onChange(of: model.didFirstLoad) { loaded in
            guard loaded else { return }
            // 超时兜底路径:首次回填那一帧不动画,下一个 runloop 才开——整块出现。
            DispatchQueue.main.async { animatesGridChanges = true }
        }
        .onChange(of: drillStack) { _ in model.display(url: currentURL) }
        .onChange(of: gridHeight) { _ in onContentResize() }
        // 列数变化会只变宽不变高（如 5→6 格同一行）,高度探针不触发,单独驱动重定位。
        .onChange(of: columnCount) { _ in onContentResize() }
    }

    // MARK: - 返回浮标（仅下钻时）

    @ViewBuilder
    private var backChip: some View {
        if !drillStack.isEmpty {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: Style.backChipSize, height: Style.backChipSize)
                .background(Circle().fill(.white.opacity(0.16)))
                .overlay(Circle().strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
                .contentShape(Circle())
                .onTapGesture { _ = drillStack.removeLast() }
                .help("返回上一级")
                .padding(10)
                .transition(.opacity)
        }
    }

    // MARK: - 网格

    private var gridBody: some View {
        VStack(spacing: 0) {
            if model.loadFailed {
                Text("无法读取文件夹内容")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else if model.entries.isEmpty && model.didFirstLoad {
                Text("文件夹是空的")
                    .font(.system(size: Style.labelSize))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            LazyVGrid(columns: columns, spacing: Style.cellSpacing) {
                ForEach(model.entries, id: \.url) { entry in
                    FolderGridCell(iconPath: entry.url.path,
                                   staticIcon: nil,
                                   label: entry.name,
                                   dragURL: entry.url,
                                   contextMenu: { cellMenu(for: entry) }) { open(entry) }
                }
                // 原生同款尾格：在访达中打开当前目录。
                FolderGridCell(iconPath: nil, staticIcon: Self.finderIcon, label: "在访达中打开") {
                    NSWorkspace.shared.open(currentURL)
                    onFileOpened()
                }
            }
            .animation(animatesGridChanges ? .easeInOut(duration: DrawerAnimation.duration) : nil,
                       value: model.entries.map(\.url))
        }
        // 下钻时顶部多留出返回浮标的高度,浮标不压第一行格子。
        .padding(.top, drillStack.isEmpty ? Style.contentPadding : Style.contentPadding + Style.backChipSize + 4)
        .padding([.horizontal, .bottom], Style.contentPadding)
        .frame(width: contentWidth)
        .background(GeometryReader { g in
            Color.clear.preference(key: FolderGridHeightKey.self, value: g.size.height)
        })
        .onPreferenceChange(FolderGridHeightKey.self) { gridHeight = $0 }
    }

    private func open(_ entry: FolderContentsLoader.Entry) {
        if entry.isDirectory {
            drillStack.append(entry.url)
        } else {
            NSWorkspace.shared.open(entry.url)
            onFileOpened()
        }
    }

    /// 条目右键菜单（手搓 NSMenu,AGENTS 护栏）。目录且未固定才给「固定到固定区」。
    private func cellMenu(for entry: FolderContentsLoader.Entry) -> NSMenu {
        let canPin = entry.isDirectory && !(isFolderPinned?(entry.url) ?? true)
        return FileItemMenuBuilder.menu(for: .init(
            url: entry.url,
            isDirectory: entry.isDirectory,
            closePopup: onFileOpened,
            pinFolder: canPin ? { onPinFolder?(entry.url) } : nil
        ))
    }

    private static let finderIcon: NSImage = {
        FolderGridCell.icon(forPath: "/System/Library/CoreServices/Finder.app")
    }()
}

/// 弹窗网格的共享尺寸常量（文件夹弹窗 + 中转弹窗共用,别在两边各写一份漂移）。
/// 列数派生口径：columnCount = clamp(总格数, minColumns, maxColumns),宽度由列数**推导**,
/// 绝不回退成测量值（fittingSize 反馈环）;maxColumns=8 是 owner「再宽一些」的拍板,勿改回 6。
enum FolderPopupStyle {
    static let iconSize: CGFloat = 64          // 原生 Stacks 同款大图标
    static let cellWidth: CGFloat = 96
    static let cellHeight: CGFloat = 104
    static let cellSpacing: CGFloat = 10
    static let contentPadding: CGFloat = 16
    static let minColumns = 3
    static let maxColumns = 8                  // 满列内容宽 ≈ 870pt（owner:再宽一些）
    /// 网格显示高度上限（约 4 行出头,超出内部滚动;owner:矮一些）。
    static let maxGridHeight: CGFloat = 470
    static let labelSize: CGFloat = 11
    static let backChipSize: CGFloat = 26
}

/// 单个格子：64pt 图标 + 两行小字名，悬停浮白底。独立 struct 才能各自持有 hover 态。
/// 条目格与「在访达中打开」尾格共用（尾格无拖拽/无菜单）。中转弹窗（阶段 B）复用,故 internal。
/// `dragURL` 非 nil → 挂系统文件拖拽 `.onDrag`（真文件拖出到别的 app;系统拖影=原生效果,
/// AGENTS「No System Drag Image」护栏限任务条/抽屉 chip 拖拽,文件拖出在豁免范围）。
struct FolderGridCell: View {
    let iconPath: String?
    let staticIcon: NSImage?
    let label: String
    var dragURL: URL? = nil
    var contextMenu: (() -> NSMenu)? = nil
    let onTap: () -> Void

    @State private var isHovering = false
    @State private var resolvedIcon: NSImage?

    var body: some View {
        if let dragURL {
            core.onDrag { NSItemProvider(contentsOf: dragURL) ?? NSItemProvider() }
        } else {
            core
        }
    }

    private var core: some View {
        VStack(spacing: 5) {
            Image(nsImage: currentIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
                .opacity(resolvedIcon == nil && staticIcon == nil ? 0 : 1)
                .task(id: iconPath) {
                    guard let path = iconPath, resolvedIcon == nil else { return }
                    let img = await Task.detached(priority: .userInitiated) {
                        FolderGridCell.icon(forPath: path)
                    }.value
                    withAnimation(.easeIn(duration: 0.15)) {
                        resolvedIcon = img
                    }
                }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .frame(width: 96, height: 104)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { onTap() }
        .nativeContextMenu { contextMenu?() ?? NSMenu() }
        .help(label)
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }

    private var currentIcon: NSImage {
        if let s = staticIcon { return s }
        if let r = resolvedIcon { return r }
        return Self.placeholderIcon
    }

    private static let placeholderIcon = NSImage(size: NSSize(width: 64, height: 64))

    /// 共享缓存对象必须 copy 再改 size（AppMenuFragments 惯例）。LazyVGrid 只实例化可见格,同步取图标够快。
    static func icon(forPath path: String, size: CGFloat = 64) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: path)
        guard let copy = icon.copy() as? NSImage else { return icon }
        copy.size = NSSize(width: size, height: size)
        return copy
    }
}

private struct FolderGridHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
