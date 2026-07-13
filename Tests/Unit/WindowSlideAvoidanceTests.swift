import CoreGraphics
import XCTest

final class WindowSlideAvoidanceTests: XCTestCase {
    private let geometry = WindowZoomAvoidance.Geometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        tungstenTop: 60
    )

    private let nativeFrame = CGRect(x: 0, y: 0, width: 1512, height: 949)
    private let key = WindowSlideAvoidance.WindowKey(pid: 100, cgWindowID: 200)

    func testDiscoverHidesBarAndBottomEdgeRevealsOnce() {
        let hidden = WindowSlideAvoidance.reduce(
            state: .idle,
            event: .discover(generation: 1, key: key, geometry: geometry, nativeFrame: nativeFrame)
        )
        XCTAssertEqual(hidden.action, .hideBar(generation: 1))

        let shown = WindowSlideAvoidance.reduce(state: hidden.state, event: .bottomEdge)
        guard case let .shown(session) = shown.state else {
            return XCTFail("Expected shown state")
        }
        XCTAssertEqual(session.generation, 2)
        XCTAssertEqual(shown.action, .revealAndLift(frame: geometry.adjustedFrame(for: nativeFrame)!, generation: 2))

        XCTAssertEqual(
            WindowSlideAvoidance.reduce(state: shown.state, event: .bottomEdge).action,
            .none
        )
    }

    func testFrontmostChangeRevealsOnlyFromHidden() {
        let hidden = discover()
        let other = WindowSlideAvoidance.WindowKey(pid: 101, cgWindowID: 201)
        let shown = WindowSlideAvoidance.reduce(
            state: hidden.state,
            event: .frontmostChanged(other)
        )
        XCTAssertEqual(shown.action, .revealAndLift(frame: geometry.adjustedFrame(for: nativeFrame)!, generation: 2))

        XCTAssertEqual(
            WindowSlideAvoidance.reduce(state: hidden.state, event: .frontmostChanged(key)).action,
            .none
        )
        XCTAssertEqual(
            WindowSlideAvoidance.reduce(state: hidden.state, event: .frontmostChanged(nil)).action,
            .none
        )
    }

    func testDiscoveringDifferentWindowRestartsHiddenSession() {
        let hidden = discover()
        let other = WindowSlideAvoidance.WindowKey(pid: 101, cgWindowID: 201)
        let restarted = WindowSlideAvoidance.reduce(
            state: hidden.state,
            event: .discover(generation: 3, key: other, geometry: geometry, nativeFrame: nativeFrame)
        )

        guard case let .hidden(session) = restarted.state else {
            return XCTFail("Expected a new hidden session")
        }
        XCTAssertEqual(session.key, other)
        XCTAssertEqual(session.generation, 3)
        XCTAssertEqual(restarted.action, .hideBar(generation: 3))
    }

    func testDiscoveringDifferentWindowRestartsShownSession() {
        let hidden = discover()
        let shown = WindowSlideAvoidance.reduce(state: hidden.state, event: .bottomEdge)
        let other = WindowSlideAvoidance.WindowKey(pid: 101, cgWindowID: 201)
        let restarted = WindowSlideAvoidance.reduce(
            state: shown.state,
            event: .discover(generation: 3, key: other, geometry: geometry, nativeFrame: nativeFrame)
        )

        guard case let .hidden(session) = restarted.state else {
            return XCTFail("Expected a new hidden session")
        }
        XCTAssertEqual(session.key, other)
        XCTAssertEqual(session.generation, 3)
        XCTAssertEqual(restarted.action, .hideBar(generation: 3))
    }

    func testDiscoveringSameWindowIsIdempotentWhileShown() {
        let hidden = discover()
        let shown = WindowSlideAvoidance.reduce(state: hidden.state, event: .bottomEdge)
        let repeated = WindowSlideAvoidance.reduce(
            state: shown.state,
            event: .discover(generation: 3, key: key, geometry: geometry, nativeFrame: nativeFrame)
        )

        XCTAssertEqual(repeated.state, shown.state)
        XCTAssertEqual(repeated.action, .none)
    }

    func testLeavingZoomLikeEndsHiddenSessionWithoutWindowAction() {
        let hidden = discover()
        let ended = WindowSlideAvoidance.reduce(
            state: hidden.state,
            event: .trackedStillZoomLike(false)
        )
        XCTAssertEqual(ended.state, .idle)
        XCTAssertEqual(ended.action, .showBarNormal(generation: 2))
    }

    func testLeavingZoomLikeEndsShownSessionAndDoesNotRevealAgain() {
        let hidden = discover()
        let shown = WindowSlideAvoidance.reduce(state: hidden.state, event: .bottomEdge)
        let ended = WindowSlideAvoidance.reduce(
            state: shown.state,
            event: .trackedStillZoomLike(false)
        )
        XCTAssertEqual(ended.state, .idle)
        XCTAssertEqual(ended.action, .showBarNormal(generation: 3))
    }

    func testScreenChangeEndsSession() {
        let hidden = discover()
        let ended = WindowSlideAvoidance.reduce(
            state: hidden.state,
            event: .screenParametersChanged
        )
        XCTAssertEqual(ended.state, .idle)
        XCTAssertEqual(ended.action, .showBarNormal(generation: 2))
    }

    func testScreenChangeEndsShownSession() {
        let hidden = discover()
        let shown = WindowSlideAvoidance.reduce(state: hidden.state, event: .bottomEdge)
        let ended = WindowSlideAvoidance.reduce(
            state: shown.state,
            event: .screenParametersChanged
        )

        XCTAssertEqual(ended.state, .idle)
        XCTAssertEqual(ended.action, .showBarNormal(generation: 3))
    }

    func testZoomLikeSampleDoesNotEndSession() {
        let hidden = discover()
        let transition = WindowSlideAvoidance.reduce(
            state: hidden.state,
            event: .trackedStillZoomLike(true)
        )
        XCTAssertEqual(transition.state, hidden.state)
        XCTAssertEqual(transition.action, .none)
    }

    private func discover() -> WindowSlideAvoidance.Transition {
        WindowSlideAvoidance.reduce(
            state: .idle,
            event: .discover(generation: 1, key: key, geometry: geometry, nativeFrame: nativeFrame)
        )
    }
}
