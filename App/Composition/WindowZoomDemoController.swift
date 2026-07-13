import AppKit
import CoreGraphics
import Foundation
import os

/// 「最大化窗口避开钨极」的两个对比 demo（throwaway，DOCK_ZOOM_DEMO 门控）。
/// 共用「看结果」检测：轮询 CG 前台窗口，最前那个若 ≈ 铺满 visibleFrame 即视为最大化。
///   - lift：钨极常驻，检测到最大化就把窗口底边收上来（窗口跳一下）。
///   - slide：钨极平滑滑走；底边或前台窗口变化唤回并抬窗，栏保持显示。
enum WindowZoomDemoMode: String {
    case lift
    case slide
}

@MainActor
protocol WindowZoomDemoHost: AnyObject {
    func demoZoomContext() -> WindowZoomAvoidanceContext?
    func demoActivateSlideMode()
    func demoSetSlideSessionActive(_ active: Bool)
    func demoSetBarHidden(_ hidden: Bool, animated: Bool, completion: (() -> Void)?)
}

@MainActor
final class WindowZoomDemoController {
    private typealias DemoWindowKey = WindowSlideAvoidance.WindowKey

    private let mode: WindowZoomDemoMode
    private weak var host: WindowZoomDemoHost?
    private let reader = AXWindowReader()
    private let logger = Logger(subsystem: "com.caye.macosdockcc.v2", category: "ZoomDemo")

    private static let pollInterval: TimeInterval = 0.2
    private static let hotZone: CGFloat = 4
    private static let trackedFalseSampleLimit = 2
    private static let frontmostStableSampleLimit = 2

    private var pollTimer: Timer?
    private var mouseMonitor: Any?
    private var screenParametersObserver: NSObjectProtocol?

    // lift 模式：已抬起的窗口（避免每轮重复抬）。
    private var liftedKey: DemoWindowKey?

    // slide 模式状态。
    private var slideState: WindowSlideAvoidance.State = .idle
    private var slideGeneration: UInt64 = 0
    private var slidePrimaryScreenHeight: CGFloat = 0
    private var slideEnding = false
    private var trackedFalseSamples = 0
    private var observedFrontmost: DemoWindowKey?
    private var observedFrontmostCount = 0
    private var slideWriteTask: Task<Void, Never>?

    init(mode: WindowZoomDemoMode, host: WindowZoomDemoHost) {
        self.mode = mode
        self.host = host
    }

    deinit {
        MainActor.assumeIsolated { stop() }
    }

