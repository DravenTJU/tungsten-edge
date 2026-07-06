import XCTest

/// 外部文件拖入任务条的几何路由纯函数（StripDropRouting.route）。
/// 布局假定："strip" 空间,中转格在 x=100..144,文件夹 chip 44pt 宽、8pt 间距从 x=152 起排。
final class StripDropRoutingTests: XCTestCase {
    private let shelf = CGRect(x: 100, y: 0, width: 44, height: 52)

    private func frames(_ paths: [String], startX: CGFloat = 152) -> [String: CGRect] {
        var result: [String: CGRect] = [:]
        var x = startX
        for path in paths {
            result["folder-" + path] = CGRect(x: x, y: 0, width: 44, height: 52)
            x += 52
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

    func testDropOnLeftHalfOfFirstFolderPinsBeforeIt() {
        let paths = ["/a", "/b"]
        // 第一个 chip 在 152..196,midX=174;落 160 在其左半 → 插 0 位。
        let target = StripDropRouting.route(location: CGPoint(x: 160, y: 26),
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 0))
    }

    func testDropOnRightHalfOfFirstFolderPinsAfterIt() {
        let paths = ["/a", "/b"]
        // 落 180 在第一 chip 中点(174)右侧、第二 chip 中点(226)左侧 → 插 1 位。
        let target = StripDropRouting.route(location: CGPoint(x: 180, y: 26),
                                            shelfFrame: shelf, folderFrames: frames(paths), orderedPaths: paths)
        XCTAssertEqual(target, .pin(insertIndex: 1))
    }

    func testTailSlackAfterLastFolderPinsAtEnd() {
        let paths = ["/a", "/b"]
        // 第二 chip 右缘 248,+24 余量内 → 追加末位(2)。
        let target = StripDropRouting.route(location: CGPoint(x: 260, y: 26),
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
