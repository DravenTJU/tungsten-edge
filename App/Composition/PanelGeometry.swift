import CoreGraphics

struct PanelLayoutMetrics: Equatable {
    var panelHeight: CGFloat
    var shadowPadding: CGFloat
    var windowHeight: CGFloat
    var bottomGap: CGFloat
    var outerMargin: CGFloat
    var capsuleWidth: CGFloat
    var capsuleGap: CGFloat
    var minimumDockWidth: CGFloat
    var minimumDrawerExtent: CGFloat

    static let tungstenEdge = PanelLayoutMetrics(
        panelHeight: 52,
        shadowPadding: 20,
        windowHeight: 92,
        bottomGap: 8,
        outerMargin: 12,
        capsuleWidth: 52,
        capsuleGap: 8,
        minimumDockWidth: 120,
        minimumDrawerExtent: 120
    )
}

struct PanelScreenGeometry: Equatable {
    var frame: CGRect
    var visibleFrame: CGRect
    var safeAreaTop: CGFloat

    /// The drawer's top cap still follows top system UI. On displays without a notch,
    /// this usually tracks visibleFrame.maxY and may change when the menu bar auto-hides.
    /// On notched displays, the safe-area cap can take over once the menu bar is hidden,
    /// so the same known edge can be smaller there than on external displays.
    var topUsableY: CGFloat {
        min(visibleFrame.maxY, frame.maxY - safeAreaTop)
    }
}

enum PanelGeometry {
    /// `satelliteColumns` = 任务条右侧悬浮小面板的列数（胶囊恒为 1；垃圾桶显示时传 2）。
    /// dock 居中，所以预留必须对称；默认 1 与历史公式完全等价。
    static func dockTargetFrame(
        contentWidth: CGFloat,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge,
        satelliteColumns: Int = 1
    ) -> CGRect {
        let reserved = metrics.outerMargin + CGFloat(satelliteColumns) * (metrics.capsuleGap + metrics.capsuleWidth)
        let maxWidth = screen.frame.width - 2 * reserved
        let panelWidth = max(min(contentWidth, maxWidth), metrics.minimumDockWidth)
        let x = screen.frame.minX + (screen.frame.width - panelWidth) / 2
        return CGRect(
            x: x - metrics.shadowPadding,
            y: screen.frame.minY + metrics.bottomGap - metrics.shadowPadding,
            width: panelWidth + metrics.shadowPadding * 2,
            height: metrics.windowHeight
        )
    }

    static func capsuleTargetFrame(
        forDock dockFrame: CGRect,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let rawX = dockFrame.maxX - metrics.shadowPadding + metrics.capsuleGap
        let rawY = dockFrame.minY + metrics.shadowPadding + (metrics.panelHeight - metrics.capsuleWidth) / 2
        let clampedX = min(max(rawX, screen.frame.minX), screen.frame.maxX - metrics.capsuleWidth)
        let clampedY = min(max(rawY, screen.frame.minY), screen.frame.maxY - metrics.capsuleWidth)
        return CGRect(
            x: clampedX - metrics.shadowPadding,
            y: clampedY - metrics.shadowPadding,
            width: metrics.capsuleWidth + metrics.shadowPadding * 2,
            height: metrics.capsuleWidth + metrics.shadowPadding * 2
        )
    }

    /// 垃圾桶卫星面板：胶囊可视右缘再向右 capsuleGap，同一垂直带、同尺寸。
    /// 顺序固定为 [dock][胶囊][垃圾桶]，垃圾桶最外侧。
    static func trashTargetFrame(
        forCapsule capsuleFrame: CGRect,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let rawX = capsuleFrame.maxX - metrics.shadowPadding + metrics.capsuleGap
        let clampedX = min(max(rawX, screen.frame.minX), screen.frame.maxX - metrics.capsuleWidth)
        return CGRect(
            x: clampedX - metrics.shadowPadding,
            y: capsuleFrame.minY,
            width: metrics.capsuleWidth + metrics.shadowPadding * 2,
            height: metrics.capsuleWidth + metrics.shadowPadding * 2
        )
    }

    /// 文件夹/废纸篓弹窗：锚点（chip 可视矩形，屏幕坐标）上方 8pt，水平居中钳进屏，
    /// 只向上生长、topUsableY 封顶——同 drawer 的底锚策略。`size` 为含阴影的整面板尺寸。
    static func folderPopupTargetFrame(
        anchorVisibleRect: CGRect,
        size: CGSize,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let bottom = max(anchorVisibleRect.maxY + 8, screen.frame.minY)
        let height = min(size.height, max(metrics.minimumDrawerExtent, screen.topUsableY - bottom))
        let rawX = anchorVisibleRect.midX - size.width / 2
        let clampedX = min(max(rawX, screen.frame.minX), screen.frame.maxX - size.width)
        return CGRect(x: clampedX, y: bottom, width: size.width, height: height)
    }

    static func maxFolderPopupContentHeight(
        anchorVisibleRect: CGRect,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGFloat {
        let bottom = anchorVisibleRect.maxY + 8
        return max(metrics.minimumDrawerExtent, (screen.topUsableY - bottom) - 2 * metrics.shadowPadding)
    }

    static func drawerTargetFrame(
        forCapsule capsuleFrame: CGRect,
        size: CGSize,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let bottom = max(capsuleFrame.maxY - metrics.shadowPadding + 8, screen.frame.minY)
        let height = min(size.height, max(metrics.minimumDrawerExtent, screen.topUsableY - bottom))
        let rawX = capsuleFrame.maxX - size.width
        let clampedX = min(max(rawX, screen.frame.minX), screen.frame.maxX - size.width)
        return CGRect(x: clampedX, y: bottom, width: size.width, height: height)
    }

    static func maxDrawerContentHeight(
        forCapsule capsuleFrame: CGRect,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGFloat {
        let drawerBottomY = capsuleFrame.maxY - metrics.shadowPadding + 8
        return max(metrics.minimumDrawerExtent, (screen.topUsableY - drawerBottomY) - 2 * metrics.shadowPadding)
    }
}
