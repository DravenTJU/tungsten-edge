import AppKit
import CoreGraphics
import Foundation

/// 一块显示器上的那套任务条面板（每屏常驻任务条，2026-07-27）。
///
/// 只装**面板 + 目标矩形 + 宽度状态**，刻意**不装任何定时器**：全屏对账、边缘隐藏、
/// 弹簧、弹窗补间那七个定时器全部留在 `PanelCoordinator` 顶层。每屏一个定时器是
/// 「N 块屏 = N 个互相竞争的状态机」这类 bug 的最大来源，而它们没一个真的需要按屏。
///
/// 抽屉、文件夹/暂存架弹窗、拖拽载体也都不在这里——它们是**全桌面单例**（owner 2026-07-27）。
///
/// `planLayout` 只**返回**目标矩形而不自己提交：`PanelCoordinator` 把所有屏的面板加上抽屉
/// 放进同一个 `NSAnimationContext` 组里一次提交，守住「布局由目标矩形驱动、不在动画期间
/// 用另一个面板的实时 frame 定位」这条硬约束（屏幕多了之后它更重要，不是更不重要）。
@MainActor
final class ScreenBar {
    struct LayoutPlan {
        let dock: NSRect
        let capsule: NSRect
        /// 任务条目标帧相对上一次是否变了。弹窗宿主屏据此决定要不要关弹窗。
        let dockChanged: Bool
        /// 首帧强制瞬时（面板刚建好，别从初始位置滑过来）。
        let mustBeInstant: Bool
    }

    let id: ScreenID
    private(set) var screen: NSScreen
    let dockPanel: NSPanel
    let capsulePanel: NSPanel
    /// 任务条的 SwiftUI 承载器。窗口 frame 归 PanelCoordinator，内容尺寸只从这里读
    /// （上游 v0.7.6 起内容视图不再直接当 contentView，见 `ManualPanelHost`）。
    let dockContentHost: ManualPanelHost
    /// 胶囊承载器。宽高固定、当前没人读它的 fittingSize，但仍**强持有**：
    /// 丢弃后只靠视图层级间接留住容器，`ManualPanelHost` 一旦加 deinit 清理，胶囊会静默失效。
    let capsuleContentHost: ManualPanelHost

    /// 目标 frame 驱动布局：drop zone 命中、开抽屉定位都读**目标**而非 live frame——
    /// 动画中 live frame 是中途值，会和视觉/逻辑短暂不一致（Codex 二审 P2）。
    private(set) var lastDockTargetFrame: NSRect = .zero
    private(set) var lastCapsuleTargetFrame: NSRect = .zero
    private(set) var lastDesiredWidth: CGFloat = 0
    /// 跨面板转正进行中钳住的任务条内容宽度（拖动前的值）。非 nil → 布局用它而非实测宽度，
    /// 让窗口卡溢出/留空而不改变面板宽度（owner 2026-06-22）。
    var frozenContentWidth: CGFloat?
    /// 这块屏上有应用处于全屏（每屏独立，owner 2026-07-27）。
    var isFullscreenHidden = false

    private var didInitialLayout = false
    /// 初值必须是 **false**：面板刚建好时还没 orderFront，若初值为 true，
    /// `setOrderedIn(true)` 会被自身的去重 guard 吃掉，这条 bar 就永远不显示
    /// （副屏任务条不出现的根因，2026-08-10）。
    private var isOrderedIn = false

    init(id: ScreenID, screen: NSScreen,
         dockPanel: NSPanel, dockContentHost: ManualPanelHost,
         capsulePanel: NSPanel, capsuleContentHost: ManualPanelHost) {
        self.id = id
        self.screen = screen
        self.dockPanel = dockPanel
        self.dockContentHost = dockContentHost
        self.capsulePanel = capsulePanel
        self.capsuleContentHost = capsuleContentHost
    }

    // MARK: - 几何

    /// 首次布局前让 SwiftUI 完成一轮排版，`fittingSize` 才是真值。
    func prepareForInitialLayout() {
        dockPanel.layoutIfNeeded()
        capsulePanel.layoutIfNeeded()
    }

    var geometry: PanelScreenGeometry {
        PanelScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame,
                            safeAreaTop: screen.safeAreaInsets.top)
    }

    /// 这块屏的 Quartz 矩形（与 AX / CG 窗口 bounds 同一坐标空间）。
    var quartzFrame: CGRect {
        ScreenAttribution.quartzRect(fromAppKit: screen.frame, primaryMaxY: ScreenGeometrySource.primaryMaxY)
    }

    /// 分辨率 / 排列变化后换上同一块屏的新 `NSScreen` 实例。
    func adopt(screen: NSScreen) {
        self.screen = screen
    }

    // MARK: - 布局

    /// 量当前内容宽度（SwiftUI fittingSize 去掉两侧阴影留白）。
    func measureContentWidth(shadowPadding: CGFloat) -> CGFloat {
        let measured = dockContentHost.fittingSize.width - 2 * shadowPadding
        lastDesiredWidth = measured
        return measured
    }

    /// 算出这块屏的目标矩形并记账；**不提交**，由调用方统一进动画组。
    func planLayout(contentWidth: CGFloat, metrics: PanelLayoutMetrics) -> LayoutPlan {
        let geo = geometry
        let dockT = PanelGeometry.dockTargetFrame(contentWidth: contentWidth, on: geo, metrics: metrics)
        let capsuleT = PanelGeometry.capsuleTargetFrame(forDock: dockT, on: geo, metrics: metrics)
        let changed = dockT != lastDockTargetFrame
        let instant = !didInitialLayout
        didInitialLayout = true
        lastDockTargetFrame = dockT
        lastCapsuleTargetFrame = capsuleT
        return LayoutPlan(dock: dockT, capsule: capsuleT, dockChanged: changed, mustBeInstant: instant)
    }

    // MARK: - 显隐与拆除

    /// 首帧显示与热插拔新增显示器都走这里；别再给面板各自散落 `orderFrontRegardless()`。
    func setOrderedIn(_ on: Bool) {
        guard on != isOrderedIn else { return }
        isOrderedIn = on
        if on {
            dockPanel.orderFrontRegardless()
            capsulePanel.orderFrontRegardless()
        } else {
            dockPanel.orderOut(nil)
            capsulePanel.orderOut(nil)
        }
    }

    /// 拆掉这块屏的面板。内容视图归 `ManualPanelHost` 管，这里只 orderOut 并松开面板；
    /// 不要置空 `contentView`——host 仍强持有内容视图，置空会让两边状态不一致。
    func teardown() {
        dockPanel.orderOut(nil)
        capsulePanel.orderOut(nil)
    }
}
