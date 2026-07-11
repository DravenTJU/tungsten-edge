import CoreGraphics
import Foundation

/// Pass B「最小化折叠」的纯决策层：一个未被认领、AX 报最小化的合格窗口，到底是某个已落座
/// 物理窗口的后台标签（→ 折叠、不另建座位），还是真正独立的窗口（→ 新建座位）？
///
/// 背景：最小化一个多标签窗口时，Ghostty 会把该窗口的所有标签一下子暴露成 AX 窗口，全报
/// min=true。后台标签是 order-out 窗口，收不到 moved/resized 通知——窗口被移动/缩放过之后，
/// 它们的 AX 坐标和尺寸都停留在过时值，纯几何匹配会失效（一个标签裂一张卡）。
///
/// 判定三级，从强到弱：
/// 1. **成员关系**：候选 cgID 曾是某已放置座位的 activeCgID（标签创建即成为活跃标签 ⇒ 每个
///    后台标签都进过所属座位的历史）。与几何、min 标志完全无关——同时豁免「移动/缩放后
///    AX 几何过时」和「min 滞后竞态」两类折叠失效。
/// 2. **frame 精确匹配**：后台标签与所属窗口逐像素同 frame（窗口没动过时成立）。
/// 3. **尺寸兜底**：同宽高 ±3 + 屏幕外 + 对应座位已标最小化（窗口移动过、但没缩放过时成立）。
/// 三级全失败 → 新建座位（对 min=true 候选这是潜在分裂点，调用方打诊断日志）。
enum TabFoldDecision {

    /// 本轮对账已放置座位的折叠视角摘要。`activeCgID` 仅作回写索引（成员学习），不是身份。
    struct PlacedSeat {
        let activeCgID: CGWindowID
        let bounds: CGRect?
        let isMinimized: Bool
        let formerCgIDs: Set<CGWindowID>
    }

    enum Reason: String {
        case membership   // 曾是该座位的活跃标签
        case exactFrame   // frame 逐像素匹配
        case sameSize     // 同尺寸 + 屏幕外兜底
    }

    enum Verdict: Equatable {
        /// 折叠进已有座位，不另建。`ownerActiveCgID` 非 nil = 归属唯一确定，调用方可把候选
        /// cgID 记入该座位历史（成员学习：下次折叠不再依赖几何）；nil = 归属歧义，只折叠不学习。
        case fold(ownerActiveCgID: CGWindowID?, reason: Reason)
        case newSeat
    }

    static func verdict(
        candidateCgID: CGWindowID,
        candidateBounds: CGRect?,
        candidateIsMinimized: Bool,
        candidateIsOnScreen: Bool,
        placedSeats: [PlacedSeat],
        frameKey: (CGRect?) -> String?
    ) -> Verdict {
        // 非 min 的未认领窗口是合法新窗口（含"两个独立窗口重叠"场景），照常新建座位。
        guard candidateIsMinimized else { return .newSeat }

        // 1. 成员关系
        let owners = placedSeats.filter { $0.formerCgIDs.contains(candidateCgID) }
        if owners.count == 1 { return .fold(ownerActiveCgID: owners[0].activeCgID, reason: .membership) }
        if owners.count > 1 { return .fold(ownerActiveCgID: nil, reason: .membership) }

        // 2. frame 精确匹配
        if let key = frameKey(candidateBounds) {
            let matches = placedSeats.filter { frameKey($0.bounds) == key }
            if matches.count == 1 { return .fold(ownerActiveCgID: matches[0].activeCgID, reason: .exactFrame) }
            if matches.count > 1 { return .fold(ownerActiveCgID: nil, reason: .exactFrame) }
        }

        // 3. 尺寸兜底：屏幕外（非活跃标签）+ 与某已放置的最小化座位宽高相同
        if !candidateIsOnScreen, let sb = candidateBounds {
            let matches = placedSeats.filter { seat in
                guard seat.isMinimized, let pb = seat.bounds else { return false }
                return abs(pb.size.width - sb.size.width) < 3 &&
                       abs(pb.size.height - sb.size.height) < 3
            }
            if matches.count == 1 { return .fold(ownerActiveCgID: matches[0].activeCgID, reason: .sameSize) }
            if matches.count > 1 { return .fold(ownerActiveCgID: nil, reason: .sameSize) }
        }

        return .newSeat
    }
}
