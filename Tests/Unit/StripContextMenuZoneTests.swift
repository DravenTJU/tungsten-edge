import XCTest
@testable import macos_dock_cc_v2

final class StripContextMenuZoneTests: XCTestCase {
    /// 中档基线的一条典型任务条：内缩 20pt，chip 52 宽、间距 8pt，
    /// 第 2、3 个 chip 之间夹一条分割线（多占 5pt，缝宽 21pt）。
    private let bounds = CGRect(x: 0, y: 0, width: 300, height: 52)
    private let chips: [CGRect] = [
        CGRect(x: 20, y: 0, width: 52, height: 52),    // 20...72
        CGRect(x: 80, y: 0, width: 52, height: 52),    // 80...132  （与上一个间隔 8pt）
        CGRect(x: 153, y: 0, width: 52, height: 52),   // 153...205（与上一个间隔 21pt：分割线）
    ]
    private let gap = StripContextMenuZone.defaultMinimumGapWidth

    private func claims(x: CGFloat) -> Bool {
        StripContextMenuZone.claims(
            point: CGPoint(x: x, y: 26),
            chipFrames: chips,
            bounds: bounds,
            minimumGapWidth: gap
        )
    }

    func testLeftInsetClaims() {
        XCTAssertTrue(claims(x: 10))
    }

    func testRightInsetClaims() {
        XCTAssertTrue(claims(x: 250))
    }

    func testDividerGapClaims() {
        // 缝是 132...153，正中 142.5。
        XCTAssertTrue(claims(x: 142))
    }

    /// 这一条是本次改动的**目的**：瞄图标差几 pt 落进窄缝时，宁可没反应，
    /// 也不要弹出钨极菜单顶掉那个 app 自己的菜单。
    func testPlainChipGapDoesNotClaim() {
        // 缝是 72...80，只有 8pt。
        XCTAssertFalse(claims(x: 76))
    }

    func testPointOnAChipDoesNotClaim() {
        XCTAssertFalse(claims(x: 46))
        XCTAssertFalse(claims(x: 106))
    }

    func testPointOutsideBoundsDoesNotClaim() {
        XCTAssertFalse(claims(x: -5))
        XCTAssertFalse(StripContextMenuZone.claims(
            point: CGPoint(x: 100, y: 999),
            chipFrames: chips,
            bounds: bounds,
            minimumGapWidth: gap
        ))
    }

    /// 首帧还没量到任何 chip 时不认——此刻分不清点在不在图标上，
    /// 抢走那个 app 的菜单比少弹一次更糟。
    func testEmptyFramesDoNotClaim() {
        XCTAssertFalse(StripContextMenuZone.claims(
            point: CGPoint(x: 10, y: 26),
            chipFrames: [],
            bounds: bounds,
            minimumGapWidth: gap
        ))
    }

    /// 两种缝在四个档位下都必须分得开：阈值和几何一起缩放，
    /// 普通缝恒 8×scale、分割线缝恒 21×scale。
    func testThresholdSeparatesBothGapsAtEveryTier() {
        // 四个档位的 scale = panelHeight / 52（小 44 / 中 52 / 大 60 / 特大 68）。
        let scales: [CGFloat] = [44 / 52, 1, 60 / 52, 68 / 52]
        for scale in scales {
            let plainGap: CGFloat = 8 * scale
            let dividerGap: CGFloat = 21 * scale
            let threshold: CGFloat = StripContextMenuZone.defaultMinimumGapWidth * scale
            XCTAssertLessThan(plainGap, threshold, "普通缝在 scale=\(scale) 下不该被认")
            XCTAssertGreaterThan(dividerGap, threshold, "分割线缝在 scale=\(scale) 下必须被认")
        }
    }

    /// 帧重叠（消息区外扩过的帧、拖动中的临时位置）不能被算成一道缝。
    func testOverlappingFramesDoNotSynthesizeAGap() {
        let overlapping = [
            CGRect(x: 20, y: 0, width: 52, height: 52),   // 20...72
            CGRect(x: 60, y: 0, width: 52, height: 52),   // 60...112，与上一个重叠
            CGRect(x: 100, y: 0, width: 52, height: 52),  // 100...152，与上一个重叠
        ]
        for x in stride(from: CGFloat(21), to: 151, by: 3) {
            XCTAssertFalse(
                StripContextMenuZone.claims(
                    point: CGPoint(x: x, y: 26),
                    chipFrames: overlapping,
                    bounds: bounds,
                    minimumGapWidth: gap
                ),
                "x=\(x) 落在连续覆盖区里，不该被当成缝"
            )
        }
    }
}
