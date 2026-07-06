import CoreGraphics
import XCTest

final class PanelGeometryTests: XCTestCase {
    private let metrics = PanelLayoutMetrics.tungstenEdge

    func testBottomDockVisibleFrameChangeDoesNotMoveBottomPanelsVertically() {
        let hidden = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let shown = screen(
            frame: hidden.frame,
            visibleFrame: CGRect(x: 0, y: 80, width: 1512, height: 869)
        )

        let hiddenLayout = layout(on: hidden)
        let shownLayout = layout(on: shown)

        XCTAssertEqual(hiddenLayout.dock.minY, shownLayout.dock.minY)
        XCTAssertEqual(hiddenLayout.capsule.minY, shownLayout.capsule.minY)
        XCTAssertEqual(hiddenLayout.drawer.minY, shownLayout.drawer.minY)
    }

    func testSideDockVisibleFrameChangeDoesNotMoveOrResizeBottomPanelsHorizontally() {
        let hidden = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let leftDockShown = screen(
            frame: hidden.frame,
            visibleFrame: CGRect(x: 90, y: 0, width: 1422, height: 949)
        )
        let rightDockShown = screen(
            frame: hidden.frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1422, height: 949)
        )

        let hiddenLayout = layout(on: hidden)
        for candidate in [layout(on: leftDockShown), layout(on: rightDockShown)] {
            XCTAssertEqual(candidate.dock.minX, hiddenLayout.dock.minX)
            XCTAssertEqual(candidate.dock.width, hiddenLayout.dock.width)
            XCTAssertEqual(candidate.capsule.minX, hiddenLayout.capsule.minX)
            XCTAssertEqual(candidate.drawer.minX, hiddenLayout.drawer.minX)
        }
    }

    func testBottomAnchoringUsesNonZeroScreenMinY() {
        let upperScreen = screen(frame: CGRect(x: -488, y: 982, width: 2560, height: 1440))
        let lowerScreen = screen(frame: CGRect(x: -2408, y: -640, width: 1920, height: 1080))

        XCTAssertEqual(layout(on: upperScreen).dock.minY, upperScreen.frame.minY + metrics.bottomGap - metrics.shadowPadding)
        XCTAssertEqual(layout(on: lowerScreen).dock.minY, lowerScreen.frame.minY + metrics.bottomGap - metrics.shadowPadding)
    }

    func testDockFrameKeepsOriginalBottomCoordinate() {
        let screen = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))

        let dock = PanelGeometry.dockTargetFrame(contentWidth: 620, on: screen, metrics: metrics)

        XCTAssertEqual(dock.minY, -12)
        XCTAssertEqual(dock.height, 92)
    }

    func testDrawerTopCapUsesVisibleFrameWhenMenuBarIsLowerThanSafeAreaCap() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 920),
            safeAreaTop: 32
        )
        XCTAssertEqual(screen.topUsableY, 920)

        let drawer = layout(on: screen, drawerSize: CGSize(width: 210, height: 900)).drawer

        XCTAssertEqual(drawer.maxY, 920)
    }

    func testDrawerTopCapUsesSafeAreaWhenNotchIsLowerThanVisibleFrame() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32
        )
        XCTAssertEqual(screen.topUsableY, 950)

        let drawer = layout(on: screen, drawerSize: CGSize(width: 210, height: 900)).drawer

        XCTAssertEqual(drawer.maxY, 950)
    }

    func testMaxDrawerContentHeightUsesSameTopCapAsDrawerFrame() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaTop: 32
        )
        let frames = layout(on: screen)

        let maxHeight = PanelGeometry.maxDrawerContentHeight(forCapsule: frames.capsule, on: screen, metrics: metrics)

        XCTAssertEqual(maxHeight, (screen.topUsableY - frames.drawer.minY) - 2 * metrics.shadowPadding)
    }

    // MARK: - 文件夹弹窗

    func testFolderPopupAnchorsAboveAnchorRectAndCenters() {
        let screen = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let anchor = CGRect(x: 700, y: 8, width: 44, height: 52)

        let popup = PanelGeometry.folderPopupTargetFrame(
            anchorVisibleRect: anchor, size: CGSize(width: 400, height: 300), on: screen, metrics: metrics
        )

        XCTAssertEqual(popup.minY, anchor.maxY + 8)
        XCTAssertEqual(popup.midX, anchor.midX)
        XCTAssertEqual(popup.height, 300)
    }

    func testFolderPopupClampsHorizontallyIntoScreen() {
        let screen = screen(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        let leftAnchor = CGRect(x: 4, y: 8, width: 44, height: 52)
        let rightAnchor = CGRect(x: 1500, y: 8, width: 44, height: 52)
        let size = CGSize(width: 400, height: 300)

        let left = PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: leftAnchor, size: size, on: screen, metrics: metrics)
        let right = PanelGeometry.folderPopupTargetFrame(anchorVisibleRect: rightAnchor, size: size, on: screen, metrics: metrics)

        XCTAssertEqual(left.minX, screen.frame.minX)
        XCTAssertEqual(right.maxX, screen.frame.maxX)
    }

    func testFolderPopupHeightCappedByTopUsableY() {
        let screen = PanelScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 920),
            safeAreaTop: 0
        )
        let anchor = CGRect(x: 700, y: 8, width: 44, height: 52)

        let popup = PanelGeometry.folderPopupTargetFrame(
            anchorVisibleRect: anchor, size: CGSize(width: 400, height: 2000), on: screen, metrics: metrics
        )
        let maxContent = PanelGeometry.maxFolderPopupContentHeight(anchorVisibleRect: anchor, on: screen, metrics: metrics)

        XCTAssertEqual(popup.maxY, screen.topUsableY)
        XCTAssertEqual(maxContent, (screen.topUsableY - (anchor.maxY + 8)) - 2 * metrics.shadowPadding)
    }

    private func layout(
        on screen: PanelScreenGeometry,
        contentWidth: CGFloat = 620,
        drawerSize: CGSize = CGSize(width: 210, height: 260)
    ) -> (dock: CGRect, capsule: CGRect, drawer: CGRect) {
        let dock = PanelGeometry.dockTargetFrame(contentWidth: contentWidth, on: screen, metrics: metrics)
        let capsule = PanelGeometry.capsuleTargetFrame(forDock: dock, on: screen, metrics: metrics)
        let drawer = PanelGeometry.drawerTargetFrame(forCapsule: capsule, size: drawerSize, on: screen, metrics: metrics)
        return (dock, capsule, drawer)
    }

    private func screen(frame: CGRect, visibleFrame: CGRect? = nil, safeAreaTop: CGFloat = 0) -> PanelScreenGeometry {
        PanelScreenGeometry(frame: frame, visibleFrame: visibleFrame ?? frame, safeAreaTop: safeAreaTop)
    }
}
