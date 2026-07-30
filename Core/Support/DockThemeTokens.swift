import Foundation

// MARK: - 浅 / 深色视觉数值表（纯数据层）
//
// 为什么存在：整套视觉原本是照着**深色模式**手调出来的，全仓库零处按外观分支——所有前景色写死成
// 白、所有阴影写死成黑。浅色模式下 `NSVisualEffectView` 会自己变浅（材质跟随系统），但上面的白字、
// 白描边、白圆点全部失效，黑阴影则变成一圈灰污渍。真实用户报告见 GitHub issue #3 第 3 条：
// 「周围有很明显的方格，然后旁边有阴影，并且还会延伸溢出，整体样式质感不行」——他用的是浅色模式，
// 抱怨的每一点都能对应到下面某个 token 在浅色下的失效。
//
// **本文件不 import SwiftUI**：只存基色 + 不透明度 + 阴影几何，全部是可精确比较的值类型，
// 因此 `DockThemeTests` 能逐项冻结深色列。`Color` / `NSVisualEffectView.Material` 的桥接在
// `App/Scenes/DockTheme.swift`。
//
// ⚠️ **深色列是冻结的**：它逐项等于 2026-07-30 改造前散落在各视图里的字面值，`DockThemeTests`
// 机械保证任何漂移直接红。要调观感只动 `light`——动 `dark` 等于改 owner 天天在用的界面。
//
// ⚠️ 两个「看着像颜色其实不是」的坑，不属于本表、也绝不能按外观改：
//   · `DockStripView` 滚动边缘淡出的 `.black` / `.clear` 是 **mask 的 alpha 通道**，不是颜色。
//   · `PanelCoordinator` 里的 `NSColor(white: 1.0, alpha: 0.0)` 是**全透明**，不是「白色底」。

/// 基色。整套视觉只用纯白 / 纯黑加不透明度叠在毛玻璃上，没有第三种基色
///（唯一的彩色是角标红，它两种模式都成立，不进本表）。
enum DockTintBase: Equatable {
    case white
    case black
}

/// 一个「基色 + 不透明度」的着色值。
struct DockTint: Equatable {
    let base: DockTintBase
    let opacity: Double

    static func white(_ opacity: Double) -> DockTint { .init(base: .white, opacity: opacity) }
    static func black(_ opacity: Double) -> DockTint { .init(base: .black, opacity: opacity) }
}

/// 同一处视觉的常态 / 强调态两个值（强调 = 悬停，或投放命中）。
struct DockTintPair: Equatable {
    let normal: DockTint
    let emphasized: DockTint
}

/// 阴影：颜色 + 模糊半径 + 向下偏移（x 恒为 0，整套视觉没有横向偏移的阴影）。
struct DockShadow: Equatable {
    let tint: DockTint
    let radius: CGFloat
    let y: CGFloat

    /// 阴影向下延伸的总量。**必须 ≤ `PanelCoordinator.shadowPadding`（20pt）**，否则在面板的
    /// 透明边处被硬切成一道齐口直边——这正是用户说的「阴影还会延伸溢出」。
    /// 深色任务条现值 15 + 8 = 23 就超了 3pt；深色冻结，本轮不动它（已单独记待办）。
    /// 浅色列全部收进预算内。
    var verticalExtent: CGFloat { radius + abs(y) }
}

/// 毛玻璃材质。用自己的枚举而不是 `NSVisualEffectView.Material`，是为了让本文件保持不依赖 AppKit
///（映射在 `DockTheme.swift`）。浅色下若觉得底板太白，这里是换材质的出口。
enum DockPanelMaterial: Equatable {
    case popover
    case hudWindow
    case menu
    case underWindowBackground
    case sidebar
    case titlebar
    case selection
    case headerView
    case fullScreenUI
    case toolTip
    case sheet
    case windowBackground
    case contentBackground
    case underPageBackground

