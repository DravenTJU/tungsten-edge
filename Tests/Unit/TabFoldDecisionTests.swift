import CoreGraphics
import XCTest

/// Pass B「最小化折叠」纯决策层（TabFoldDecision）。
/// 背景：Ghostty 最小化多标签窗口时把所有标签暴露成 min=true 的 AX 窗口；后台标签是 order-out
/// 窗口，移动/缩放后 AX 几何停留在过时值。判定四级：成员关系 → 影子标签池 → frame 精确匹配
/// → 尺寸兜底。影子池 = 上一轮「在 CG 却不在 AX」的 id（order-out 标签签名，免疫 dock 重启）。
final class TabFoldDecisionTests: XCTestCase {

    // 与 AppTracker.frameKey 同构的测试用 key（pid 固定即可）
    private func fk(_ b: CGRect?) -> String? {
        guard let b else { return nil }
        return "\(Int(b.origin.x.rounded())):\(Int(b.origin.y.rounded())):\(Int(b.size.width.rounded())):\(Int(b.size.height.rounded()))"
    }

    private func seat(
        cg: CGWindowID, bounds: CGRect?, min: Bool = true, former: Set<CGWindowID> = []
    ) -> TabFoldDecision.PlacedSeat {
        TabFoldDecision.PlacedSeat(activeCgID: cg, bounds: bounds, isMinimized: min, formerCgIDs: former)
    }

    private func verdict(
        cg: CGWindowID, bounds: CGRect?, min: Bool = true, onScreen: Bool = false,
        shadow: Bool = false, placed: [TabFoldDecision.PlacedSeat]
    ) -> TabFoldDecision.Verdict {
        TabFoldDecision.verdict(
            candidateCgID: cg, candidateBounds: bounds,
            candidateIsMinimized: min, candidateIsOnScreen: onScreen,
            candidateIsKnownShadow: shadow, placedSeats: placed, frameKey: fk
        )
    }

    private let frame = CGRect(x: 172, y: 87, width: 1191, height: 831)

    // MARK: - 既有行为锁定

