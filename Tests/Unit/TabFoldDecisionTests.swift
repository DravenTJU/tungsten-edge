import CoreGraphics
import XCTest

/// Pass B「最小化折叠」纯决策层（TabFoldDecision）。
/// 背景：Ghostty 最小化多标签窗口时把所有标签暴露成 min=true 的 AX 窗口；后台标签是 order-out
/// 窗口，移动/缩放后 AX 几何停留在过时值。判定三级：成员关系 → frame 精确匹配 → 尺寸兜底。
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

    private let frame = CGRect(x: 172, y: 87, width: 1191, height: 831)

    // MARK: - 既有行为锁定

    func testSameFrameBackgroundTabFolds() {
        // 窗口没动过：后台标签与座位逐像素同 frame → 精确匹配折叠
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [seat(cg: 249469, bounds: frame)], frameKey: fk
        )
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .exactFrame))
    }

    func testMovedWindowFoldsBySizeFallback() {
        // 窗口移动过：后台标签坐标过时（旧位置），尺寸没变 → 尺寸兜底折叠（6412015 行为）
        let moved = frame.offsetBy(dx: 300, dy: -60)
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,   // 过时坐标
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [seat(cg: 249469, bounds: moved)], frameKey: fk
        )
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .sameSize))
    }

    func testNonMinimizedOverlappingWindowGetsNewSeat() {
        // 非 min 的同 frame 窗口 = 两个独立窗口重叠的合法场景 → 照常新建座位
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,
            candidateIsMinimized: false, candidateIsOnScreen: true,
            placedSeats: [seat(cg: 249469, bounds: frame, min: false)], frameKey: fk
        )
        XCTAssertEqual(v, .newSeat)
    }

    func testOnScreenCandidateDoesNotSizeMatch() {
        // 在屏窗口不是后台标签：即使同尺寸也不走尺寸兜底（独立窗口该有自己的座位）
        let moved = frame.offsetBy(dx: 300, dy: 0)
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,
            candidateIsMinimized: true, candidateIsOnScreen: true,
            placedSeats: [seat(cg: 249469, bounds: moved)], frameKey: fk
        )
        XCTAssertEqual(v, .newSeat)
    }

    // MARK: - 洞 1：缩放后几何全过时 → 成员关系兜住

    func testResizedWindowSplitsWithoutMembership() {
        // 缩放过的窗口：后台标签坐标和尺寸都过时 → 精确匹配、尺寸兜底双失败。
        // 没有成员关系时只能新建座位（= 复发的分裂路径，锁定这个缺口的存在）。
        let resized = CGRect(x: 172, y: 87, width: 900, height: 600)
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,   // 过时坐标+过时尺寸
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [seat(cg: 249469, bounds: resized)], frameKey: fk
        )
        XCTAssertEqual(v, .newSeat)
    }

    func testResizedWindowFoldsByMembership() {
        // 同上，但候选曾是该座位的活跃标签 → 成员折叠，与几何无关（洞 1 根治）
        let resized = CGRect(x: 172, y: 87, width: 900, height: 600)
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [seat(cg: 249469, bounds: resized, former: [240522])], frameKey: fk
        )
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .membership))
    }

    // MARK: - 洞 2：min 滞后竞态 → 成员关系不看 min 标志

    func testMinLagRaceFoldsByMembership() {
        // 最小化瞬间：后台标签已暴露(min=true)，但活跃座位的 min 还没翻真（AX 滞后），
        // 且窗口移动过（精确匹配已失败）。尺寸兜底被 min 门槛挡住 → 旧逻辑分裂；
        // 成员折叠不看座位 min 标志 → 折叠（洞 2 根治）
        let moved = frame.offsetBy(dx: 300, dy: -60)
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [seat(cg: 249469, bounds: moved, min: false, former: [240522])], frameKey: fk
        )
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .membership))
    }

    func testMinLagRaceWithoutMembershipStillSplits() {
        // 同竞态、无成员关系：尺寸兜底仍要求座位已标 min（保守，防误并独立窗口）→ 新建
        let moved = frame.offsetBy(dx: 300, dy: -60)
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [seat(cg: 249469, bounds: moved, min: false)], frameKey: fk
        )
        XCTAssertEqual(v, .newSeat)
    }

    // MARK: - 防误并 / 歧义

    func testReusedCgIDAfterPurgeDoesNotFold() {
        // cgID 复用防护的决策层面：销毁后历史已被清除（purgeFromSeatHistories/CG 交集），
        // 复用的 cgID 不在任何座位历史里 → 只能靠几何，几何不匹配就新建，不误吸
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: CGRect(x: 50, y: 50, width: 400, height: 300),
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [seat(cg: 249469, bounds: frame)], frameKey: fk
        )
        XCTAssertEqual(v, .newSeat)
    }

    func testAmbiguousMembershipFoldsWithoutLearning() {
        // 两个座位历史都认领同一 cgID（异常残留）→ 仍折叠（不裂卡），但归属 nil = 不学习
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [
                seat(cg: 249469, bounds: frame, former: [240522]),
                seat(cg: 253982, bounds: frame.offsetBy(dx: 40, dy: 40), former: [240522]),
            ], frameKey: fk
        )
        XCTAssertEqual(v, .fold(ownerActiveCgID: nil, reason: .membership))
    }

    func testAmbiguousFrameMatchFoldsWithoutLearning() {
        // 两个座位同 frame（窗口重叠）→ 折叠但不学习（宁可少学，不误记归属）
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [seat(cg: 249469, bounds: frame), seat(cg: 253982, bounds: frame)],
            frameKey: fk
        )
        XCTAssertEqual(v, .fold(ownerActiveCgID: nil, reason: .exactFrame))
    }

    func testMembershipWinsOverGeometry() {
        // 成员关系优先于精确匹配：候选在座位 A 历史里，却与座位 B 同 frame → 归 A
        let v = TabFoldDecision.verdict(
            candidateCgID: 240522, candidateBounds: frame,
            candidateIsMinimized: true, candidateIsOnScreen: false,
            placedSeats: [
                seat(cg: 249469, bounds: frame.offsetBy(dx: 500, dy: 0), former: [240522]),
                seat(cg: 253982, bounds: frame),
            ], frameKey: fk
        )
        XCTAssertEqual(v, .fold(ownerActiveCgID: 249469, reason: .membership))
    }
}