    /// 调参用：`DOCK_PANEL_MATERIAL=<名字>` 可以在**不重新构建**的前提下换材质，
    /// 一轮迭代约 8 秒，方便一次拍完整张候选对照表。名字就是上面这些 case（大小写不敏感）。
    /// 认不出的名字**回落到传入的默认值**，绝不崩——调参时手滑打错不该让应用起不来。
    static func resolved(from environment: [String: String], fallback: DockPanelMaterial) -> DockPanelMaterial {
        guard let raw = environment["DOCK_PANEL_MATERIAL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !raw.isEmpty else { return fallback }
        return all.first { "\($0)".lowercased() == raw } ?? fallback
    }

    /// 候选全集，供解析与对照表遍历。系统材质全部 macOS 10.14+，我们最低 12，无需可用性分支。
    static let all: [DockPanelMaterial] = [
        .popover, .hudWindow, .menu, .underWindowBackground, .sidebar,
        .titlebar, .selection, .headerView, .fullScreenUI, .toolTip,
        .sheet, .windowBackground, .contentBackground, .underPageBackground,
    ]
}

/// 图标的「淡化处理」。三个通道：褪透明 / 去饱和 / 压暗。
///
/// 为什么不能只有 opacity：`.opacity()` 是把图标往**底板颜色**上褪。深色底板是黑的，褪过去
/// 就是变暗，读起来是「暗下去了」，成立；浅色底板是浅灰的，褪过去等于往浅灰里化——本身深底的
/// 图标褪到 0.45 之后整块变成灰方块、品牌色发白，这就是 owner 2026-07-30 说的「灰蒙蒙」。
/// 浅色因此改成主要靠**去饱和 + 略压暗**表达「不在桌面上」，透明度只少量参与，图标保持「实」。
struct DockIconDim: Equatable {
    let opacity: Double
    /// 0 = 原色，1 = 全灰。
    let grayscale: Double
    /// 负值压暗，0 = 不动。浅色底板上单靠去饱和会偏亮，压一点才留得住对比。
    let brightness: Double

    /// 要不要挂颜色滤镜。全零 → 只挂 `.opacity`，与 2026-07-30 改造前逐像素一致
    ///（恒等的 `.grayscale(0)` / `.brightness(0)` 仍可能触发离屏渲染，会破坏深色的逐像素冻结）。
    var usesColorFilters: Bool { grayscale != 0 || brightness != 0 }
}

extension DockIconDim {
    /// 图标全亮（在桌面上）。
    static let bright = DockIconDim(opacity: 1, grayscale: 0, brightness: 0)
    /// 改造前全仓库唯一的淡化做法：纯 opacity，与外观无关，`DockStripView` 与
    /// `LauncherChipVisualPlan` 各自硬写。**深色列 = 这两个值（冻结）**——深色底板上
    /// 「往底色褪」本来就读作变暗，成立，所以深色不需要浅色那套颜色滤镜。
    static let legacyHidden = DockIconDim(opacity: 0.45, grayscale: 0, brightness: 0)
    static let legacyNotRunning = DockIconDim(opacity: 0.35, grayscale: 0, brightness: 0)
}

/// 图标此刻处在哪一档淡化。**只表达「在不在桌面上」**——「是否运行」由图标下方的白点单独表达，
/// 两者正交（运行但隐藏 = 有点 + hidden 档；已退出 = 无点 + notRunning 档）。
enum DockIconDimState: Equatable {
    case bright
    /// 运行中，但窗口被隐藏 / 最小化。
    case hidden
    /// 进程已退出（kept 占位图标、抽屉下区）。
    case notRunning
}

/// 与外观无关的形状常量。原先 `cornerRadius: 16` 在 `DockStripView` 的 private `Style` 里，
/// 导致 `DrawerView` / `FolderGridPopupView` / `ShelfGridPopupView` 各自硬写一遍 16。
enum DockShape {
    /// 所有悬浮面板（任务条 / 抽屉 / 胶囊 / 两个弹窗）的圆角。
    static let panelCornerRadius: CGFloat = 16
}

// MARK: - Tokens

struct DockThemeTokens: Equatable {

    // MARK: 面板（任务条 / 抽屉 / 抽屉胶囊 / 文件夹弹窗 / 中转弹窗 共用）

    /// 面板描边的**上沿**。苹果原生玻璃是「上沿亮、下沿几乎没有」，模拟来自上方的光；
    /// 改造前是均匀一圈白 0.15，浅色下就变成用户说的那圈「明显的方格」灰框。
    /// 深色两端同值（0.15 / 0.15）→ 渐变退化成均匀色，与改造前逐像素一致。
    let panelRimTop: DockTint
    /// 面板描边的**下沿 / 两侧**。
    let panelRimBottom: DockTint
    /// 投放命中时的整框高亮（抽屉图标拖到任务条上方、外部目录悬停文件夹区）。
    let panelRimHighlighted: DockTint
    let panelRimLineWidth: CGFloat
    let panelRimHighlightedLineWidth: CGFloat

    // MARK: 玻璃厚度感（内高光 + 内阴影）
    //
    // 真玻璃的「厚」来自边缘两道信号：上内沿一条亮线（光从上方进入介质）+ 下内沿一道暗收
    // （介质底部的自阴影）。这两层画在材质**之上**、内容**之下**，是我们自己的像素，
    // 因此不受「拿不到窗口背后像素」那条限制——折射和背景饱和度做不到，厚度感能做。
    //
    // **深色一律 opacity 0 + width 0**，渲染上等价于不画，深色继续逐像素冻结。

