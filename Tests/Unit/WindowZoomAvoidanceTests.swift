import CoreGraphics
import XCTest

final class WindowZoomAvoidanceTests: XCTestCase {
    private let geometry = WindowZoomAvoidance.Geometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
        tungstenTop: 60
    )

    func testGeometryRaisesOnlyBottomAndPreservesNativeTopAndWidth() {
        let native = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let adjusted = geometry.adjustedFrame(for: native)

        XCTAssertEqual(adjusted, CGRect(x: 0, y: 68, width: 1512, height: 881))
        XCTAssertEqual(adjusted?.maxY, native.maxY)
    }

    func testGeometryNeverLowersWindowPastSystemDockReservation() {
        let geometry = WindowZoomAvoidance.Geometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 90, width: 1512, height: 859),
            tungstenTop: 60
        )
        let native = CGRect(x: 0, y: 90, width: 1512, height: 859)

        XCTAssertNil(geometry.adjustedFrame(for: native))
    }

    func testSideDockDoesNotChangeBottomReservation() {
        let geometry = WindowZoomAvoidance.Geometry(
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 90, y: 0, width: 1422, height: 949),
            tungstenTop: 60
        )
        let native = CGRect(x: 90, y: 0, width: 1422, height: 949)

        XCTAssertEqual(geometry.adjustedFrame(for: native)?.minY, 68)
    }

    func testGeometrySupportsNegativeAndVerticallyStackedScreens() {
        let geometry = WindowZoomAvoidance.Geometry(
            screenFrame: CGRect(x: -2408, y: -640, width: 1920, height: 1080),
            visibleFrame: CGRect(x: -2408, y: -640, width: 1920, height: 1055),
            tungstenTop: -580
        )
        let native = CGRect(x: -2408, y: -640, width: 1920, height: 1055)

        let adjusted = geometry.adjustedFrame(for: native)
        XCTAssertEqual(adjusted?.minY, -572)
        XCTAssertEqual(adjusted?.maxY, native.maxY)
    }

    func testGeometryRejectsWindowMostlyOnAnotherScreen() {
        let native = CGRect(x: 1600, y: 0, width: 1200, height: 900)

        XCTAssertNil(geometry.adjustedFrame(for: native))
    }

    func testPollScheduleUsesAbsoluteDeadlinesAndVirtualElapsedTime() {
        let schedule = WindowZoomAvoidance.PollSchedule.standard

        XCTAssertEqual(schedule.deadlines, [0.1, 0.2, 0.4, 0.8])
        XCTAssertEqual(schedule.incrementalDelays, [0.1, 0.1, 0.2, 0.4])
        XCTAssertEqual(schedule.remainingDelay(for: 2, elapsed: 0.25) ?? -1, 0.15, accuracy: 0.0001)
        XCTAssertEqual(schedule.remainingDelay(for: 0, elapsed: 0.2), 0)
        XCTAssertNil(schedule.remainingDelay(for: 4, elapsed: 0))
    }

    func testFirstZoomAdjustsAfterTwoStableSamples() {
        let original = CGRect(x: 200, y: 180, width: 900, height: 650)
        let native = CGRect(x: 0, y: 0, width: 1512, height: 949)
        var transition = WindowZoomAvoidance.reduce(
            state: .idle,
            event: .begin(generation: 1, currentFrame: original, geometry: geometry)
        )

        transition = WindowZoomAvoidance.reduce(
            state: transition.state,
            event: .sample(generation: 1, frame: native, pollIndex: 0)
        )
        XCTAssertEqual(transition.action, .wait(generation: 1))

        transition = WindowZoomAvoidance.reduce(
            state: transition.state,
            event: .sample(generation: 1, frame: native, pollIndex: 1)
        )
        guard case let .adjust(target, generation) = transition.action else {
            return XCTFail("Expected adjust action")
        }
        XCTAssertEqual(generation, 1)
        XCTAssertEqual(target.minY, 68)

        transition = WindowZoomAvoidance.reduce(
            state: transition.state,
            event: .adjustmentFinished(generation: 1, actualFrame: target)
        )
        guard case let .adjusted(session) = transition.state else {
            return XCTFail("Expected adjusted state")
        }
        XCTAssertEqual(session.originalFrame, original)
        XCTAssertEqual(session.nativeZoomFrame, native)
    }

    func testSecondClickAcceptsNativeRestore() {
        let session = makeSession()
        var transition = WindowZoomAvoidance.reduce(
            state: .adjusted(session),
            event: .begin(generation: 2, currentFrame: session.adjustedFrame, geometry: geometry)
        )
        let restored = CGRect(x: 200, y: 180, width: 900, height: 650)

        transition = sampleStable(state: transition.state, generation: 2, frame: restored)

        XCTAssertEqual(transition.state, .idle)
        XCTAssertEqual(transition.action, .clear(generation: 2))
    }

    func testSecondClickRestoresOriginalWhenAppZoomsAgain() {
        let session = makeSession()
        var transition = WindowZoomAvoidance.reduce(
            state: .adjusted(session),
            event: .begin(generation: 2, currentFrame: session.adjustedFrame, geometry: geometry)
        )

        transition = sampleStable(state: transition.state, generation: 2, frame: session.nativeZoomFrame)

        XCTAssertEqual(transition.action, .restore(frame: session.originalFrame, generation: 2))
        transition = WindowZoomAvoidance.reduce(
            state: transition.state,
            event: .restoreFinished(generation: 2, actualFrame: session.originalFrame)
        )
        XCTAssertEqual(transition.state, .idle)
    }

    func testManualResizeInvalidatesAdjustedSessionAndStartsNewZoom() {
        let session = makeSession()
        let manuallyChanged = CGRect(x: 50, y: 100, width: 1000, height: 700)

        let transition = WindowZoomAvoidance.reduce(
            state: .adjusted(session),
            event: .begin(generation: 3, currentFrame: manuallyChanged, geometry: geometry)
        )

        guard case let .awaitingZoom(pending) = transition.state else {
            return XCTFail("Expected a new zoom operation")
        }
        XCTAssertEqual(pending.originalFrame, manuallyChanged)
        XCTAssertEqual(pending.generation, 3)
    }

    func testUnstableSamplesClearAtFinalPoll() {
        let original = CGRect(x: 200, y: 180, width: 900, height: 650)
        var transition = WindowZoomAvoidance.reduce(
            state: .idle,
            event: .begin(generation: 1, currentFrame: original, geometry: geometry)
        )

        for index in 0..<4 {
            let delta = CGFloat(index * 4)
            let frame = CGRect(x: 0, y: delta, width: 1512, height: 949 - delta)
            transition = WindowZoomAvoidance.reduce(
                state: transition.state,
                event: .sample(generation: 1, frame: frame, pollIndex: index)
            )
        }

        XCTAssertEqual(transition.state, .idle)
        XCTAssertEqual(transition.action, .clear(generation: 1))
    }

    func testAdjustmentFailureClearsSession() {
        let original = CGRect(x: 200, y: 180, width: 900, height: 650)
        let native = CGRect(x: 0, y: 0, width: 1512, height: 949)
        var transition = WindowZoomAvoidance.reduce(
            state: .idle,
            event: .begin(generation: 5, currentFrame: original, geometry: geometry)
        )
        transition = sampleStable(state: transition.state, generation: 5, frame: native)

        transition = WindowZoomAvoidance.reduce(
            state: transition.state,
            event: .adjustmentFinished(generation: 5, actualFrame: nil)
        )

        XCTAssertEqual(transition.state, .idle)
        XCTAssertEqual(transition.action, .clear(generation: 5))
    }

    func testStaleGenerationDoesNotChangeState() {
        let original = CGRect(x: 200, y: 180, width: 900, height: 650)
        let transition = WindowZoomAvoidance.reduce(
            state: .idle,
            event: .begin(generation: 8, currentFrame: original, geometry: geometry)
        )

        let stale = WindowZoomAvoidance.reduce(
            state: transition.state,
            event: .sample(generation: 7, frame: CGRect(x: 0, y: 0, width: 1512, height: 949), pollIndex: 0)
        )

        XCTAssertEqual(stale.state, transition.state)
        XCTAssertEqual(stale.action, .none)
    }

    func testUnavailableWindowClearsMatchingGenerationOnly() {
        let original = CGRect(x: 200, y: 180, width: 900, height: 650)
        let transition = WindowZoomAvoidance.reduce(
            state: .idle,
            event: .begin(generation: 9, currentFrame: original, geometry: geometry)
        )

        let stale = WindowZoomAvoidance.reduce(
            state: transition.state,
            event: .windowUnavailable(generation: 8)
        )
        XCTAssertEqual(stale.state, transition.state)

        let cleared = WindowZoomAvoidance.reduce(
            state: transition.state,
            event: .windowUnavailable(generation: 9)
        )
        XCTAssertEqual(cleared.state, .idle)
    }

    private func makeSession() -> WindowZoomAvoidance.Session {
        WindowZoomAvoidance.Session(
            generation: 1,
            originalFrame: CGRect(x: 200, y: 180, width: 900, height: 650),
            nativeZoomFrame: CGRect(x: 0, y: 0, width: 1512, height: 949),
            adjustedFrame: CGRect(x: 0, y: 68, width: 1512, height: 881),
            geometry: geometry
        )
    }

    private func sampleStable(
        state: WindowZoomAvoidance.State,
        generation: UInt64,
        frame: CGRect
    ) -> WindowZoomAvoidance.Transition {
        let first = WindowZoomAvoidance.reduce(
            state: state,
            event: .sample(generation: generation, frame: frame, pollIndex: 0)
        )
        return WindowZoomAvoidance.reduce(
            state: first.state,
            event: .sample(generation: generation, frame: frame, pollIndex: 1)
        )
    }
}
