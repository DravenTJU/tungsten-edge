import Foundation

/// 拖动来源：决定投放区、落点动作、载体绘制三处分支。
/// `.folder` = 固定文件夹 chip（区内重排 + 拖出移除 + 拖回窗口区打开）,**与 strip/drawer 收纳
/// 语义完全隔离**：不进 drawerStore、不进投放区（canExternalDrop=false）、不走 convert/revert;
/// DockStripView 只提供落点几何，最终 commit 由 `endDrag()` 的 mouseUp/轮询兜底路径触发。
/// `.messaging` = 消息区 app chip（区内重排 + 拖进抽屉收纳）：投放区与 `.strip` 相同
/// （胶囊 + 打开的抽屉体），任务条其余区域不是它的落点。
/// 定义放本文件（而非 DragController.swift）：测试 target 按"本地编译源文件"工作，纯决策层
/// 必须不带 DragController 的 AppKit 依赖就能编译。
enum DragSource { case strip, drawer, folder, messaging }

/// 抽屉图标拖到任务条时的行为模式（纯决策，DockStripView 喂事实）。
enum DrawerDragOutMode: Equatable {
    case reject             // Finder / 未运行的消息应用 → 不接受（留在抽屉）
    case releaseToMessaging // 运行中的消息应用 → 进消息区范围才临时释放回消息区
    case unstash            // 有真窗口 → 现有精确落位路径
    case keepPlacement      // app fallback / kept placeholder → app 级落位，绝不修改 kept
}

/// 跨面板拖拽转换的纯决策层（Codex 评审 2026-07-11 P2-6）。几何、store、面板都不进来——
/// 调用方喂当前事实，这里只回答"该做什么"，转换的执行与回滚在 `DragController`。
enum DragConversionPlan {

    /// 抽屉拖出模式判定。消息判定必须在真窗口判定**之前**——运行中的消息应用有主窗口，
    /// 否则会误入 unstash。未运行的消息应用拒收：消息区只显示运行中的应用，释放会凭空消失。
    static func drawerDragOutMode(bundleID: String,
                                  isMessagingMember: Bool,
                                  isInSnapshot: Bool,
                                  hasRealWindow: Bool,
                                  isKept: Bool) -> DrawerDragOutMode {
        guard !bundleID.isEmpty, bundleID != "com.apple.finder" else { return .reject }
        if isMessagingMember {
            return isInSnapshot ? .releaseToMessaging : .reject
        }
        if hasRealWindow { return .unstash }
        // app-* fallback while running, or a kept placeholder while stopped.
        return isInSnapshot || isKept ? .keepPlacement : .reject
    }

    /// `endDrag` 松手收尾动作（`.messaging` / `.drawer` 来源；`.strip`/`.folder` 不经这里）。
    enum EndAction: Equatable {
        case none
        /// 消息区 chip 落在投放区（胶囊/开着的抽屉）→ drawer.add 收纳。
        case stashMessagingChip
        /// 抽屉图标已转正进任务条 → 通知顺序层 commit。
        case commitDrawerToStrip
        /// 抽屉图标未转正、落任务条、非消息成员 → 降级移出（drawer.remove）。
        case fallbackUnstash
    }

    /// 松手决策。消息成员的抽屉图标**永不**走降级 unstash：它回任务条的唯一路径是
    /// 进消息区范围的临时释放（drawerToMessaging），其他位置松手一律留在抽屉（评审 P1-3）。
    /// 已释放回消息区的载荷来源是 `.messaging`：不在投放区 → `.none`（drawer.remove 已发生，
    /// 松手即落定）；在投放区 → 收纳（等效回滚，drawer.add 幂等）。
    static func endAction(source: DragSource,
                          isConvertedToStrip: Bool,
                          isOverDropZone: Bool,
                          isMessagingMember: Bool) -> EndAction {
        switch source {
        case .strip, .folder:
            return .none
        case .messaging:
            return isOverDropZone ? .stashMessagingChip : .none
        case .drawer:
            if isConvertedToStrip { return .commitDrawerToStrip }
            guard isOverDropZone, !isMessagingMember else { return .none }
            return .fallbackUnstash
        }
    }
}
