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

    func testTooltipThresholdTracksDockScaleButBubbleDoesNot() {
        // 条内标题宽度随任务条缩放，截断判定必须用同一个宽度——两处各写死 140 就会出现
        // 「看着截断了却不弹 tooltip」（或反之）。
        for scale in [0.846153846, 1.0, 1.153846154, 1.307692308] as [CGFloat] {
            XCTAssertEqual(WindowTitleTextMetrics.maximumWidth(for: scale),
                           WindowTitleTextMetrics.maximumWidth * scale, accuracy: 0.001)
        }
        // 中档必须与历史字面值一致。气泡面板本身不缩（独立表面），这里只锁条内那段。
        XCTAssertEqual(WindowTitleTextMetrics.maximumWidth(for: 1.0), 140)
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
