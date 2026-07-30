import AppKit
import SwiftUI

// MARK: - DockThemeTokens 的 SwiftUI / AppKit 桥接
//
// 纯数值表在 `Core/Support/DockThemeTokens.swift`（不 import SwiftUI，因此可被单测精确冻结）。
// 这里只做「数值 → Color / Material / 修饰符」的翻译，不含任何取值判断。
//
// 用法：需要上色的视图加
//     @Environment(\.colorScheme) private var colorScheme
//     private var theme: DockThemeTokens { .resolve(colorScheme) }
// 然后读 `theme.xxx.color`。
//
// 为什么不建 EnvironmentKey 注入：`colorScheme` 本身就是环境值，逐个 struct 自己读最省事，
// 也不用在 5 个宿主面板各写一遍注入。

extension DockThemeTokens {
    /// 唯一的取值入口。`colorScheme` 由各面板的 `NSHostingView` 从窗口 `effectiveAppearance`
    /// 继承（所有面板都没有覆写 `appearance`，所以就是系统当前外观），系统切换外观时自动重算。
    static func resolve(_ colorScheme: ColorScheme) -> DockThemeTokens {
        colorScheme == .dark ? .dark : .light
    }
}

extension DockTint {
    var color: Color {
        switch base {
        case .white: return Color.white.opacity(opacity)
        case .black: return Color.black.opacity(opacity)
        }
    }

    /// 同基色的全透明版本。
    /// **不要用 `Color.clear` 代替**：动画是在两个颜色之间插值，从 `.clear` 淡向一个白色描边
    /// 会在中途透出灰边；改造前的写法本来就是 `opacity(isActive ? 0.9 : 0)`。
    var transparent: Color { DockTint(base: base, opacity: 0).color }

    /// 按状态开关同一处着色（关 = 同基色全透明）。
    func color(active: Bool) -> Color { active ? color : transparent }
}

extension DockTintPair {
    /// - Parameter emphasized: 悬停中，或投放命中。
    func color(emphasized: Bool) -> Color {
        (emphasized ? self.emphasized : normal).color
    }
}

extension DockPanelMaterial {
    var nsMaterial: NSVisualEffectView.Material {
        switch self {
        case .popover: return .popover
        case .hudWindow: return .hudWindow
        case .menu: return .menu
        case .underWindowBackground: return .underWindowBackground
        case .sidebar: return .sidebar
        case .titlebar: return .titlebar
        case .selection: return .selection
        case .headerView: return .headerView
        case .fullScreenUI: return .fullScreenUI
        case .toolTip: return .toolTip
        case .sheet: return .sheet
        case .windowBackground: return .windowBackground
        case .contentBackground: return .contentBackground
        case .underPageBackground: return .underPageBackground
        }
    }
}

extension DockThemeTokens {
    /// 实际生效的材质：`DOCK_PANEL_MATERIAL` 覆盖 token 值（调参用，认不出的名字回落，不崩）。
    /// 读一次就固定——调参期间改环境变量重启一次即可，也避免一次会话里前后不一致。
    var effectivePanelMaterial: DockPanelMaterial {
        DockPanelMaterial.resolved(from: DockMaterialOverride.environment, fallback: panelMaterial)
    }
}

enum DockMaterialOverride {
    static let environment = ProcessInfo.processInfo.environment

    /// 调参诊断：只有真的设了环境变量才打一行。打的是**解析后**的值，所以名字打错
    /// （回落到 token 值）当场就看得出来，不会拿着一张其实没换材质的对照表瞎比。
    static func logIfOverridden(resolved: DockPanelMaterial) {
        guard let raw = environment["DOCK_PANEL_MATERIAL"] else { return }
        print("[material] DOCK_PANEL_MATERIAL=\"\(raw)\" → 实际生效 \(resolved)")
    }
}

extension DockThemeTokens {
    /// 面板描边：上沿亮、下沿暗，模拟来自上方的光（苹果原生玻璃的打光方向）。
    /// 深色两端同值 → 渐变退化成均匀色，与改造前的 `.strokeBorder(.white.opacity(0.15))` 逐像素一致。
    var panelRimStyle: LinearGradient {
        LinearGradient(colors: [panelRimTop.color, panelRimBottom.color],
                       startPoint: .top,
                       endPoint: .bottom)
    }

    /// 投放命中时换成实色整框；否则用上下渐变。
    func panelRimStyle(highlighted: Bool) -> AnyShapeStyle {
        highlighted ? AnyShapeStyle(panelRimHighlighted.color) : AnyShapeStyle(panelRimStyle)
    }

    func panelRimLineWidth(highlighted: Bool) -> CGFloat {
        highlighted ? panelRimHighlightedLineWidth : panelRimLineWidth
    }

    /// 玻璃厚度层：上内沿一条亮线（光从上方进入介质）+ 下内沿一道暗收（介质底部自阴影）。
    /// 画在材质**之上**、内容**之下**，是我们自己的像素——所以不受「拿不到窗口背后像素」
    /// 那条限制（折射与背景饱和度就是卡在那里）。
    ///
    /// 调用方必须先判 `drawsPanelThickness`：深色时整层不进视图树，见该属性的注释。
    @ViewBuilder
    func panelThicknessLayer(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            shape
                .strokeBorder(
                    LinearGradient(colors: [panelInnerHighlight.color, panelInnerHighlight.transparent],
                                   startPoint: .top, endPoint: .center),
                    lineWidth: panelInnerHighlightWidth
                )
                .blur(radius: panelInnerHighlightBlur)
            shape
                .strokeBorder(
                    LinearGradient(colors: [panelInnerShadow.transparent, panelInnerShadow.color],
                                   startPoint: .center, endPoint: .bottom),
                    lineWidth: panelInnerShadowWidth
                )
                .blur(radius: panelInnerShadowBlur)
        }
        // 模糊会溢出形状，必须裁回来，否则厚度层会糊到面板外面去。
        .clipShape(shape)
        // 纯装饰层，绝不能抢 chip 的点击（面板是 nonactivatingPanel，chip 全靠 onTapGesture）。
        .allowsHitTesting(false)
    }

    /// 标题胶囊的描边：同样是上亮下暗。
    /// - Parameter emphasized: 悬停中。
    func chipPillRimStyle(emphasized: Bool) -> LinearGradient {
        LinearGradient(colors: [chipPillRimTop.color(emphasized: emphasized), chipPillRimBottom.color],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

extension View {
    /// 给毛玻璃底板加背景提饱和。**1.0 时整个修饰符都不挂**——`.saturation(1.0)` 虽是恒等，
    /// 但仍可能触发离屏渲染，多一层就可能破坏深色的逐像素冻结（同厚度层的理由）。
    @ViewBuilder
    func dockBackdropSaturation(_ amount: Double) -> some View {
        if amount == 1.0 { self } else { self.saturation(amount) }
    }

    /// 应用一个 `DockShadow`（x 恒为 0）。
    func dockShadow(_ shadow: DockShadow) -> some View {
        self.shadow(color: shadow.tint.color, radius: shadow.radius, x: 0, y: shadow.y)
    }

    /// 条件式光晕：`active` 为假时半径与不透明度都归零（等价于不画）。
    func dockGlow(_ tint: DockTint, radius: CGFloat, active: Bool) -> some View {
        self.shadow(color: tint.color(active: active), radius: active ? radius : 0)
    }
}
