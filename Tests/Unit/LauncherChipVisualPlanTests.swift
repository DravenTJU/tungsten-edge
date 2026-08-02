import XCTest
@testable import macos_dock_cc_v2

final class LauncherChipVisualPlanTests: XCTestCase {

    // 运行点是**唯一**的状态信号（2026-08-02 拿掉图标淡化之后）：运行=有点，退出=无点。
    // 与所在分区无关——消息区、抽屉下区、保留图标一视同仁。
    func testRunningDotFollowsProcessStateOnly() {
        XCTAssertTrue(LauncherChipVisualPlan.visual(isRunning: true).showsRunningDot)
        XCTAssertFalse(LauncherChipVisualPlan.visual(isRunning: false).showsRunningDot)
    }
}
