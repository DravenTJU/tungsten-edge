import XCTest

final class DrawerHoverPlanTests: XCTestCase {
    private func input(
        insideCapsule: Bool = false,
        insideDrawer: Bool = false,
        enabled: Bool = true,
        isDragging: Bool = false,
        drawerOpen: Bool = false,
        hoverOpened: Bool = false,
        openOnHoveredScreen: Bool = true
    ) -> DrawerHoverPlan.Input {
        DrawerHoverPlan.Input(
            insideCapsule: insideCapsule,
            insideDrawer: insideDrawer,
            enabled: enabled,
            isDragging: isDragging,
            drawerOpen: drawerOpen,
            hoverOpened: hoverOpened,
            openOnHoveredScreen: openOnHoveredScreen
        )
    }

    // MARK: - 基本展开

    func testHoveringClosedCapsuleArmsOpen() {
        XCTAssertEqual(DrawerHoverPlan.decide(input(insideCapsule: true)), [.cancelClose, .armOpen])
    }

    func testHoveringCapsuleWhileAlreadyOpenOnSameScreenDoesNothing() {
        let actions = DrawerHoverPlan.decide(input(
            insideCapsule: true, drawerOpen: true, hoverOpened: true, openOnHoveredScreen: true
        ))
        XCTAssertEqual(actions, [.cancelClose, .cancelOpen])
    }

    // MARK: - 不变量 1：拖动中让位给弹簧

    func testDraggingAlwaysYieldsToSpringLoad() {
        // 即使正悬在胶囊上、抽屉关着——拖动路径有自己的 0.4s 弹簧，两套定时器不能并存
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(insideCapsule: true, isDragging: true)),
            [.cancelOpen, .cancelClose]
        )
    }

    func testDraggingDoesNotCloseAHoverOpenedDrawer() {
        // 拖动开始时指针可能已离开胶囊；此时不能起收起定时器，否则拖到一半抽屉自己关了
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(isDragging: true, drawerOpen: true, hoverOpened: true)),
            [.cancelOpen, .cancelClose]
        )
    }

    // MARK: - 设置关掉

    func testDisabledNeverArmsAnything() {
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(insideCapsule: true, enabled: false)),
            [.cancelOpen, .cancelClose]
        )
    }

    func testDisabledDoesNotCloseAnAlreadyOpenDrawer() {
        // 用户在抽屉开着的时候关掉这个设置 → 不该把抽屉甩掉，交回点击语义
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(enabled: false, drawerOpen: true, hoverOpened: true)),
            [.cancelOpen, .cancelClose]
        )
    }

    // MARK: - 不变量 2：只自动收起自己开的

    func testLeavingClosesHoverOpenedDrawer() {
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(drawerOpen: true, hoverOpened: true)),
            [.cancelOpen, .armClose]
        )
    }

    func testLeavingDoesNotCloseClickOpenedDrawer() {
        // 点击开的抽屉是明确意图，鼠标移开不该收掉（保持改造前的语义）
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(drawerOpen: true, hoverOpened: false)),
            [.cancelOpen, .cancelClose]
        )
    }

    func testInsideDrawerNeverCloses() {
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(insideDrawer: true, drawerOpen: true, hoverOpened: true)),
            [.cancelClose, .cancelOpen]
        )
    }

    func testInsideDrawerDoesNotReopen() {
        // 抽屉里移动不该反复起展开定时器
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(insideDrawer: true, drawerOpen: true, hoverOpened: true)),
            [.cancelClose, .cancelOpen]
        )
    }

    // MARK: - 不变量 3：跨屏只搬自己开的

    func testHoveringOtherScreenCapsuleMovesAHoverOpenedDrawer() {
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(
                insideCapsule: true, drawerOpen: true, hoverOpened: true, openOnHoveredScreen: false
            )),
            [.cancelClose, .armOpen]
        )
    }

    func testHoveringOtherScreenCapsuleLeavesAClickOpenedDrawerAlone() {
        XCTAssertEqual(
            DrawerHoverPlan.decide(input(
                insideCapsule: true, drawerOpen: true, hoverOpened: false, openOnHoveredScreen: false
            )),
            [.cancelClose, .cancelOpen]
        )
    }

    // MARK: - 空闲

    func testIdleOutsideEverythingWithNoDrawerIsQuiet() {
        XCTAssertEqual(DrawerHoverPlan.decide(input()), [.cancelOpen, .cancelClose])
    }
}