    let panelInnerHighlight: DockTint
    let panelInnerHighlightWidth: CGFloat
    let panelInnerHighlightBlur: CGFloat
    let panelInnerShadow: DockTint
    let panelInnerShadowWidth: CGFloat
    let panelInnerShadowBlur: CGFloat

    /// 背景饱和度倍数。**1.0 = 不加滤镜**（此时整个修饰符都不挂，同厚度层的理由）。
    ///
    /// 2026-07-30 实测：SwiftUI 的 `.saturation()` 作用在毛玻璃的**合成结果**上（材质 + 已模糊
    /// 的背景），所以能真的把背景颜色提浓，而且**模糊保留**——彩色靶实测条内饱和度
    /// 0.221 → 0.534，条外对照 0.398 不变。
    ///
    /// 对比之下 `.opacity()` 是**死路**，别再试：它把材质本身抹掉一部分、露出**没模糊过**的
    /// 原始桌面（实测条内过渡带从 115px 塌成 0.9px，和条外一样锐利），观感廉价，
    /// 不是"更透的玻璃"而是"挖了个洞的玻璃"。通透度只能靠换材质。
    let panelBackdropSaturation: Double
    /// 任务条 + 抽屉胶囊的落地阴影。
    let stripShadow: DockShadow
    /// 抽屉 + 两个弹窗的落地阴影（比任务条略收，因为它们悬在更高处）。
    let popupShadow: DockShadow
    let panelMaterial: DockPanelMaterial

    // MARK: 多窗口 chip 的标题胶囊

    /// 卡片底。**浅色必须翻成加黑**：浅色玻璃上「加白」等于消失，只剩描边孤零零留着，
    /// 于是每张卡看起来就是一个空心方格——用户抱怨的「方格」有一半来自这里。
    let chipPillFill: DockTintPair
    let chipPillRimTop: DockTintPair
    let chipPillRimBottom: DockTint

    // MARK: 文字

    /// 窗口标题（该窗口在桌面上可见时）。
    let labelActive: DockTint
    /// 窗口标题（已最小化 / 隐藏时）。
    let labelInactive: DockTint
    /// 悬停时冒出的名字（窗口 chip / 抽屉图标 / 文件夹名 / 中转格）。
    let labelHover: DockTint
    /// 标题胶囊下方的应用名副标题。
    let labelSubtitle: DockTint

    // MARK: 指示器

    /// 图标底下的运行小圆点。浅色下白点在浅玻璃上完全看不见。
    let runningDot: DockTint
    /// 任务条分区之间的竖分隔线。
    let zoneDivider: DockTint

    // MARK: 图标

    /// 所有 app 图标 / 文件夹封面 / 中转格底板共用的投影。
    let iconShadow: DockShadow

    /// 运行但被隐藏 / 最小化时的图标淡化。
    let iconDimHidden: DockIconDim
    /// 进程已退出时的图标淡化。
    let iconDimNotRunning: DockIconDim

    // MARK: 中转格

    let shelfPlateFill: DockTintPair
    let shelfPlateRim: DockTintPair
    let shelfGlyph: DockTint
    /// 投放命中时底板外扩的光晕。
    let shelfDropGlow: DockTint

    // MARK: 抽屉胶囊

    /// 抽屉为空时的九宫格占位符号。
    let capsuleGlyph: DockTint
    /// 拖卡悬到胶囊上的「微微发光」（去掉过生硬白圈后的替代反馈，owner 2026-06-21）。
    let capsuleStashGlow: DockTint

    // MARK: 固定文件夹 chip

    /// 外部文件拖到文件夹 chip 上（= 移入该文件夹）的命中环。
    let folderDropRing: DockTint
    /// 真缩略图封面的细描边（图标封面不描边）。
    let folderThumbHairline: DockTint

    // MARK: 文件夹 / 中转弹窗

    let popupCellLabel: DockTint
    let popupCellHover: DockTint
    /// 「无法读取文件夹内容」这类主提示。
    let popupPrimaryText: DockTint
    /// 「文件夹是空的」「拖文件到中转格暂存」这类次级提示。
    let popupSecondaryText: DockTint
    let backChipFill: DockTint
    let backChipRim: DockTint
    let backChipGlyph: DockTint

    // MARK: 窗口标题 tooltip

