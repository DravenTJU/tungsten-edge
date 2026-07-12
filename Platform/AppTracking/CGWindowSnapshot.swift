import CoreGraphics

struct AppTrackerCGWindowSnapshot: Equatable {
    let allWindowIDs: Set<CGWindowID>
    let onScreenWindowIDs: Set<CGWindowID>

    static func capture() -> AppTrackerCGWindowSnapshot {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return AppTrackerCGWindowSnapshot(allWindowIDs: [], onScreenWindowIDs: [])
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

    static func parse(_ windowInfo: [[String: Any]]) -> AppTrackerCGWindowSnapshot {
        var allWindowIDs: Set<CGWindowID> = []
        var onScreenWindowIDs: Set<CGWindowID> = []

        for info in windowInfo {
            guard let windowID = layerZeroWindowID(in: info) else { continue }
            allWindowIDs.insert(windowID)
            if info[kCGWindowIsOnscreen as String] as? Bool == true {
                onScreenWindowIDs.insert(windowID)
            }
        }

        return AppTrackerCGWindowSnapshot(
            allWindowIDs: allWindowIDs,
            onScreenWindowIDs: onScreenWindowIDs
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
