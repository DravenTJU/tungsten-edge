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
    static let windowTitleTooltipGap: CGFloat = 8
    static let windowTitleTooltipScreenMargin: CGFloat = 8
    static let windowTitleTooltipShadowPadding: CGFloat = 8

    static func dockTargetFrame(
        contentWidth: CGFloat,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let maxWidth = screen.frame.width - 2 * (metrics.outerMargin + metrics.capsuleGap + metrics.capsuleWidth)
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

    /// 弹窗锚定+钳位的**单一真相**：给定"期望中心 X / 期望底边 Y / 尺寸"，算出贴屏钳位后的 origin。
    /// folderPopupTargetFrame（首帧/重定位）和切换动画的每帧插值都走它，避免钳位规则在两处各写一份漂移。
    static func folderPopupClampedOrigin(
        desiredCenterX: CGFloat,
        desiredBottomY: CGFloat,
        size: CGSize,
        on screen: PanelScreenGeometry
    ) -> CGPoint {
        let bottom = max(desiredBottomY, screen.frame.minY)
        let x = min(max(desiredCenterX - size.width / 2, screen.frame.minX), screen.frame.maxX - size.width)
        return CGPoint(x: x, y: bottom)
    }

    /// 固定文件夹弹窗：锚点（chip 可视矩形，屏幕坐标）上方 8pt，水平居中钳进屏，
    /// 只向上生长、topUsableY 封顶——同 drawer 的底锚策略。`size` 为含阴影的整面板尺寸。
    static func folderPopupTargetFrame(
        anchorVisibleRect: CGRect,
        size: CGSize,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGRect {
        let origin = folderPopupClampedOrigin(
            desiredCenterX: anchorVisibleRect.midX, desiredBottomY: anchorVisibleRect.maxY + 8,
            size: size, on: screen)
        let height = min(size.height, max(metrics.minimumDrawerExtent, screen.topUsableY - origin.y))
        return CGRect(x: origin.x, y: origin.y, width: size.width, height: height)
    }

    static func maxFolderPopupContentHeight(
        anchorVisibleRect: CGRect,
        on screen: PanelScreenGeometry,
        metrics: PanelLayoutMetrics = .tungstenEdge
    ) -> CGFloat {
        let bottom = anchorVisibleRect.maxY + 8
        return max(metrics.minimumDrawerExtent, (screen.topUsableY - bottom) - 2 * metrics.shadowPadding)
    }

    /// Window-title tooltip panel frame. The panel includes transparent padding for its SwiftUI
    /// shadow, while the visible bubble stays 8pt above the pill and 8pt inside the screen edges.
    static func windowTitleTooltipTargetFrame(
        anchorVisibleRect: CGRect,
        size: CGSize,
        on screen: PanelScreenGeometry
    ) -> CGRect {
        let inset = windowTitleTooltipShadowPadding
        let visibleWidth = max(0, size.width - 2 * inset)
        let visibleHeight = max(0, size.height - 2 * inset)
        let minVisibleX = screen.frame.minX + windowTitleTooltipScreenMargin
        let maxVisibleX = screen.frame.maxX - windowTitleTooltipScreenMargin - visibleWidth
        let desiredVisibleX = anchorVisibleRect.midX - visibleWidth / 2
        let visibleX = min(max(desiredVisibleX, minVisibleX), maxVisibleX)
        let desiredVisibleY = anchorVisibleRect.maxY + windowTitleTooltipGap
        let maxVisibleY = screen.topUsableY - visibleHeight
        let visibleY = min(desiredVisibleY, maxVisibleY)

        return CGRect(
            x: visibleX - inset,
            y: visibleY - inset,
            width: size.width,
            height: size.height
        )
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