    /// 叠在 `.ultraThinMaterial` 上的染色层。深色是加黑压暗，**浅色要反过来加白**。
    let tooltipTint: DockTint
    let tooltipRim: DockTint
    let tooltipText: DockTint
    let tooltipShadow: DockShadow

    // MARK: 拖动浮动副本

    let carrierShadow: DockShadow

    /// 本表里某一档的图标淡化值。`.bright` 与外观无关，恒为不淡化。
    func iconDim(_ state: DockIconDimState) -> DockIconDim {
        switch state {
        case .bright: return .bright
        case .hidden: return iconDimHidden
        case .notRunning: return iconDimNotRunning
        }
    }

    /// 这一套值到底画不画厚度层。**深色必须是 `false`**——不是"画一层全透明的"，而是
    /// 整层根本不进视图树。`.blur(radius: 0)` 在 SwiftUI 里仍可能触发离屏渲染，
    /// 多一层就可能让深色的逐像素比对出现差异，冻结就不再是严格的。
    var drawsPanelThickness: Bool {
        Self.drawsThickness(highlight: panelInnerHighlight, highlightWidth: panelInnerHighlightWidth,
                            shadow: panelInnerShadow, shadowWidth: panelInnerShadowWidth)
    }

    /// 上面那条判断的纯函数形式（单测直接打这个，不用为了试 4 个值去构造整张 44 字段的表）。
    /// 颜色透明**或**线宽为 0 都等于看不见，两个条件必须同时满足才算"要画"。
    static func drawsThickness(highlight: DockTint, highlightWidth: CGFloat,
                               shadow: DockTint, shadowWidth: CGFloat) -> Bool {
        (highlight.opacity > 0 && highlightWidth > 0) || (shadow.opacity > 0 && shadowWidth > 0)
    }
}

// MARK: - 深色（冻结：逐项 = 改造前散落在各视图里的字面值）

extension DockThemeTokens {
    static let dark = DockThemeTokens(
        panelRimTop: .white(0.15),
        panelRimBottom: .white(0.15),
        panelRimHighlighted: .white(0.45),
        panelRimLineWidth: 0.5,
        panelRimHighlightedLineWidth: 1,
        // 深色不画厚度层（2026-07-30 冻结）：全 0 = 渲染上等价于这一层不存在。
        panelInnerHighlight: .white(0),
        panelInnerHighlightWidth: 0,
        panelInnerHighlightBlur: 0,
        panelInnerShadow: .black(0),
        panelInnerShadowWidth: 0,
        panelInnerShadowBlur: 0,
        panelBackdropSaturation: 1.0,
        stripShadow: DockShadow(tint: .black(0.35), radius: 15, y: 8),
        popupShadow: DockShadow(tint: .black(0.35), radius: 12, y: 5),
        panelMaterial: .popover,

        chipPillFill: DockTintPair(normal: .white(0.08), emphasized: .white(0.14)),
        chipPillRimTop: DockTintPair(normal: .white(0.15), emphasized: .white(0.25)),
        chipPillRimBottom: .white(0.02),

        labelActive: .white(0.9),
        labelInactive: .white(0.6),
        labelHover: .white(0.85),
        labelSubtitle: .white(0.65),

        runningDot: .white(0.85),
        zoneDivider: .white(0.18),

        iconShadow: DockShadow(tint: .black(0.22), radius: 3, y: 1),
        // 深色继续用纯 opacity 淡化：往黑底板上褪 = 变暗，本来就成立（冻结）。
        iconDimHidden: .legacyHidden,
        iconDimNotRunning: .legacyNotRunning,

        shelfPlateFill: DockTintPair(normal: .white(0.12), emphasized: .white(0.28)),
        shelfPlateRim: DockTintPair(normal: .white(0.18), emphasized: .white(0.4)),
        shelfGlyph: .white(0.9),
        shelfDropGlow: .white(0.25),

        capsuleGlyph: .white(0.72),
        capsuleStashGlow: .white(0.18),

        folderDropRing: .white(0.9),
        folderThumbHairline: .white(0.35),

        popupCellLabel: .white(0.9),
        popupCellHover: .white(0.12),
        popupPrimaryText: .white(0.8),
        popupSecondaryText: .white(0.5),
        backChipFill: .white(0.16),
        backChipRim: .white(0.2),
        backChipGlyph: .white(0.85),

        tooltipTint: .black(0.28),
        tooltipRim: .white(0.18),
        tooltipText: .white(0.94),
        tooltipShadow: DockShadow(tint: .black(0.32), radius: 6, y: 2),

        carrierShadow: DockShadow(tint: .black(0.35), radius: 8, y: 4)
    )
}

// MARK: - 浅色（第一版保守初值，等 owner 看实机效果拍板）

extension DockThemeTokens {
    /// 三条取值依据：
    /// ① **描边**：均匀灰框 → 亮上沿（白 0.60）+ 暗下沿（黑 0.10），对齐苹果原生玻璃的打光方向。
    /// ② **卡片底 / 底板**：由「加白」翻成「加黑」——浅色下加白等于消失，只剩描边 = 空心方格。
    /// ③ **阴影**：全线压淡并收进 `radius + |y| ≤ 20` 的预算内，消掉被面板边缘裁出的那道直边。
    static let light = DockThemeTokens(
        panelRimTop: .white(0.6),
        panelRimBottom: .black(0.1),
        panelRimHighlighted: .black(0.35),
        panelRimLineWidth: 0.5,
        panelRimHighlightedLineWidth: 1,
        // ⚠️ 下面两组是**候选值，默认不生效**——owner 还没验收，按「未验收一律 opt-in」
        // 的规矩由环境变量开（`DOCK_PANEL_THICKNESS=1` / `DOCK_PANEL_SATURATION=candidate`，
        // 见 `DockEffectSwitches`）。数值留在表里是为了调参时只有一张表可改。
        //
        // 厚度感候选：上内沿一条亮线 + 下内沿一道暗收。
        panelInnerHighlight: .white(0.5),
        panelInnerHighlightWidth: 1.5,
        panelInnerHighlightBlur: 2,
        panelInnerShadow: .black(0.06),
        panelInnerShadowWidth: 2,
        panelInnerShadowBlur: 3,
        // 背景提饱和候选。3.0 是实验用的极端值，日常这个量级即可。
        panelBackdropSaturation: 1.25,
        stripShadow: DockShadow(tint: .black(0.14), radius: 8, y: 3),
        popupShadow: DockShadow(tint: .black(0.14), radius: 8, y: 3),
        // 通透度候选待 owner 从对照表里指定；在那之前保持 .popover。
        panelMaterial: .popover,

        chipPillFill: DockTintPair(normal: .black(0.05), emphasized: .black(0.09)),
        chipPillRimTop: DockTintPair(normal: .white(0.55), emphasized: .white(0.7)),
        chipPillRimBottom: .black(0.1),

        labelActive: .black(0.85),
        labelInactive: .black(0.45),
        labelHover: .black(0.75),
        labelSubtitle: .black(0.55),

        runningDot: .black(0.5),
        zoneDivider: .black(0.12),

        iconShadow: DockShadow(tint: .black(0.12), radius: 2, y: 1),
        // 图标淡化：把「变淡」从褪透明改成去饱和 + 略压暗，图标保持「实」，不糊成一片灰。
        // **owner 2026-07-30 实机验收通过，这就是默认观感**（曾短暂挂在 `DOCK_ICON_DIM=1`
        // 后面，验收后开关即删——不再是候选，和下面那三个仍未验收的效果不是一回事）。
        //
        // 两档差得很近，是**故意的**（owner 同日第二次微调，推翻了第一版的「退出 = 全灰」）：
        // 「是否运行」由图标下方的白点表达（退出无点），图标本身不必再扛一遍这个区分，
        // 抽成灰色剪影反而死气。退出档只需要比隐藏档「稍微再灰一点」。
        iconDimHidden: DockIconDim(opacity: 0.80, grayscale: 0.45, brightness: -0.02),
        iconDimNotRunning: DockIconDim(opacity: 0.72, grayscale: 0.58, brightness: -0.03),

        shelfPlateFill: DockTintPair(normal: .black(0.05), emphasized: .black(0.12)),
        shelfPlateRim: DockTintPair(normal: .black(0.1), emphasized: .black(0.28)),
        shelfGlyph: .black(0.65),
        shelfDropGlow: .black(0.1),

        capsuleGlyph: .black(0.55),
        capsuleStashGlow: .black(0.1),

        folderDropRing: .black(0.45),
        folderThumbHairline: .black(0.15),

        popupCellLabel: .black(0.85),
        popupCellHover: .black(0.06),
        popupPrimaryText: .black(0.7),
        popupSecondaryText: .black(0.45),
        backChipFill: .black(0.06),
        backChipRim: .black(0.12),
        backChipGlyph: .black(0.75),

        tooltipTint: .white(0.55),
        tooltipRim: .black(0.1),
        tooltipText: .black(0.85),
        tooltipShadow: DockShadow(tint: .black(0.14), radius: 5, y: 2),

        carrierShadow: DockShadow(tint: .black(0.16), radius: 6, y: 3)
    )
}
