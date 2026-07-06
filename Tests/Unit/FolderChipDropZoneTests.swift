import XCTest

/// 固定文件夹 chip 拖动松手落点分类（FolderChipDropZone.classify）。
/// 布局假定："strip" 局部坐标,可见区域 0..400 x 0..92,固定区右边界在 x=200。
final class FolderChipDropZoneTests: XCTestCase {
    private let stripVisibleRect = CGRect(x: 0, y: 0, width: 400, height: 92)
    private let folderZoneMaxX: CGFloat = 200

    func testPointWithinFolderZoneClassifiesAsFolderZone() {
        let zone = FolderChipDropZone.classify(point: CGPoint(x: 100, y: 40),
                                               stripVisibleRect: stripVisibleRect,
                                               folderZoneMaxX: folderZoneMaxX)
        XCTAssertEqual(zone, .folderZone)
    }

    func testPointRightOfFolderZoneButInsideStripClassifiesAsLiveZone() {
        let zone = FolderChipDropZone.classify(point: CGPoint(x: 300, y: 40),
                                               stripVisibleRect: stripVisibleRect,
                                               folderZoneMaxX: folderZoneMaxX)
        XCTAssertEqual(zone, .liveZone)
    }

    func testPointOutsideStripHorizontallyClassifiesAsOutsideStrip() {
        let left = FolderChipDropZone.classify(point: CGPoint(x: -10, y: 40),
                                               stripVisibleRect: stripVisibleRect,
                                               folderZoneMaxX: folderZoneMaxX)
        let right = FolderChipDropZone.classify(point: CGPoint(x: 410, y: 40),
                                                stripVisibleRect: stripVisibleRect,
                                                folderZoneMaxX: folderZoneMaxX)
        XCTAssertEqual(left, .outsideStrip)
        XCTAssertEqual(right, .outsideStrip)
    }

    func testPointOutsideStripVerticallyClassifiesAsOutsideStrip() {
        let above = FolderChipDropZone.classify(point: CGPoint(x: 100, y: -5),
                                                stripVisibleRect: stripVisibleRect,
                                                folderZoneMaxX: folderZoneMaxX)
        let below = FolderChipDropZone.classify(point: CGPoint(x: 100, y: 100),
                                                stripVisibleRect: stripVisibleRect,
                                                folderZoneMaxX: folderZoneMaxX)
        XCTAssertEqual(above, .outsideStrip)
        XCTAssertEqual(below, .outsideStrip)
    }

    func testNoBufferJustOutsideStripEdgeIsOutsideStrip() {
        // owner 反馈：命中范围按可见区域算，不留大缓冲区——紧贴边界外 1pt 就该判定为移出。
        let zone = FolderChipDropZone.classify(point: CGPoint(x: 400.5, y: 40),
                                               stripVisibleRect: stripVisibleRect,
                                               folderZoneMaxX: folderZoneMaxX)
        XCTAssertEqual(zone, .outsideStrip)
    }

    func testExactlyOnStripEdgeIsStillInside() {
        let zone = FolderChipDropZone.classify(point: CGPoint(x: 399.9, y: 40),
                                               stripVisibleRect: stripVisibleRect,
                                               folderZoneMaxX: folderZoneMaxX)
        XCTAssertEqual(zone, .liveZone)
    }

    func testExactlyAtFolderZoneBoundaryIsFolderZone() {
        let zone = FolderChipDropZone.classify(point: CGPoint(x: 200, y: 40),
                                               stripVisibleRect: stripVisibleRect,
                                               folderZoneMaxX: folderZoneMaxX)
        XCTAssertEqual(zone, .folderZone)
    }

    func testJustPastFolderZoneBoundaryIsLiveZone() {
        let zone = FolderChipDropZone.classify(point: CGPoint(x: 200.1, y: 40),
                                               stripVisibleRect: stripVisibleRect,
                                               folderZoneMaxX: folderZoneMaxX)
        XCTAssertEqual(zone, .liveZone)
    }

    func testScreenPointWithinFolderZoneClassifiesAsFolderZone() {
        let geometry = FolderChipDropGeometry(stripScreenRect: CGRect(x: 100, y: 500, width: 400, height: 92),
                                              folderZoneMaxX: folderZoneMaxX)
        let zone = geometry.classify(screenPoint: CGPoint(x: 250, y: 552))
        XCTAssertEqual(zone, .folderZone)
    }

    func testScreenPointWithinLiveZoneClassifiesAsLiveZone() {
        let geometry = FolderChipDropGeometry(stripScreenRect: CGRect(x: 100, y: 500, width: 400, height: 92),
                                              folderZoneMaxX: folderZoneMaxX)
        let zone = geometry.classify(screenPoint: CGPoint(x: 401, y: 552))
        XCTAssertEqual(zone, .liveZone)
    }

    func testScreenPointJustOutsideStripClassifiesAsOutsideStrip() {
        let geometry = FolderChipDropGeometry(stripScreenRect: CGRect(x: 100, y: 500, width: 400, height: 92),
                                              folderZoneMaxX: folderZoneMaxX)
        let zone = geometry.classify(screenPoint: CGPoint(x: 501, y: 552))
        XCTAssertEqual(zone, .outsideStrip)
    }
}
