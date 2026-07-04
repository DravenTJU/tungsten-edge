import XCTest

final class FullscreenClassificationTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    // 回归：Finder 桌面伪窗口（role=AXScrollArea，frame 恰好等于整屏）不得判为全屏
    func testDesktopPseudoWindowWithExactScreenFrameIsNotFullscreen() {
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: "AXScrollArea", isAXFullscreen: false, windowFrame: screen, screenCGFrame: screen))
    }

    func testUnreadableRoleIsNotFullscreenEvenWithExactScreenFrame() {
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: nil, isAXFullscreen: false, windowFrame: screen, screenCGFrame: screen))
    }

    func testUnreadableRoleIsNotFullscreenEvenWithAXFullscreenFlag() {
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: nil, isAXFullscreen: true, windowFrame: nil, screenCGFrame: screen))
    }

    func testNativeFullscreenWindowIsFullscreen() {
        XCTAssertTrue(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: true, windowFrame: screen, screenCGFrame: screen))
    }

    func testNativeFullscreenWithUnreadableFrameIsFullscreen() {
        XCTAssertTrue(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: true, windowFrame: nil, screenCGFrame: screen))
    }

    func testNativeFullscreenOnAnotherScreenIsNotFullscreenHere() {
        let otherScreen = CGRect(x: 1512, y: -200, width: 1920, height: 1080)
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: true, windowFrame: otherScreen, screenCGFrame: screen))
    }

    // 无 AXFullScreen 标志的无边框全屏（游戏/HTML5）仍走 frame≈整屏兜底
    func testBorderlessScreenSizedWindowIsFullscreen() {
        let nearScreen = screen.insetBy(dx: 2, dy: 2)
        XCTAssertTrue(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: false, windowFrame: nearScreen, screenCGFrame: screen))
    }

    func testOrdinaryWindowIsNotFullscreen() {
        let partial = CGRect(x: 253, y: 125, width: 1127, height: 689)
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: false, windowFrame: partial, screenCGFrame: screen))
    }

    func testRealWindowWithUnreadableFrameIsNotFullscreen() {
        XCTAssertFalse(FullscreenWindowClassifier.isFullscreen(
            role: "AXWindow", isAXFullscreen: false, windowFrame: nil, screenCGFrame: screen))
    }
}
