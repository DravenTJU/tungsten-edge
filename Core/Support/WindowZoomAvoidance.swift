import CoreGraphics
import Foundation

enum WindowZoomAvoidance {
    static let frameTolerance: CGFloat = 2
    static let clearance: CGFloat = 8
    static let pollDeadlines: [TimeInterval] = [0.1, 0.2, 0.4, 0.8]

    struct Geometry: Equatable {
        /// AppKit global coordinates (bottom-left origin).
        let screenFrame: CGRect
        let visibleFrame: CGRect
        let tungstenTop: CGFloat

        func adjustedFrame(for nativeZoomFrame: CGRect) -> CGRect? {
            guard mostlyBelongsToScreen(nativeZoomFrame) else { return nil }

            let targetBottom = max(
                nativeZoomFrame.minY,
                visibleFrame.minY,
                tungstenTop + WindowZoomAvoidance.clearance
            )
            guard targetBottom > nativeZoomFrame.minY + WindowZoomAvoidance.frameTolerance,
                  targetBottom < nativeZoomFrame.maxY - WindowZoomAvoidance.frameTolerance else {
                return nil
            }

            return CGRect(
                x: nativeZoomFrame.minX,
                y: targetBottom,
                width: nativeZoomFrame.width,
                height: nativeZoomFrame.maxY - targetBottom
            )
        }

        func isZoomLike(_ frame: CGRect) -> Bool {
            guard mostlyBelongsToScreen(frame), visibleFrame.width > 0, visibleFrame.height > 0 else {
                return false
            }
            let overlap = frame.intersection(visibleFrame)
            guard !overlap.isNull else { return false }
            return overlap.width >= visibleFrame.width * 0.75
                && overlap.height >= visibleFrame.height * 0.85
        }

        /// Strict discovery predicate: all four edges must cover the visible frame within tolerance.
        /// Keep this separate from isZoomLike, which intentionally accepts the raised frame during a session.
        func fillsVisibleFrame(_ frame: CGRect, tolerance: CGFloat = 12) -> Bool {
            guard visibleFrame.width > 0, visibleFrame.height > 0 else { return false }
            return abs(frame.minX - visibleFrame.minX) <= tolerance
                && abs(frame.minY - visibleFrame.minY) <= tolerance
                && abs(frame.maxX - visibleFrame.maxX) <= tolerance
                && abs(frame.maxY - visibleFrame.maxY) <= tolerance
        }

        private func mostlyBelongsToScreen(_ frame: CGRect) -> Bool {
            guard frame.width > 0, frame.height > 0 else { return false }
            let overlap = frame.intersection(screenFrame)
            guard !overlap.isNull else { return false }
            return overlap.width * overlap.height >= frame.width * frame.height * 0.5
        }
    }

    struct PollSchedule: Equatable {
        let deadlines: [TimeInterval]

        static let standard = PollSchedule(deadlines: WindowZoomAvoidance.pollDeadlines)

        var incrementalDelays: [TimeInterval] {
            var previous: TimeInterval = 0
            return deadlines.map { deadline in
                defer { previous = deadline }
                return max(0, deadline - previous)
            }
        }

        func remainingDelay(for index: Int, elapsed: TimeInterval) -> TimeInterval? {
            guard deadlines.indices.contains(index) else { return nil }
            return max(0, deadlines[index] - elapsed)
        }
    }

    struct ZoomPending: Equatable {
        let generation: UInt64
        let originalFrame: CGRect
        let geometry: Geometry
        var previousSample: CGRect?
        var lastPollIndex: Int
        var nativeZoomFrame: CGRect?
        var targetFrame: CGRect?
    }

    struct Session: Equatable {
        let generation: UInt64
        let originalFrame: CGRect
        let nativeZoomFrame: CGRect
        let adjustedFrame: CGRect
        let geometry: Geometry
    }

    struct RestorePending: Equatable {
        let generation: UInt64
        let session: Session
        var previousSample: CGRect?
        var lastPollIndex: Int
        var restoreTarget: CGRect?
    }

    enum State: Equatable {
        case idle
        case awaitingZoom(ZoomPending)
        case adjusted(Session)
        case awaitingRestore(RestorePending)
    }

    enum Event: Equatable {
        case begin(generation: UInt64, currentFrame: CGRect, geometry: Geometry)
        case sample(generation: UInt64, frame: CGRect?, pollIndex: Int)
        case adjustmentFinished(generation: UInt64, actualFrame: CGRect?)
        case restoreFinished(generation: UInt64, actualFrame: CGRect?)
        case windowUnavailable(generation: UInt64)
    }

    enum Action: Equatable {
        case none
        case wait(generation: UInt64)
        case adjust(frame: CGRect, generation: UInt64)
        case restore(frame: CGRect, generation: UInt64)
        case clear(generation: UInt64)
    }

    struct Transition: Equatable {
        let state: State
        let action: Action
    }

