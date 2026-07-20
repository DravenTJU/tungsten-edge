import XCTest
@testable import macos_dock_cc_v2

final class LauncherMenuPlanTests: XCTestCase {

    func testRunningNotHiddenShowsHideAndQuit() {
        let kinds = LauncherMenuPlan.itemKinds(isRunning: true, isHidden: false, hasMembership: false)
        XCTAssertEqual(kinds, [.recentDocuments, .hide, .quit])
    }

    func testRunningHiddenShowsShowAndQuit() {
        let kinds = LauncherMenuPlan.itemKinds(isRunning: true, isHidden: true, hasMembership: false)
        XCTAssertEqual(kinds, [.recentDocuments, .show, .quit])
    }

    func testNotRunningNoMembershipShowsOpenOnly() {
        let kinds = LauncherMenuPlan.itemKinds(isRunning: false, isHidden: false, hasMembership: false)
        XCTAssertEqual(kinds, [.open])
    }

    func testNotRunningWithMembershipShowsOpenRecentAndMembership() {
        let kinds = LauncherMenuPlan.itemKinds(isRunning: false, isHidden: false, hasMembership: true)
        XCTAssertEqual(kinds, [.open, .recentDocuments, .membership])
    }

    func testRunningWithMembershipShowsAll() {
        let kinds = LauncherMenuPlan.itemKinds(isRunning: true, isHidden: false, hasMembership: true)
        XCTAssertEqual(kinds, [.recentDocuments, .hide, .membership, .quit])
    }

    /// 退出恒为末项：成员项曾被排在退出之后，导致 kept 图标菜单里「退出」落到倒数第三。
    func testQuitIsAlwaysLastWhenPresent() {
        for isRunning in [true, false] {
            for isHidden in [true, false] {
                for hasMembership in [true, false] {
                    let kinds = LauncherMenuPlan.itemKinds(isRunning: isRunning,
                                                           isHidden: isHidden,
                                                           hasMembership: hasMembership)
                    guard kinds.contains(.quit) else { continue }
                    XCTAssertEqual(kinds.last, .quit,
                                   "running=\(isRunning) hidden=\(isHidden) membership=\(hasMembership) → \(kinds)")
                }
            }
        }
    }

}
