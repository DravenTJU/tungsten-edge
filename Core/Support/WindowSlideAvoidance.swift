import CoreGraphics
import Foundation

/// Pure state machine for the slide zoom demo.
/// Geometry and frames use AppKit's global bottom-left coordinate system.
enum WindowSlideAvoidance {
    struct WindowKey: Equatable, Hashable {
        let pid: Int32
        let cgWindowID: CGWindowID
    }

    struct Session: Equatable {
        let generation: UInt64
        let key: WindowKey
        let geometry: WindowZoomAvoidance.Geometry
        let nativeFrame: CGRect
        let baselineFrontmost: WindowKey
    }

    enum State: Equatable {
        case idle
        case hidden(Session)
        case shown(Session)
    }

    enum Event: Equatable {
        case discover(
            generation: UInt64,
            key: WindowKey,
            geometry: WindowZoomAvoidance.Geometry,
            nativeFrame: CGRect
        )
        case bottomEdge
        case frontmostChanged(WindowKey?)
        case trackedStillZoomLike(Bool)
        case screenParametersChanged
    }

    enum Action: Equatable {
        case none
        case hideBar(generation: UInt64)
        case revealAndLift(frame: CGRect, generation: UInt64)
        case showBarNormal(generation: UInt64)
    }

    struct Transition: Equatable {
        let state: State
        let action: Action
    }

    static func reduce(state: State, event: Event) -> Transition {
        switch event {
        case let .discover(generation, key, geometry, nativeFrame):
            guard geometry.isZoomLike(nativeFrame),
                  geometry.adjustedFrame(for: nativeFrame) != nil else {
                return Transition(state: state, action: .none)
            }

            switch state {
            case .idle:
                break
            case let .hidden(session), let .shown(session):
                guard key != session.key else {
                    return Transition(state: state, action: .none)
                }
            }

            let session = Session(
                generation: generation,
                key: key,
                geometry: geometry,
                nativeFrame: nativeFrame,
                baselineFrontmost: key
            )
            return Transition(
                state: .hidden(session),
                action: .hideBar(generation: generation)
            )

        case .bottomEdge:
            guard case let .hidden(session) = state,
                  let adjusted = session.geometry.adjustedFrame(for: session.nativeFrame) else {
                return Transition(state: state, action: .none)
            }
            let generation = session.generation &+ 1
            let shown = Session(
                generation: generation,
                key: session.key,
                geometry: session.geometry,
                nativeFrame: session.nativeFrame,
                baselineFrontmost: session.baselineFrontmost
            )
            return Transition(
                state: .shown(shown),
                action: .revealAndLift(frame: adjusted, generation: generation)
            )

        case let .frontmostChanged(frontmost):
            guard case let .hidden(session) = state,
                  let frontmost,
                  frontmost != session.baselineFrontmost,
                  let adjusted = session.geometry.adjustedFrame(for: session.nativeFrame) else {
                return Transition(state: state, action: .none)
            }
            let generation = session.generation &+ 1
            let shown = Session(
                generation: generation,
                key: session.key,
                geometry: session.geometry,
                nativeFrame: session.nativeFrame,
                baselineFrontmost: session.baselineFrontmost
            )
            return Transition(
                state: .shown(shown),
                action: .revealAndLift(frame: adjusted, generation: generation)
            )

        case let .trackedStillZoomLike(isZoomLike):
            guard !isZoomLike else { return Transition(state: state, action: .none) }
            switch state {
            case .idle:
                return Transition(state: state, action: .none)
            case let .hidden(session), let .shown(session):
                let generation = session.generation &+ 1
                return Transition(
                    state: .idle,
                    action: .showBarNormal(generation: generation)
                )
            }

        case .screenParametersChanged:
            switch state {
            case .idle:
                return Transition(state: state, action: .none)
            case let .hidden(session), let .shown(session):
                let generation = session.generation &+ 1
                return Transition(
                    state: .idle,
                    action: .showBarNormal(generation: generation)
                )
            }
        }
    }
}