    func testSameFrameBackgroundTabFolds() {
        // 窗口没动过：后台标签与座位逐像素同 frame → 精确匹配折叠
        let v = verdict(cg: 240522, bounds: frame, placed: [seat(cg: 249469, bounds: frame)])
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .exactFrame))
    }

    func testMovedWindowFoldsBySizeFallback() {
        // 窗口移动过：后台标签坐标过时（旧位置），尺寸没变 → 尺寸兜底折叠（6412015 行为）
        let moved = frame.offsetBy(dx: 300, dy: -60)
        let v = verdict(cg: 240522, bounds: frame, placed: [seat(cg: 249469, bounds: moved)])
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .sameSize))
    }

    func testNonMinimizedOverlappingWindowGetsNewSeat() {
        // 非 min 的同 frame 窗口 = 两个独立窗口重叠的合法场景 → 照常新建座位
        let v = verdict(cg: 240522, bounds: frame, min: false, onScreen: true,
                        placed: [seat(cg: 249469, bounds: frame, min: false)])
        XCTAssertEqual(v, .newSeat)
    }

    func testOnScreenCandidateDoesNotSizeMatch() {
        // 在屏窗口不是后台标签：即使同尺寸也不走尺寸兜底（独立窗口该有自己的座位）
        let moved = frame.offsetBy(dx: 300, dy: 0)
        let v = verdict(cg: 240522, bounds: frame, onScreen: true,
                        placed: [seat(cg: 249469, bounds: moved)])
        XCTAssertEqual(v, .newSeat)
    }

    // MARK: - 洞 1：缩放后几何全过时 → 成员关系兜住

    func testResizedWindowSplitsWithoutMembership() {
        // 缩放过的窗口：后台标签坐标和尺寸都过时 → 精确匹配、尺寸兜底双失败。
        // 无成员关系且不在影子池（如 dock 重启后第一轮）→ 只能新建座位（锁定这个缺口的存在）。
        let resized = CGRect(x: 172, y: 87, width: 900, height: 600)
        let v = verdict(cg: 240522, bounds: frame, placed: [seat(cg: 249469, bounds: resized)])
        XCTAssertEqual(v, .newSeat)
    }

    func testResizedWindowFoldsByMembership() {
        // 同上，但候选曾是该座位的活跃标签 → 成员折叠，与几何无关（洞 1 根治）
        let resized = CGRect(x: 172, y: 87, width: 900, height: 600)
        let v = verdict(cg: 240522, bounds: frame,
                        placed: [seat(cg: 249469, bounds: resized, former: [240522])])
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .membership))
    }

    // MARK: - 洞 2：min 滞后竞态 → 成员关系不看 min 标志

    func testMinLagRaceFoldsByMembership() {
        // 最小化瞬间：后台标签已暴露(min=true)，但活跃座位的 min 还没翻真（AX 滞后），
        // 且窗口移动过（精确匹配已失败）。尺寸兜底被 min 门槛挡住 → 旧逻辑分裂；
        // 成员折叠不看座位 min 标志 → 折叠（洞 2 根治）
        let moved = frame.offsetBy(dx: 300, dy: -60)
        let v = verdict(cg: 240522, bounds: frame,
                        placed: [seat(cg: 249469, bounds: moved, min: false, former: [240522])])
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .membership))
    }

    func testMinLagRaceWithoutMembershipStillSplits() {
        // 同竞态、无成员关系、不在影子池：尺寸兜底仍要求座位已标 min（保守，防误并独立窗口）→ 新建
        let moved = frame.offsetBy(dx: 300, dy: -60)
        let v = verdict(cg: 240522, bounds: frame,
                        placed: [seat(cg: 249469, bounds: moved, min: false)])
        XCTAssertEqual(v, .newSeat)
    }

    // MARK: - 影子标签池（成员历史被 dock 重启清零后的重启安全层）

    func testShadowPoolFoldsDespiteStaleGeometryAndMinLag() {
        // 缺口 A 核心：dock 重启后历史为空 + 窗口移动且缩放过（几何双失败）+ min 滞后竞态
        // （座位 min 还没翻真）。候选上一轮在 CG 却不在 AX（影子标签签名）→ 池折叠，
        // 唯一座位归属 + 学习。
        let resized = CGRect(x: 500, y: 300, width: 900, height: 600)
        let v = verdict(cg: 240522, bounds: frame, shadow: true,
                        placed: [seat(cg: 249469, bounds: resized, min: false)])
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .shadowPool))
    }

    func testShadowPoolRequiresMinimizedCandidate() {
        // 拽出标签变可见：它上一轮还是影子（order-out），现在 min=false → 必须正常分卡，池不拦
        let v = verdict(cg: 240522, bounds: frame.offsetBy(dx: 400, dy: 0), min: false,
                        onScreen: true, shadow: true,
                        placed: [seat(cg: 249469, bounds: frame, min: false)])
        XCTAssertEqual(v, .newSeat)
    }

    func testShadowPoolWithNoPlacedSeatsCreatesSeat() {
        // 零已放置座位时池不折叠——否则真最小化窗口组连一张代表卡都建不出来
        let v = verdict(cg: 240522, bounds: frame, shadow: true, placed: [])
        XCTAssertEqual(v, .newSeat)
    }

    func testShadowPoolMultiSeatFoldsWithoutLearning() {
        // 多座位归属歧义：仍折叠（不裂卡），但归属 nil = 不学习（宁可少学不误记）
        let v = verdict(cg: 240522, bounds: CGRect(x: 1, y: 2, width: 300, height: 200), shadow: true,
                        placed: [seat(cg: 249469, bounds: frame),
                                 seat(cg: 253982, bounds: frame.offsetBy(dx: 40, dy: 40))])
        XCTAssertEqual(v, .fold(ownerActiveCgID: nil, reason: .shadowPool))
    }

    func testMembershipWinsOverShadowPool() {
        // 成员关系优先于影子池：多座位时池只能折不能归属，成员关系能精确归属 → 先查成员
        let v = verdict(cg: 240522, bounds: frame, shadow: true,
                        placed: [seat(cg: 249469, bounds: frame.offsetBy(dx: 500, dy: 0), former: [240522]),
                                 seat(cg: 253982, bounds: frame)])
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .membership))
    }

    func testRealMinimizedWindowNotInShadowPoolGetsSeat() {
        // seed 时真最小化的独立窗口：min=true 但从一开始就在 AX（不是影子）、几何与已有座位
        // 不匹配 → 照常新建座位（不能被折没）
        let v = verdict(cg: 240522, bounds: CGRect(x: 50, y: 50, width: 400, height: 300),
                        placed: [seat(cg: 249469, bounds: frame)])
        XCTAssertEqual(v, .newSeat)
    }

    // MARK: - 防误并 / 歧义

    func testReusedCgIDAfterPurgeDoesNotFold() {
        // cgID 复用防护的决策层面：销毁后历史/影子池已被清除（purgeFromSeatHistories/CG 交集），
        // 复用的 cgID 不在任何座位历史里 → 只能靠几何，几何不匹配就新建，不误吸
        let v = verdict(cg: 240522, bounds: CGRect(x: 50, y: 50, width: 400, height: 300),
                        placed: [seat(cg: 249469, bounds: frame)])
        XCTAssertEqual(v, .newSeat)
    }

    func testAmbiguousMembershipFoldsWithoutLearning() {
        // 两个座位历史都认领同一 cgID（异常残留）→ 仍折叠（不裂卡），但归属 nil = 不学习
        let v = verdict(cg: 240522, bounds: frame,
                        placed: [seat(cg: 249469, bounds: frame, former: [240522]),
                                 seat(cg: 253982, bounds: frame.offsetBy(dx: 40, dy: 40), former: [240522])])
        XCTAssertEqual(v, .fold(ownerActiveCgID: nil, reason: .membership))
    }

    func testAmbiguousFrameMatchFoldsWithoutLearning() {
        // 两个座位同 frame（窗口重叠）→ 折叠但不学习（宁可少学，不误记归属）
        let v = verdict(cg: 240522, bounds: frame,
                        placed: [seat(cg: 249469, bounds: frame), seat(cg: 253982, bounds: frame)])
        XCTAssertEqual(v, .fold(ownerActiveCgID: nil, reason: .exactFrame))
    }

    func testMembershipWinsOverGeometry() {
        // 成员关系优先于精确匹配：候选在座位 A 历史里，却与座位 B 同 frame → 归 A
        let v = verdict(cg: 240522, bounds: frame,
                        placed: [seat(cg: 249469, bounds: frame.offsetBy(dx: 500, dy: 0), former: [240522]),
                                 seat(cg: 253982, bounds: frame)])
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .membership))
    }
}

