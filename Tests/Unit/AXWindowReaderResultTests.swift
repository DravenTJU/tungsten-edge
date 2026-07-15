import ApplicationServices
import XCTest

final class AXWindowReaderResultTests: XCTestCase {
    func testSuccessPreservesOriginalWindowArray() {
        let snapshot = AXWindowSnapshot(
            pid: 42,
            cgWindowID: 123,
            title: "test",
            bounds: nil,
            role: nil,
            subrole: nil,
            isMinimized: false,
            isFocusedWindow: false,
            element: AXUIElementCreateApplication(42)
        )

        let windows = AXWindowReadResult.success([snapshot]).windowsOrEmpty

        XCTAssertEqual(windows.count, 1)
        XCTAssertEqual(windows[0].pid, snapshot.pid)
        XCTAssertEqual(windows[0].cgWindowID, snapshot.cgWindowID)
    }

    func testUnreadStillMapsToEmptyArrayAndKeepsError() {
        let result = AXWindowReadResult.unread(.cannotComplete)

        XCTAssertTrue(result.windowsOrEmpty.isEmpty)
        guard case .unread(let error) = result else {
            return XCTFail("expected unread")
        }
        XCTAssertEqual(error, .cannotComplete)
    }
}
