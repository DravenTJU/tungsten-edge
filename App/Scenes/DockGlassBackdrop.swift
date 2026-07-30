import AppKit
import SwiftUI

// MARK: - 原生 Liquid Glass 底板（探路用，默认关）
//
// 为什么存在：owner 2026-07-30 反馈「浅色适配后整体好很多，但还是没有像原生的有玻璃折射的效果」。
// 我们自己**做不出**折射——`.behindWindow` 混合发生在系统进程里，我们的进程拿不到背后的像素，
// 所以位移贴图那条路是死的。但苹果自己的 API 在合成器里，不受这个限制：
//
//   AppKit   NSGlassEffectView / NSGlassEffectContainerView   macOS 26.0+
//   SwiftUI  View.glassEffect(_:in:) / GlassEffectContainer    macOS 26.0+
//
// **本文件目前是探路装置，不是已验收的功能。** 它要回答一个问题：玻璃在我们这种
// `.borderless + .nonactivatingPanel + level=.floating + isOpaque=false + hasShadow=false`
// 的面板上，会不会折射**窗口背后**的桌面内容。`NSVisualEffectView` 需要显式
// `blendingMode = .behindWindow` 才有那个能力，而玻璃 API 没有这个开关；系统的菜单和 popover
// 在 26 上都是独立窗口且确实透出背后内容，所以大概率可以，但我们这套组合非常规，只能实测。
//
// 判据：**模糊不会让一条直线弯，折射会。** 把高对比硬边摆到穿过任务条圆角的位置，
// 开关开/关各截一张，量这条边在条内条外的位移。
//
// 设计约束（owner 拍定）：
// - 默认关，`DOCK_LIQUID_GLASS=1` 才开 —— 所以提交进去不改变任何既有行为。
// - macOS 26+ 才有玻璃；12–25 走 `else` 分支，也就是原样的 `DockVisualEffectView`。
//   **接受两套观感**，不抬最低系统版本。
// - 玻璃**不进** `DockThemeTokens`：给那张冻结的数值表加 `@available(macOS 26)` 的关联类型
//   会污染它、还会牵动 `DockThemeTests` 的深色冻结。玻璃是"底板换一种画法"，与 token 表正交。

/// 任务条底板：按环境开关 + 系统版本在「原生玻璃」和「毛玻璃材质」之间二选一。
///
/// 探路阶段**只有任务条自己**用它；抽屉胶囊、抽屉、两个弹窗仍直接用 `DockVisualEffectView`。
struct DockGlassBackdrop: View {
    /// 回退路径用的材质（`DockThemeTokens.panelMaterial`）。玻璃不可用时就是它。
    let material: DockPanelMaterial
    var cornerRadius: CGFloat = DockShape.panelCornerRadius

    var body: some View {
        resolved
            // 诊断挂在 onAppear 而不是 body 里，免得每次求值都打一行。
            .onAppear {
                DockGlassSwitch.logResolvedPath()
                DockMaterialOverride.logIfOverridden(resolved: material)
            }
    }

    @ViewBuilder
    private var resolved: some View {
        if #available(macOS 26.0, *), DockGlassSwitch.isEnabled {
            // `Color.clear` 只是给玻璃一个铺满的形状；玻璃自己负责采样与折射。
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            DockVisualEffectView(material: material)
        }
    }
}

/// 探路开关。读一次就固定（跟 `DOCK_EDGEHOVER_TRACE` 同款写法）——探路期间不需要热切换，
/// 每次改开关重启一次应用即可，这样也避免开关值在一次会话里前后不一致。
enum DockGlassSwitch {
    static let isEnabled: Bool =
        ProcessInfo.processInfo.environment["DOCK_LIQUID_GLASS"] == "1"

    /// 探路诊断：启动时打一行，说明这次跑的到底是哪条路径。
    /// 用 `print` 而不是 `Logger`——有些环境读不回统一日志（同 `[edgehover]` 的理由）。
    static func logResolvedPath() {
        guard isEnabled else { return }
        if #available(macOS 26.0, *) {
            print("[glass] DOCK_LIQUID_GLASS=1 且系统 ≥ 26 → 任务条底板走原生 Liquid Glass")
        } else {
            print("[glass] DOCK_LIQUID_GLASS=1 但系统 < 26 → 仍走 NSVisualEffectView")
        }
    }
}

// MARK: - AppKit 备用路径
//
// 如果 SwiftUI 的 `.glassEffect` 在这种面板里渲染成扁平/空白，就换这个：`NSGlassEffectView`
// 有显式的 `cornerRadius` 和 `tintColor`，作为一块纯底板可能更听话。
// 探路时**只换 `DockGlassBackdrop` 里那一行**，别两条一起上。

@available(macOS 26.0, *)
struct DockNativeGlassView: NSViewRepresentable {
    var cornerRadius: CGFloat = DockShape.panelCornerRadius

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .regular
        view.cornerRadius = cornerRadius
        return view
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        if nsView.cornerRadius != cornerRadius { nsView.cornerRadius = cornerRadius }
    }
}
