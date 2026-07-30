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
        }
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

    /// 标题胶囊的描边：同样是上亮下暗。
    /// - Parameter emphasized: 悬停中。
    func chipPillRimStyle(emphasized: Bool) -> LinearGradient {
        LinearGradient(colors: [chipPillRimTop.color(emphasized: emphasized), chipPillRimBottom.color],
                       startPoint: .top,
                       endPoint: .bottom)
    }
}

extension View {
    /// 应用一个 `DockShadow`（x 恒为 0）。
    func dockShadow(_ shadow: DockShadow) -> some View {
        self.shadow(color: shadow.tint.color, radius: shadow.radius, x: 0, y: shadow.y)
    }

    /// 条件式光晕：`active` 为假时半径与不透明度都归零（等价于不画）。
    func dockGlow(_ tint: DockTint, radius: CGFloat, active: Bool) -> some View {
        self.shadow(color: tint.color(active: active), radius: active ? radius : 0)
    }
}
