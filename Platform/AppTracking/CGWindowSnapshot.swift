import CoreGraphics
import Foundation

struct AppTrackerCGWindowSnapshot: Equatable {
    let allWindowIDs: Set<CGWindowID>
    let onScreenWindowIDs: Set<CGWindowID>
    /// 按属主 pid 分组的 layer-0 窗口 id（影子标签池用：CG(pid) − AX 暴露集 = order-out 后台标签）。
    let windowIDsByPID: [pid_t: Set<CGWindowID>]
    /// AX inventory 没有透明度属性；按同轮 CG window id 补齐，供 admission 的 alpha=0 过滤使用。
    let alphaByWindowID: [CGWindowID: Double]

    static func capture() -> AppTrackerCGWindowSnapshot {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return AppTrackerCGWindowSnapshot(
                allWindowIDs: [],
                onScreenWindowIDs: [],
                windowIDsByPID: [:],
                alphaByWindowID: [:]
            )
        }
        return parse(windowInfo)
    }

    static func captureOnScreenWindowIDs() -> Set<CGWindowID> {
        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }
        return layerZeroWindowIDs(in: windowInfo)
    }

    /// 该 App 此刻压在最上面的那个**已收编**窗口（CG 层 0 + on-screen；`CGWindowListCopyWindowInfo`
    /// 返回的就是前→后的层叠顺序）。
    ///
    /// 只在 `candidates`（= 任务条上真有卡片的那些 cgWindowID）里挑。**不能**直接取「CG 里该 pid
    /// 最靠前的那个窗口」：几乎每个 App 都挂着无标题 / 全透明的 layer-0 窗口（飞书贴在屏幕顶端的
    /// 那些隐形窗口是实测案例，见 `findBackgroundActivationTarget` 的同类教训），它们会永远挡在
    /// 真正的文档窗口前面。
    ///
    /// `nil` = 这次读不出结论（列表拿不到、或该 App 的窗口一个都不在屏上）。调用方必须把 `nil`
    /// 当成「不知道」，不能当成「不是它」。
    static func frontmostOnScreenWindowID(
        forPID pid: pid_t,
        among candidates: Set<CGWindowID>
    ) -> CGWindowID? {
        guard !candidates.isEmpty,
              let windowInfo = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements],
                  kCGNullWindowID
              ) as? [[String: Any]] else {
            return nil
        }

        for info in windowInfo {
            guard let windowID = layerZeroWindowID(in: info),
                  candidates.contains(windowID),
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  pid_t(ownerPID) == pid else {
                continue
            }
            return windowID
        }
        return nil
    }

    static func parse(_ windowInfo: [[String: Any]]) -> AppTrackerCGWindowSnapshot {
        var allWindowIDs: Set<CGWindowID> = []
        var onScreenWindowIDs: Set<CGWindowID> = []
        var windowIDsByPID: [pid_t: Set<CGWindowID>] = [:]
        var alphaByWindowID: [CGWindowID: Double] = [:]

        for info in windowInfo {
            guard let windowID = layerZeroWindowID(in: info) else { continue }
            allWindowIDs.insert(windowID)
            if info[kCGWindowIsOnscreen as String] as? Bool == true {
                onScreenWindowIDs.insert(windowID)
            }
            if let ownerPID = info[kCGWindowOwnerPID as String] as? Int {
                windowIDsByPID[pid_t(ownerPID), default: []].insert(windowID)
            }
            if let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue {
                alphaByWindowID[windowID] = alpha
            }
        }

        return AppTrackerCGWindowSnapshot(
            allWindowIDs: allWindowIDs,
            onScreenWindowIDs: onScreenWindowIDs,
            windowIDsByPID: windowIDsByPID,
            alphaByWindowID: alphaByWindowID
        )
    }

    private static func layerZeroWindowIDs(in windowInfo: [[String: Any]]) -> Set<CGWindowID> {
        Set(windowInfo.compactMap(layerZeroWindowID(in:)))
    }

    private static func layerZeroWindowID(in info: [String: Any]) -> CGWindowID? {
        guard let layer = info[kCGWindowLayer as String] as? Int,
              layer == 0,
              let number = info[kCGWindowNumber as String] as? Int else {
            return nil
        }
        return CGWindowID(number)
    }
}
