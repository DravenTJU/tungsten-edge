import XCTest

/// 外部文件拖入任务条的几何路由纯函数（StripDropRouting.route）。
/// 布局假定："strip" 空间,中转格在 x=100..144,文件夹 chip 52pt 宽、8pt 间距从 x=152 起排。
final class StripDropRoutingTests: XCTestCase {
    private let shelf = CGRect(x: 100, y: 0, width: 44, height: 52)

    private func frames(_ paths: [String], startX: CGFloat = 152) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        var x = startX
        for path in paths {
            result["folder-" + path] = CGRect(x: x, y: 0, width: 52, height: 52)
            x += 60
        }
        return result
    }

    func testHitShelfStashes() {
        let target = StripDropRouting.route(location: CGPoint(x: 120, y: 26),
                                            shelfFrame: shelf, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .stash)
    }

    func testLeftOfShelfIsNone() {
        let target = StripDropRouting.route(location: CGPoint(x: 50, y: 26),
                                            shelfFrame: shelf, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .none)
    }

    func testZeroShelfFrameRejectsEverything() {
        let target = StripDropRouting.route(location: CGPoint(x: 120, y: 26),
                                            shelfFrame: .zero, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .none)
    }

    func testNoFoldersPinsAtZeroWithinTailSlack() {
        // 中转格右缘 144 + 24pt 余量内 → 首次固定,插 0 位。
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            shelfFrame: shelf, folderFrames: [:], orderedPaths: [])
        XCTAssertEqual(target, .pin(insertIndex: 0))
    }

    func testDropOnLeftHalfOfFirstFolderMovesIntoIt() {
        let paths = ["/a", "/b"]
        // 第一个 chip 在 152..204；左右半都属于移入目标。
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testDropOnRightHalfOfFirstFolderMovesIntoIt() {
        let paths = ["/a", "/b"]
        let target = StripDropRouting.route(location: CGPoint(x: 190, y: 26),
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testDropUsesHorizontalChipBand() {
        let paths = ["/a"]
        let target = StripDropRouting.route(location: CGPoint(x: 180, y: 200),
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .moveInto(path: "/a"))
    }

    func testGapBetweenFoldersStillPins() {
        let paths = ["/a", "/b"]
        // 第一张右缘 204、第二张左缘 212；x=208 是真实 8pt 间隙。
        let target = StripDropRouting.route(location: CGPoint(x: 208, y: 26),
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 1))
    }

    func testMissingFrameDoesNotBecomeMoveTarget() {
        let paths = ["/a", "/b"]
        let partial = ["folder-/b": CGRect(x: 212, y: 0, width: 52, height: 52)]
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            shelfFrame: shelf, folderFrames: partial, orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 0))
    }

    func testTailSlackAfterLastFolderPinsAtEnd() {
        let paths = ["/a", "/b"]
        // 第二 chip 右缘 264,+24 余量内 → 追加末位(2)。
        let target = StripDropRouting.route(location: CGPoint(x: 276, y: 26),
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 2))
    }

    func testFarRightIsNone() {
        let paths = ["/a", "/b"]
        let target = StripDropRouting.route(location: CGPoint(x: 400, y: 26),
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .none)
    }
}