    func start() {
        if mode == .slide {
            host?.demoActivateSlideMode()
            screenParametersObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleScreenParametersChanged()
                }
            }
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        if mode == .slide {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleSlideMouse() }
            }
        }
        logger.info("zoom demo started mode=\(self.mode.rawValue, privacy: .public)")
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil

        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let screenParametersObserver {
            NotificationCenter.default.removeObserver(screenParametersObserver)
            self.screenParametersObserver = nil
        }

        slideWriteTask?.cancel()
        slideWriteTask = nil
        guard mode == .slide else { return }

        slideGeneration &+= 1
        slideState = .idle
        slideEnding = false
        host?.demoSetBarHidden(false, animated: false, completion: nil)
        host?.demoSetSlideSessionActive(false)
    }

    // MARK: - Polling

    private func poll() {
        guard let context = host?.demoZoomContext() else {
            if mode == .lift {
                liftedKey = nil
            } else if !isSlideIdle {
                handleSlideEvent(.screenParametersChanged)
            }
            return
        }

        switch mode {
        case .lift:
            let target = Self.frontmostZoomLikeWindow(context: context)
            handleLiftPoll(target: target, context: context)
        case .slide:
            pollSlide(context: context)
        }
    }

    private func handleLiftPoll(
        target: (key: DemoWindowKey, appKit: CGRect)?,
        context: WindowZoomAvoidanceContext
    ) {
        guard let target else {
            liftedKey = nil
            return
        }
        if liftedKey == target.key { return }
        guard let adjusted = context.geometry.adjustedFrame(for: target.appKit) else { return }
        liftedKey = target.key
        applyLift(
            key: target.key,
            appKitTarget: adjusted,
            nativeAppKit: target.appKit,
            primaryHeight: context.primaryScreenHeight
        )
    }

    private func pollSlide(context: WindowZoomAvoidanceContext) {
        guard !slideEnding else { return }

        switch slideState {
        case .idle:
            guard let target = Self.frontmostZoomLikeWindow(context: context) else { return }
            slidePrimaryScreenHeight = context.primaryScreenHeight
            let generation = slideGeneration &+ 1
            slideGeneration = generation
            handleSlideEvent(.discover(
                generation: generation,
                key: target.key,
                geometry: context.geometry,
                nativeFrame: target.appKit
            ))

        case let .hidden(session), let .shown(session):
            if context.geometry.screenFrame != session.geometry.screenFrame {
                handleSlideEvent(.screenParametersChanged)
                host?.demoSetSlideSessionActive(false)
                return
            }

            // 新的最前最大化窗口优先开启新会话；同一窗口仍 zoom-like 时不重启。
            if let newMax = Self.frontmostZoomLikeWindow(context: context), newMax.key != session.key {
                let generation = slideGeneration &+ 1
                slideGeneration = generation
                handleSlideEvent(.discover(
                    generation: generation,
                    key: newMax.key,
                    geometry: context.geometry,
                    nativeFrame: newMax.appKit
                ))
                return
            }

            // End detection wins over frontmost-change detection after new-window discovery.
            let stillZoomLike = Self.trackedWindowIsZoomLike(
                key: session.key,
                geometry: session.geometry,
                primaryHeight: slidePrimaryScreenHeight
            )
            if stillZoomLike {
                trackedFalseSamples = 0
            } else {
                trackedFalseSamples += 1
                if trackedFalseSamples >= Self.trackedFalseSampleLimit {
                    trackedFalseSamples = 0
                    handleSlideEvent(.trackedStillZoomLike(false))
                    return
                }
            }

            guard case .hidden = slideState else { return }
            guard let frontmost = stableFrontmostWindowKey() else { return }
            if frontmost != session.baselineFrontmost {
                handleSlideEvent(.frontmostChanged(frontmost))
            }
        }
    }

    // MARK: - slide input and reducer

    private var isSlideIdle: Bool {
        if case .idle = slideState { return true }
        return false
    }

    private func handleSlideMouse() {
        guard case let .hidden(session) = slideState,
              !slideEnding else {
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = session.geometry.screenFrame
        guard screen.contains(mouse), mouse.y - screen.minY <= Self.hotZone else { return }
        handleSlideEvent(.bottomEdge)
    }

    private func handleSlideEvent(_ event: WindowSlideAvoidance.Event) {
        let transition = WindowSlideAvoidance.reduce(state: slideState, event: event)
        guard transition.state != slideState || transition.action != .none else { return }
        slideState = transition.state
        executeSlideAction(transition.action)
    }

    private func executeSlideAction(_ action: WindowSlideAvoidance.Action) {
        switch action {
        case .none:
            break

        case let .hideBar(generation):
            slideGeneration = generation
            trackedFalseSamples = 0
            resetFrontmostObservation()
            slideWriteTask?.cancel()
            slideWriteTask = nil
            host?.demoSetSlideSessionActive(true)
            host?.demoSetBarHidden(true, animated: true, completion: nil)

        case let .revealAndLift(_, generation):
            slideGeneration = generation
            guard case let .shown(session) = slideState else { return }
            slideWriteTask?.cancel()
            host?.demoSetBarHidden(false, animated: true, completion: nil)
            applySlideLift(
                key: session.key,
                geometry: session.geometry,
                primaryHeight: slidePrimaryScreenHeight,
                generation: generation
            )

        case let .showBarNormal(generation):
            slideGeneration = generation
            trackedFalseSamples = 0
            observedFrontmost = nil
            observedFrontmostCount = 0
            slideWriteTask?.cancel()
            slideWriteTask = nil
            slideEnding = true
            host?.demoSetBarHidden(false, animated: true) { [weak self] in
                guard let self else { return }
                self.slideEnding = false
                self.host?.demoSetSlideSessionActive(false)
                self.slidePrimaryScreenHeight = 0
            }
        }
    }

    private func handleScreenParametersChanged() {
        guard mode == .slide else { return }
        if !isSlideIdle {
            handleSlideEvent(.screenParametersChanged)
        }
    }

    private func resetFrontmostObservation() {
        guard case let .hidden(session) = slideState else {
            observedFrontmost = nil
            observedFrontmostCount = 0
            return
        }
        observedFrontmost = session.baselineFrontmost
        observedFrontmostCount = Self.frontmostStableSampleLimit
    }

    private func stableFrontmostWindowKey() -> DemoWindowKey? {
        let current = Self.frontmostWindowKey()
        guard let current else {
            observedFrontmost = nil
            observedFrontmostCount = 0
            return nil
        }
        if observedFrontmost == current {
            observedFrontmostCount += 1
        } else {
            observedFrontmost = current
            observedFrontmostCount = 1
        }
        return observedFrontmostCount >= Self.frontmostStableSampleLimit ? current : nil
    }

    // MARK: - AX writes

    private func applyLift(key: DemoWindowKey, appKitTarget: CGRect, nativeAppKit: CGRect, primaryHeight: CGFloat) {
        let targetQuartz = Self.quartzFrame(fromAppKit: appKitTarget, primaryHeight: primaryHeight)
        let nativeQuartz = Self.quartzFrame(fromAppKit: nativeAppKit, primaryHeight: primaryHeight)
        let reader = self.reader
        let logger = self.logger
        Task.detached {
            guard let handle = reader.captureHandle(
                forPID: pid_t(key.pid),
                cgWindowID: key.cgWindowID,
                messagingTimeout: 0.1
            ) else { return }
            let result = reader.setSize(
                targetQuartz.size,
                for: handle.element,
                messagingTimeout: 0.1,
                verificationTolerance: WindowZoomAvoidance.frameTolerance,
                restoreOnFailureTo: nativeQuartz
            )
            if case .failure = result {
                logger.error("lift failed pid=\(key.pid, privacy: .public) wid=\(key.cgWindowID, privacy: .public)")
            }
        }
    }

    private func applySlideLift(
        key: DemoWindowKey,
        geometry: WindowZoomAvoidance.Geometry,
        primaryHeight: CGFloat,
        generation: UInt64
    ) {
        guard isCurrentSlideGeneration(key: key, generation: generation) else { return }
        let reader = self.reader
        let logger = self.logger
        let task: Task<Void, Never> = Task.detached { [weak self] in
            guard !Task.isCancelled,
                  let handle = reader.captureHandle(
                      forPID: pid_t(key.pid),
                      cgWindowID: key.cgWindowID,
                      messagingTimeout: 0.1
                  ),
                  let currentQuartz = reader.frame(of: handle.element, messagingTimeout: 0.1) else {
                return
            }

            let currentAppKit = Self.appKitFrame(fromQuartz: currentQuartz, primaryHeight: primaryHeight)
            guard geometry.isZoomLike(currentAppKit),
                  let recomputedTarget = geometry.adjustedFrame(for: currentAppKit),
                  !Task.isCancelled else {
                return
            }
            let targetQuartz = Self.quartzFrame(fromAppKit: recomputedTarget, primaryHeight: primaryHeight)

            let result = reader.setSize(
                targetQuartz.size,
                for: handle.element,
                messagingTimeout: 0.1,
                verificationTolerance: WindowZoomAvoidance.frameTolerance,
                restoreOnFailureTo: nil
            )

            await MainActor.run { [weak self] in
                guard let self, self.isCurrentSlideGeneration(key: key, generation: generation) else { return }
                if case .failure = result {
                    logger.error("slide lift failed pid=\(key.pid, privacy: .public) wid=\(key.cgWindowID, privacy: .public) gen=\(generation, privacy: .public)")
                }
                self.slideWriteTask = nil
            }
        }
        slideWriteTask = task
    }

    private func isCurrentSlideGeneration(key: DemoWindowKey, generation: UInt64) -> Bool {
        switch slideState {
        case let .hidden(session), let .shown(session):
            return session.key == key && session.generation == generation
        case .idle:
            return false
        }
    }

    // MARK: - CG snapshots and coordinate conversion

    /// 钨极所在屏上、面积过半的最前窗口：若它 ≈ 铺满 visibleFrame 则返回，否则 nil。
    nonisolated private static func frontmostZoomLikeWindow(
        context: WindowZoomAvoidanceContext
    ) -> (key: DemoWindowKey, appKit: CGRect)? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let selfPID = pid_t(ProcessInfo.processInfo.processIdentifier)

        for info in list {
            guard let candidate = eligibleWindow(info, excludingPID: selfPID),
                  mostlyBelongs(candidate.bounds, to: context.screenQuartzFrame) else {
                continue
            }
            let appKit = appKitFrame(fromQuartz: candidate.bounds, primaryHeight: context.primaryScreenHeight)
            guard context.geometry.isZoomLike(appKit) else { return nil }
            return (candidate.key, appKit)
        }
        return nil
    }

    nonisolated private static func frontmostWindowKey() -> DemoWindowKey? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let selfPID = pid_t(ProcessInfo.processInfo.processIdentifier)
        return list.compactMap { eligibleWindow($0, excludingPID: selfPID)?.key }.first
    }

    nonisolated private static func trackedWindowIsZoomLike(
        key: DemoWindowKey,
        geometry: WindowZoomAvoidance.Geometry,
        primaryHeight: CGFloat
    ) -> Bool {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        for info in list {
            guard let candidate = eligibleWindow(info, excludingPID: pid_t(ProcessInfo.processInfo.processIdentifier)),
                  candidate.key == key else {
                continue
            }
            if let onScreen = info[kCGWindowIsOnscreen as String] as? Bool, !onScreen {
                return false
            }
            let appKit = appKitFrame(fromQuartz: candidate.bounds, primaryHeight: primaryHeight)
            return geometry.isZoomLike(appKit)
        }
        return false
    }

    private struct Candidate {
        let key: DemoWindowKey
        let bounds: CGRect
    }

    nonisolated private static func eligibleWindow(
        _ info: [String: Any],
        excludingPID selfPID: pid_t
    ) -> Candidate? {
        guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
              pidNumber.int32Value != selfPID,
              let idNumber = info[kCGWindowNumber as String] as? NSNumber,
              let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
              bounds.width >= 80,
              bounds.height >= 40,
              ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
              let app = NSRunningApplication(processIdentifier: pidNumber.int32Value),
              !app.isTerminated,
              app.activationPolicy == .regular || app.activationPolicy == .accessory else {
            return nil
        }
        return Candidate(
            key: DemoWindowKey(pid: pidNumber.int32Value, cgWindowID: CGWindowID(idNumber.uint32Value)),
            bounds: bounds
        )
    }

    nonisolated private static func mostlyBelongs(_ frame: CGRect, to screen: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let overlap = frame.intersection(screen)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height >= frame.width * frame.height * 0.5
    }

    nonisolated private static func appKitFrame(fromQuartz frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    nonisolated private static func quartzFrame(fromAppKit frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}

extension PanelCoordinator: WindowZoomDemoHost {}
