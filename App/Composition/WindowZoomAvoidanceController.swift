import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import os

private let windowZoomAvoidanceAXTimeout: TimeInterval = 0.1
private let windowZoomAvoidanceHitTolerance: CGFloat = 4
private let windowZoomAvoidanceLogger = Logger(
    subsystem: "com.caye.macosdockcc.v2",
    category: "ZoomAvoidance"
)

struct WindowZoomAvoidanceContext {
    let geometry: WindowZoomAvoidance.Geometry
    let screenQuartzFrame: CGRect
    let primaryScreenHeight: CGFloat
}

private struct WindowZoomAvoidanceKey: Hashable {
    let pid: pid_t
    let cgWindowID: CGWindowID
}

private struct WindowZoomClickCandidate {
    let key: WindowZoomAvoidanceKey
    let quartzFrame: CGRect
    let clickQuartzPoint: CGPoint
    let timestamp: TimeInterval
}

private struct WindowZoomTarget {
    let key: WindowZoomAvoidanceKey
    let generation: UInt64
    let handle: AXWindowHandle
    let context: WindowZoomAvoidanceContext
    let startedAt: TimeInterval
}

@MainActor
final class WindowZoomAvoidanceController {
    private let contextProvider: () -> WindowZoomAvoidanceContext?
    private let reader = AXWindowReader()
    private var globalMouseMonitor: Any?
    private var terminationObserver: NSObjectProtocol?
    private var states: [WindowZoomAvoidanceKey: WindowZoomAvoidance.State] = [:]
    private var latestGenerations: [WindowZoomAvoidanceKey: UInt64] = [:]
    private var targets: [WindowZoomAvoidanceKey: WindowZoomTarget] = [:]
    private var pollTasks: [WindowZoomAvoidanceKey: Task<Void, Never>] = [:]
    private var nextGeneration: UInt64 = 0

    init(contextProvider: @escaping () -> WindowZoomAvoidanceContext?) {
        self.contextProvider = contextProvider
    }

    deinit {
        MainActor.assumeIsolated { stop() }
    }

    func start(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard globalMouseMonitor == nil,
              environment["DOCK_ZOOM_AVOIDANCE"] != "0" else {
            return
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option) else {
                return
            }

            // 翻转基准取主屏 screens[0]，不能用 NSScreen.main（跟着 key window 跑）。
            let primaryHeight = MainActor.assumeIsolated { ScreenGeometrySource.primaryMaxY }
            let appKitPoint = NSEvent.mouseLocation
            let quartzPoint = ScreenAttribution.quartzPoint(fromAppKit: appKitPoint, primaryMaxY: primaryHeight)
            guard let candidate = Self.topmostWindow(
                at: quartzPoint,
                timestamp: event.timestamp
            ) else {
                return
            }

            Task { @MainActor [weak self] in
                self?.begin(candidate: candidate)
            }
        }

        terminationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor [weak self] in
                self?.removeState(forPID: app.processIdentifier)
            }
        }
    }

    func stop() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let terminationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObserver)
            self.terminationObserver = nil
        }
        for task in pollTasks.values { task.cancel() }
        pollTasks.removeAll()
        targets.removeAll()
        states.removeAll()
        latestGenerations.removeAll()
    }

    private func begin(candidate: WindowZoomClickCandidate) {
        guard candidate.key.pid != pid_t(ProcessInfo.processInfo.processIdentifier),
              let context = contextProvider(),
              Self.mostlyBelongs(candidate.quartzFrame, to: context.screenQuartzFrame) else {
            return
        }

        pruneDeadWindowStates()
        nextGeneration &+= 1
        let generation = nextGeneration
        latestGenerations[candidate.key] = generation
        pollTasks[candidate.key]?.cancel()
        pollTasks[candidate.key] = nil

        let reader = self.reader
        Task.detached { [weak self] in
            guard let handle = reader.captureHandle(
                forPID: candidate.key.pid,
                cgWindowID: candidate.key.cgWindowID,
                messagingTimeout: windowZoomAvoidanceAXTimeout
            ), let currentFrame = reader.frame(
                of: handle.element,
                messagingTimeout: windowZoomAvoidanceAXTimeout
            ), reader.stringAttribute(
                kAXRoleAttribute as CFString,
                from: handle.element,
                maxAttempts: 1
            ) == (kAXWindowRole as String),
            reader.boolAttribute(
                "AXFullScreen" as CFString,
                from: handle.element,
                maxAttempts: 1
            ) != true,
            reader.frameSettableStatus(
                of: handle.element,
                messagingTimeout: windowZoomAvoidanceAXTimeout
            ).canSetFrame,
            let buttonFrame = reader.zoomButton(
                for: handle.element,
                messagingTimeout: windowZoomAvoidanceAXTimeout
            )?.frame else {
                await MainActor.run { [weak self] in
                    self?.discardUnvalidatedCandidate(key: candidate.key, generation: generation)
                }
                return
            }

            // The AX read can complete after the native zoom animation has moved the window.
            // Reconstruct the button's click-time frame from its stable offset to the window origin.
            let clickTimeButtonFrame = buttonFrame.offsetBy(
                dx: candidate.quartzFrame.minX - currentFrame.minX,
                dy: candidate.quartzFrame.minY - currentFrame.minY
            ).insetBy(dx: -windowZoomAvoidanceHitTolerance, dy: -windowZoomAvoidanceHitTolerance)
            guard clickTimeButtonFrame.contains(candidate.clickQuartzPoint) else {
                await MainActor.run { [weak self] in
                    self?.discardUnvalidatedCandidate(key: candidate.key, generation: generation)
                }
                return
            }

            await MainActor.run { [weak self] in
                self?.beginValidatedTarget(
                    candidate: candidate,
                    generation: generation,
                    handle: handle,
                    context: context
                )
            }
        }
    }

    private func beginValidatedTarget(
        candidate: WindowZoomClickCandidate,
        generation: UInt64,
        handle: AXWindowHandle,
        context: WindowZoomAvoidanceContext
    ) {
        let key = candidate.key
        guard latestGenerations[key] == generation else { return }

        let currentFrame = Self.appKitFrame(
            fromQuartz: candidate.quartzFrame,
            primaryScreenHeight: context.primaryScreenHeight
        )
        let transition = WindowZoomAvoidance.reduce(
            state: states[key] ?? .idle,
            event: .begin(
                generation: generation,
                currentFrame: currentFrame,
                geometry: context.geometry
            )
        )
        states[key] = transition.state
        targets[key] = WindowZoomTarget(
            key: key,
            generation: generation,
            handle: handle,
            context: context,
            startedAt: candidate.timestamp
        )
        startPolling(key: key, generation: generation)
    }

    private func startPolling(key: WindowZoomAvoidanceKey, generation: UInt64) {
        pollTasks[key]?.cancel()
        pollTasks[key] = Task { [weak self] in
            guard let self else { return }
            let schedule = WindowZoomAvoidance.PollSchedule.standard

            for index in schedule.deadlines.indices {
                guard !Task.isCancelled,
                      let target = self.targets[key],
                      target.generation == generation else {
                    return
                }

                let elapsed = max(0, ProcessInfo.processInfo.systemUptime - target.startedAt)
                if let remaining = schedule.remainingDelay(for: index, elapsed: elapsed), remaining > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
                guard !Task.isCancelled,
                      self.latestGenerations[key] == generation,
                      let liveTarget = self.targets[key],
                      liveTarget.generation == generation else {
                    return
                }

                let element = liveTarget.handle.element
                let primaryHeight = liveTarget.context.primaryScreenHeight
                let reader = self.reader
                let quartzFrame = await Task.detached {
                    reader.frame(of: element, messagingTimeout: windowZoomAvoidanceAXTimeout)
                }.value
                let appKitFrame = quartzFrame.map {
                    Self.appKitFrame(fromQuartz: $0, primaryScreenHeight: primaryHeight)
                }
                self.handle(
                    event: .sample(generation: generation, frame: appKitFrame, pollIndex: index),
                    for: key
                )

                guard self.isStillPolling(key: key, generation: generation) else { return }
            }
        }
    }

    private func isStillPolling(key: WindowZoomAvoidanceKey, generation: UInt64) -> Bool {
        guard latestGenerations[key] == generation, let state = states[key] else { return false }
        switch state {
        case let .awaitingZoom(pending):
            return pending.generation == generation && pending.targetFrame == nil
        case let .awaitingRestore(pending):
            return pending.generation == generation && pending.restoreTarget == nil
        case .idle, .adjusted:
            return false
        }
    }

    private func handle(event: WindowZoomAvoidance.Event, for key: WindowZoomAvoidanceKey) {
        let transition = WindowZoomAvoidance.reduce(state: states[key] ?? .idle, event: event)
        states[key] = transition.state

        switch transition.action {
        case .none, .wait:
            break
        case let .adjust(frame, generation):
            pollTasks[key]?.cancel()
            pollTasks[key] = nil
            applyAdjustment(frame, key: key, generation: generation)
        case let .restore(frame, generation):
            pollTasks[key]?.cancel()
            pollTasks[key] = nil
            applyRestore(frame, key: key, generation: generation)
        case let .clear(generation):
            clearOperation(for: key, generation: generation)
        }
    }

    private func applyAdjustment(
        _ targetFrame: CGRect,
        key: WindowZoomAvoidanceKey,
        generation: UInt64
    ) {
        guard latestGenerations[key] == generation,
              let target = targets[key],
              case let .awaitingZoom(pending) = states[key],
              pending.generation == generation,
              let nativeZoomFrame = pending.nativeZoomFrame else {
            return
        }

        let primaryHeight = target.context.primaryScreenHeight
        let targetQuartzFrame = Self.quartzFrame(
            fromAppKit: targetFrame,
            primaryScreenHeight: primaryHeight
        )
        let nativeQuartzFrame = Self.quartzFrame(
            fromAppKit: nativeZoomFrame,
            primaryScreenHeight: primaryHeight
        )
        let element = target.handle.element
        let reader = self.reader

        Task.detached { [weak self] in
            guard reader.boolAttribute(
                "AXFullScreen" as CFString,
                from: element,
                maxAttempts: 1
            ) != true else {
                await MainActor.run { [weak self] in
                    self?.handle(
                        event: .adjustmentFinished(generation: generation, actualFrame: nil),
                        for: key
                    )
                }
                return
            }

            let result = reader.setSize(
                targetQuartzFrame.size,
                for: element,
                messagingTimeout: windowZoomAvoidanceAXTimeout,
                verificationTolerance: WindowZoomAvoidance.frameTolerance,
                restoreOnFailureTo: nativeQuartzFrame
            )
            let actualFrame: CGRect?
            switch result {
            case let .success(quartzFrame):
                actualFrame = Self.appKitFrame(
                    fromQuartz: quartzFrame,
                    primaryScreenHeight: primaryHeight
                )
            case let .failure(reason, rollback):
                actualFrame = nil
                windowZoomAvoidanceLogger.error(
                    "adjust failed pid=\(key.pid, privacy: .public) wid=\(key.cgWindowID, privacy: .public) reason=\(String(describing: reason), privacy: .public) rollback=\(String(describing: rollback), privacy: .public)"
                )
            }

            await MainActor.run { [weak self] in
                self?.handle(
                    event: .adjustmentFinished(generation: generation, actualFrame: actualFrame),
                    for: key
                )
                if actualFrame != nil {
                    windowZoomAvoidanceLogger.info(
                        "adjusted pid=\(key.pid, privacy: .public) wid=\(key.cgWindowID, privacy: .public) bottom=\(targetFrame.minY, privacy: .public)"
                    )
                }
                if self?.latestGenerations[key] == generation {
                    self?.targets[key] = nil
                }
            }
        }
    }

    private func applyRestore(
        _ originalFrame: CGRect,
        key: WindowZoomAvoidanceKey,
        generation: UInt64
    ) {
        guard latestGenerations[key] == generation,
              let target = targets[key],
              case let .awaitingRestore(pending) = states[key],
              pending.generation == generation else {
            return
        }

        let primaryHeight = target.context.primaryScreenHeight
        let originalQuartzFrame = Self.quartzFrame(
            fromAppKit: originalFrame,
            primaryScreenHeight: primaryHeight
        )
        let rollbackFrame = pending.previousSample.map {
            Self.quartzFrame(fromAppKit: $0, primaryScreenHeight: primaryHeight)
        }
        let element = target.handle.element
        let reader = self.reader

        Task.detached { [weak self] in
            let result = reader.setFrame(
                originalQuartzFrame,
                for: element,
                messagingTimeout: windowZoomAvoidanceAXTimeout,
                verificationTolerance: WindowZoomAvoidance.frameTolerance,
                restoreOnFailureTo: rollbackFrame
            )
            let actualFrame: CGRect?
            switch result {
            case let .success(quartzFrame):
                actualFrame = Self.appKitFrame(
                    fromQuartz: quartzFrame,
                    primaryScreenHeight: primaryHeight
                )
            case let .failure(reason, rollback):
                actualFrame = nil
                windowZoomAvoidanceLogger.error(
                    "restore failed pid=\(key.pid, privacy: .public) wid=\(key.cgWindowID, privacy: .public) reason=\(String(describing: reason), privacy: .public) rollback=\(String(describing: rollback), privacy: .public)"
                )
            }

            await MainActor.run { [weak self] in
                self?.handle(
                    event: .restoreFinished(generation: generation, actualFrame: actualFrame),
                    for: key
                )
                if actualFrame != nil {
                    windowZoomAvoidanceLogger.info(
                        "restored pid=\(key.pid, privacy: .public) wid=\(key.cgWindowID, privacy: .public)"
                    )
                }
            }
        }
    }

    private func clearOperation(for key: WindowZoomAvoidanceKey, generation: UInt64) {
        guard latestGenerations[key] == generation else { return }
        pollTasks[key]?.cancel()
        pollTasks[key] = nil
        targets[key] = nil
        if states[key] == .idle { states[key] = nil }
        latestGenerations[key] = nil
    }

    private func discardUnvalidatedCandidate(key: WindowZoomAvoidanceKey, generation: UInt64) {
        guard latestGenerations[key] == generation else { return }
        pollTasks[key]?.cancel()
        pollTasks[key] = nil
        targets[key] = nil
        latestGenerations[key] = nil

        switch states[key] {
        case let .awaitingRestore(pending):
            states[key] = .adjusted(pending.session)
        case .adjusted:
            break
        case .idle, .awaitingZoom, nil:
            states[key] = nil
        }
    }

    private func removeState(forPID pid: pid_t) {
        let keys = Set(states.keys)
            .union(latestGenerations.keys)
            .union(targets.keys)
            .filter { $0.pid == pid }
        for key in keys { removeState(for: key) }
    }

    private func pruneDeadWindowStates() {
        let liveIDs = Self.allWindowIDs()
        let deadKeys = states.keys.filter { !liveIDs.contains($0.cgWindowID) }
        for key in deadKeys { removeState(for: key) }
    }

    private func removeState(for key: WindowZoomAvoidanceKey) {
        pollTasks[key]?.cancel()
        pollTasks[key] = nil
        targets[key] = nil
        latestGenerations[key] = nil
        states[key] = nil
    }

    nonisolated private static func topmostWindow(
        at quartzPoint: CGPoint,
        timestamp: TimeInterval
    ) -> WindowZoomClickCandidate? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let selfPID = pid_t(ProcessInfo.processInfo.processIdentifier)

        for info in list {
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  pidNumber.int32Value != selfPID,
                  let idNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.contains(quartzPoint),
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0 else {
                continue
            }

            return WindowZoomClickCandidate(
                key: WindowZoomAvoidanceKey(
                    pid: pid_t(pidNumber.int32Value),
                    cgWindowID: CGWindowID(idNumber.uint32Value)
                ),
                quartzFrame: bounds,
                clickQuartzPoint: quartzPoint,
                timestamp: timestamp
            )
        }
        return nil
    }

    nonisolated private static func allWindowIDs() -> Set<CGWindowID> {
        guard let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return Set(list.compactMap { info in
            (info[kCGWindowNumber as String] as? NSNumber).map { CGWindowID($0.uint32Value) }
        })
    }

    nonisolated private static func mostlyBelongs(_ frame: CGRect, to screen: CGRect) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let overlap = frame.intersection(screen)
        guard !overlap.isNull else { return false }
        return overlap.width * overlap.height >= frame.width * frame.height * 0.5
    }

    nonisolated private static func appKitFrame(
        fromQuartz frame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryScreenHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    nonisolated private static func quartzFrame(
        fromAppKit frame: CGRect,
        primaryScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryScreenHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}
