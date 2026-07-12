import CoreGraphics
import XCTest

final class CGWindowSnapshotTests: XCTestCase {
    func testParseSeparatesAllAndOnScreenLayerZeroWindows() {
        let snapshot = AppTrackerCGWindowSnapshot.parse([
            windowInfo(id: 11, layer: 0, isOnScreen: true),
            windowInfo(id: 12, layer: 0, isOnScreen: false),
            windowInfo(id: 13, layer: 1, isOnScreen: true),
        ])

        XCTAssertEqual(snapshot.allWindowIDs, [11, 12])
        XCTAssertEqual(snapshot.onScreenWindowIDs, [11])
    }

    func testParseTreatsMissingOnScreenFlagAsNotOnScreen() {
        let snapshot = AppTrackerCGWindowSnapshot.parse([
            windowInfo(id: 21, layer: 0, isOnScreen: nil),
        ])

        XCTAssertEqual(snapshot.allWindowIDs, [21])
        XCTAssertTrue(snapshot.onScreenWindowIDs.isEmpty)
    }

    func testParseIgnoresMalformedEntriesAndHandlesEmptyInput() {
        let malformed: [[String: Any]] = [
            [kCGWindowLayer as String: 0],
            [kCGWindowNumber as String: 31],
            [kCGWindowLayer as String: "0", kCGWindowNumber as String: 32],
        ]

        XCTAssertEqual(
            AppTrackerCGWindowSnapshot.parse(malformed),
            AppTrackerCGWindowSnapshot(allWindowIDs: [], onScreenWindowIDs: [])
        )
        XCTAssertEqual(
            AppTrackerCGWindowSnapshot.parse([]),
            AppTrackerCGWindowSnapshot(allWindowIDs: [], onScreenWindowIDs: [])
        )
    }

    private func windowInfo(id: Int, layer: Int, isOnScreen: Bool?) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowNumber as String: id,
            kCGWindowLayer as String: layer,
        ]
        if let isOnScreen {
            info[kCGWindowIsOnscreen as String] = isOnScreen
        }
        return info
    }
}
