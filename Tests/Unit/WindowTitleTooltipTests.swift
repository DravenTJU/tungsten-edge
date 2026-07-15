import AppKit
import XCTest

final class WindowTitleTooltipTests: XCTestCase {
    func testFontUsesRenderedSizeRules() {
        XCTAssertEqual(WindowTitleTextMetrics.font(scale: 0.5).pointSize, 10)
        XCTAssertEqual(WindowTitleTextMetrics.font(scale: 1).pointSize, 12)
        XCTAssertEqual(WindowTitleTextMetrics.font(scale: 1.5).pointSize, 18)
    }

    func testFontUsesRoundedSystemDesign() {
        XCTAssertTrue(WindowTitleTextMetrics.font(scale: 1).fontName.contains("Rounded"))
    }

    func testIntrinsicWidthTracksScale() {
        let title = "activity-list.vue - project"
        let small = WindowTitleTextMetrics.intrinsicWidth(of: title, scale: 0.5)
        let regular = WindowTitleTextMetrics.intrinsicWidth(of: title, scale: 1)
        let large = WindowTitleTextMetrics.intrinsicWidth(of: title, scale: 1.5)

        XCTAssertLessThan(small, regular)
        XCTAssertLessThan(regular, large)
    }

    func testTruncationThresholdIncludesTolerance() {
        XCTAssertFalse(WindowTitleTextMetrics.isTruncated(intrinsicWidth: 142))
        XCTAssertTrue(WindowTitleTextMetrics.isTruncated(intrinsicWidth: 142.01))
    }

    func testEmptyAndShortTitlesDoNotNeedTooltip() {
        XCTAssertFalse(WindowTitleTextMetrics.needsTooltip(for: "", scale: 1))
        XCTAssertFalse(WindowTitleTextMetrics.needsTooltip(for: "Short", scale: 1))
    }

    func testLongTitleNeedsTooltip() {
        XCTAssertTrue(WindowTitleTextMetrics.needsTooltip(
            for: String(repeating: "Window title ", count: 20),
            scale: 1
        ))
    }
}
