import AppKit
import SwiftUI

enum WindowTitleTextMetrics {
    /// 条内标题的最大宽度（中档基线）。**渲染和截断判定必须共用同一个值**——
    /// 以前 `ChipView` 那边写死 140、这边也写死 140，两处随缩放各走各的就会出现
    /// 「视觉上截断了但不弹 tooltip」（或反之）。任务条缩放后一律走 `maximumWidth(for:)`。
    static let maximumWidth: CGFloat = 140
    static let truncationTolerance: CGFloat = 2

    static func maximumWidth(for scale: CGFloat) -> CGFloat { maximumWidth * scale }

    static func font(scale: CGFloat) -> NSFont {
        let size = max(10, 12 * scale)
        let base = NSFont.systemFont(ofSize: size, weight: .medium)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size) else {
            return base
        }
        return rounded
    }

    static func intrinsicWidth(of title: String, scale: CGFloat) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: font(scale: scale)]).width
    }

    static func isTruncated(
        intrinsicWidth: CGFloat,
        maximumWidth: CGFloat = maximumWidth,
        tolerance: CGFloat = truncationTolerance
    ) -> Bool {
        ceil(intrinsicWidth) > maximumWidth + tolerance
    }

    static func needsTooltip(for title: String, scale: CGFloat) -> Bool {
        guard !title.isEmpty else { return false }
        return isTruncated(
            intrinsicWidth: intrinsicWidth(of: title, scale: scale),
            maximumWidth: maximumWidth(for: scale)
        )
    }
}

struct WindowTitleTooltipRequest: Equatable {
    let chipID: String
    let title: String
    let anchorVisibleRect: CGRect
}

enum WindowTitleTooltipEvent: Equatable {
    case update(WindowTitleTooltipRequest)
    case exit(chipID: String)
}

struct WindowTitleTooltipView: View {
    let title: String

    /// 浅 / 深色两套视觉数值（见 `DockThemeTokens`）。
    @Environment(\.colorScheme) private var colorScheme
    private var theme: DockThemeTokens { .resolve(colorScheme) }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(theme.tooltipText.color)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 360, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.ultraThinMaterial)
                    // 材质本身跟随系统外观，这层是再压一道染色：深色加黑压暗，浅色反过来加白提亮。
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(theme.tooltipTint.color)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(theme.tooltipRim.color, lineWidth: 0.5)
            )
            .dockShadow(theme.tooltipShadow)
            .padding(PanelGeometry.windowTitleTooltipShadowPadding)
    }
}