/// 幽灵座位自愈纯判定（PhantomSeatDecision）：五门槛全过才释放，宁可不愈不误删。
/// 幽灵座位 = 折叠失手时从 min=true 爆发候选裂出来的多余座位（典型：dock 启动时窗口已最小化，
/// seed 无历史无影子池），还原窗口后它离开 AX、仍在 CG，被 min 保留规则永久扣住。
final class PhantomSeatDecisionTests: XCTestCase {

    private func release(
        everSeenVisible: Bool = false,
        axAbsentFor: TimeInterval = 12,
        cgStillPresent: Bool = true,
        axReadSawWindows: Bool = true,
        siblings: Int = 1
    ) -> Bool {
        PhantomSeatDecision.shouldRelease(
            everSeenVisible: everSeenVisible, axAbsentFor: axAbsentFor, threshold: 10,
            cgStillPresent: cgStillPresent, axReadSawWindows: axReadSawWindows,
            axPresentSiblingCount: siblings
        )
    }

    func testReleasesWhenAllGatesPass() {
        XCTAssertTrue(release())
    }

    func testEverSeenVisibleProtectsRealWindow() {
        // Safari 式真窗口：可见过 → 最小化后整个离开 AX 也永不自愈（最小化不丢卡是硬护栏）
        XCTAssertFalse(release(everSeenVisible: true))
    }