    static func reduce(state: State, event: Event) -> Transition {
        switch event {
        case let .begin(generation, currentFrame, geometry):
            if case let .adjusted(session) = state,
               framesMatch(currentFrame, session.adjustedFrame) {
                return Transition(
                    state: .awaitingRestore(RestorePending(
                        generation: generation,
                        session: session,
                        previousSample: nil,
                        lastPollIndex: -1,
                        restoreTarget: nil
                    )),
                    action: .wait(generation: generation)
                )
            }

            return Transition(
                state: .awaitingZoom(ZoomPending(
                    generation: generation,
                    originalFrame: currentFrame,
                    geometry: geometry,
                    previousSample: nil,
                    lastPollIndex: -1,
                    nativeZoomFrame: nil,
                    targetFrame: nil
                )),
                action: .wait(generation: generation)
            )

        case let .sample(generation, frame, pollIndex):
            switch state {
            case var .awaitingZoom(pending):
                guard pending.generation == generation,
                      pending.targetFrame == nil,
                      pollIndex > pending.lastPollIndex else {
                    return Transition(state: state, action: .none)
                }
                pending.lastPollIndex = pollIndex
                guard let frame else {
                    pending.previousSample = nil
                    return finishOrWait(pending: pending, pollIndex: pollIndex)
                }
                guard let previous = pending.previousSample,
                      framesMatch(previous, frame) else {
                    pending.previousSample = frame
                    return finishOrWait(pending: pending, pollIndex: pollIndex)
                }
                guard let target = pending.geometry.adjustedFrame(for: frame) else {
                    return Transition(state: .idle, action: .clear(generation: generation))
                }
                pending.nativeZoomFrame = frame
                pending.targetFrame = target
                return Transition(
                    state: .awaitingZoom(pending),
                    action: .adjust(frame: target, generation: generation)
                )

            case var .awaitingRestore(pending):
                guard pending.generation == generation,
                      pending.restoreTarget == nil,
                      pollIndex > pending.lastPollIndex else {
                    return Transition(state: state, action: .none)
                }
                pending.lastPollIndex = pollIndex
                guard let frame else {
                    pending.previousSample = nil
                    return finishOrWait(pending: pending, pollIndex: pollIndex)
                }
                guard let previous = pending.previousSample,
                      framesMatch(previous, frame) else {
                    pending.previousSample = frame
                    return finishOrWait(pending: pending, pollIndex: pollIndex)
                }

                let session = pending.session
                if framesMatch(frame, session.originalFrame)
                    || (!framesMatch(frame, session.adjustedFrame)
                        && !framesMatch(frame, session.nativeZoomFrame)
                        && !session.geometry.isZoomLike(frame)) {
                    return Transition(state: .idle, action: .clear(generation: generation))
                }

                pending.restoreTarget = session.originalFrame
                return Transition(
                    state: .awaitingRestore(pending),
                    action: .restore(frame: session.originalFrame, generation: generation)
                )

            case .idle, .adjusted:
                return Transition(state: state, action: .none)
            }

        case let .adjustmentFinished(generation, actualFrame):
            guard case let .awaitingZoom(pending) = state,
                  pending.generation == generation,
                  let nativeZoomFrame = pending.nativeZoomFrame,
                  let targetFrame = pending.targetFrame else {
                return Transition(state: state, action: .none)
            }
            guard let actualFrame, framesMatch(actualFrame, targetFrame) else {
                return Transition(state: .idle, action: .clear(generation: generation))
            }
            return Transition(
                state: .adjusted(Session(
                    generation: generation,
                    originalFrame: pending.originalFrame,
                    nativeZoomFrame: nativeZoomFrame,
                    adjustedFrame: actualFrame,
                    geometry: pending.geometry
                )),
                action: .none
            )

        case let .restoreFinished(generation, _):
            guard case let .awaitingRestore(pending) = state,
                  pending.generation == generation,
                  pending.restoreTarget != nil else {
                return Transition(state: state, action: .none)
            }
            return Transition(state: .idle, action: .clear(generation: generation))

        case let .windowUnavailable(generation):
            guard stateGeneration(of: state) == generation else {
                return Transition(state: state, action: .none)
            }
            return Transition(state: .idle, action: .clear(generation: generation))
        }
    }

    static func framesMatch(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = frameTolerance) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func finishOrWait(pending: ZoomPending, pollIndex: Int) -> Transition {
        if pollIndex >= pollDeadlines.count - 1 {
            return Transition(state: .idle, action: .clear(generation: pending.generation))
        }
        return Transition(state: .awaitingZoom(pending), action: .wait(generation: pending.generation))
    }

    private static func finishOrWait(pending: RestorePending, pollIndex: Int) -> Transition {
        if pollIndex >= pollDeadlines.count - 1 {
            return Transition(state: .idle, action: .clear(generation: pending.generation))
        }
        return Transition(state: .awaitingRestore(pending), action: .wait(generation: pending.generation))
    }

    private static func stateGeneration(of state: State) -> UInt64? {
        switch state {
        case .idle:
            return nil
        case let .awaitingZoom(pending):
            return pending.generation
        case let .adjusted(session):
            return session.generation
        case let .awaitingRestore(pending):
            return pending.generation
        }
    }
}
