import XCTest

/// `LauncherMenuPlan.itemKinds` 纯决策覆盖。核心：菜单运行态跟随「显示区」(`isRunning`)，
/// 待启动区（`isRunning=false`）图标即使进程仍活也不出现 显示/隐藏/退出。
final class LauncherMenuPlanTests: XCTestCase {

    func testRemoveOnlyNotRunningShowsOnlyMembership() {
        let kinds = LauncherMenuPlan.itemKinds(mode: .removeOnly, isRunning: false, isHidden: false, hasMembership: true)
        XCTAssertEqual(kinds, [.membership])
    }

    func testRemoveOnlyIgnoresRunningState() {
        // 纯固定图标即使 isRunning 为真也只给成员项（防御；实际不会落到运行区）。
        let kinds = LauncherMenuPlan.itemKinds(mode: .removeOnly, isRunning: true, isHidden: false, hasMembership: true)
        XCTAssertEqual(kinds, [.membership])
    }

    func testFullNotRunningHasNoAppActions() {
        // 关键回归：待启动区里进程仍活 / 收纳已退出的图标——最近文件 + 成员项，绝无 隐藏/退出。
        let kinds = LauncherMenuPlan.itemKinds(mode: .full, isRunning: false, isHidden: false, hasMembership: true)
        XCTAssertEqual(kinds, [.recentDocuments, .membership])
    }

    func testFullRunningVisibleShowsFullMenu() {
        let kinds = LauncherMenuPlan.itemKinds(mode: .full, isRunning: true, isHidden: false, hasMembership: true)
        XCTAssertEqual(kinds, [.recentDocuments, .hide, .quit, .membership])
    }

    func testFullRunningHiddenShowsUnhide() {
        let kinds = LauncherMenuPlan.itemKinds(mode: .full, isRunning: true, isHidden: true, hasMembership: true)
        XCTAssertEqual(kinds, [.recentDocuments, .show, .quit, .membership])
    }

    func testFullNotRunningNoMembershipIsEmpty() {
        let kinds = LauncherMenuPlan.itemKinds(mode: .full, isRunning: false, isHidden: false, hasMembership: false)
        XCTAssertEqual(kinds, [])
    }
}