    func testUnderThresholdDoesNotRelease() {
        // AX 偶发漏读一两轮不算幽灵
        XCTAssertFalse(release(axAbsentFor: 9.9))
    }

    func testHungAppDoesNotRelease() {
        // 本轮 AX 一个窗口都没读到（app 挂死）→ 按兵不动
        XCTAssertFalse(release(axReadSawWindows: false))
    }

    func testLoneSeatNeverReleases() {
        // 孤座位永不自愈：app 仅有的卡不能被自愈删掉
        XCTAssertFalse(release(siblings: 0))
    }

    func testCgGoneIsNotHealingBusiness() {
        // 出了 CG 是真关闭，走既有删除路径，自愈不管
        XCTAssertFalse(release(cgStillPresent: false))
    }

    func testEvaluationExportsAllFailedGates() {
        let evaluation = PhantomSeatDecision.evaluate(
            everSeenVisible: true,
            axAbsentFor: 9.9,
            threshold: 10,
            cgStillPresent: false,
            axReadSawWindows: false,
            axPresentSiblingCount: 0
        )

        XCTAssertFalse(evaluation.shouldRelease)
        XCTAssertEqual(evaluation.holdReasons, [
            .everSeenVisible,
            .absenceGraceNotElapsed,
            .cgMissing,
            .noEligibleWindows,
            .noAXPresentSibling,
        ])
    }

    func testEvaluationExportsEachFailedGate() {
        let cases: [(PhantomSeatDecision.HoldReason, PhantomSeatDecision.Evaluation)] = [
            (.everSeenVisible, PhantomSeatDecision.evaluate(
                everSeenVisible: true, axAbsentFor: 10, threshold: 10,
                cgStillPresent: true, axReadSawWindows: true, axPresentSiblingCount: 1
            )),
            (.absenceGraceNotElapsed, PhantomSeatDecision.evaluate(
                everSeenVisible: false, axAbsentFor: 9.9, threshold: 10,
                cgStillPresent: true, axReadSawWindows: true, axPresentSiblingCount: 1
            )),
            (.cgMissing, PhantomSeatDecision.evaluate(
                everSeenVisible: false, axAbsentFor: 10, threshold: 10,
                cgStillPresent: false, axReadSawWindows: true, axPresentSiblingCount: 1
            )),
            (.noEligibleWindows, PhantomSeatDecision.evaluate(
                everSeenVisible: false, axAbsentFor: 10, threshold: 10,
                cgStillPresent: true, axReadSawWindows: false, axPresentSiblingCount: 1
            )),
            (.noAXPresentSibling, PhantomSeatDecision.evaluate(
                everSeenVisible: false, axAbsentFor: 10, threshold: 10,
                cgStillPresent: true, axReadSawWindows: true, axPresentSiblingCount: 0
            )),
        ]

        for (reason, evaluation) in cases {
            XCTAssertFalse(evaluation.shouldRelease)
            XCTAssertEqual(evaluation.holdReasons, [reason])
        }
    }

    func testEvaluationHasNoHoldReasonsWhenAllGatesPass() {
        let evaluation = PhantomSeatDecision.evaluate(
            everSeenVisible: false,
            axAbsentFor: 10,
            threshold: 10,
            cgStillPresent: true,
            axReadSawWindows: true,
            axPresentSiblingCount: 1
        )

        XCTAssertTrue(evaluation.shouldRelease)
        XCTAssertTrue(evaluation.holdReasons.isEmpty)
    }
}
