import AppKit
import Combine
import Foundation

/// Process-state projection for app-level launcher chips.
///
/// `AppTracker` remains the sole window-inventory authority and intentionally omits
/// ordinary apps with no eligible windows. This store independently observes regular
/// `NSRunningApplication` processes so a pinned icon can still show running/hidden
/// state after its last window closes. It never reads or mutates a window snapshot.
@MainActor
final class RunningApplicationStore: ObservableObject {
    @Published private(set) var runningBundleIDs: Set<String> = []
    @Published private(set) var hiddenBundleIDs: Set<String> = []

    private struct ProcessGeneration: Equatable {
        let pid: pid_t
        let startTimeSeconds: Int64
        let startTimeMicroseconds: Int64
    }

    private struct ProcessIdentity: Equatable {
        let generation: ProcessGeneration
        let bundleID: String
    }

    private struct ProcessState: Equatable {
        let identity: ProcessIdentity
        let bundleID: String
        var isHidden: Bool
    }

    private struct PolicyRecheck {
        let identity: ProcessIdentity
        let token: UUID
        var application: NSRunningApplication
        let task: Task<Void, Never>
    }

    private struct TerminationRecheck {
        let generation: ProcessGeneration
        let token: UUID
        let task: Task<Void, Never>
    }

    /// Absolute retry times are 0.2/0.5/1/2/4/8/12/20s after the notification.
    /// The final bound matches the launch-session fallback: after that the UI has already
    /// stopped presenting the process as an active launch.
    private static let policyRecheckSleepNanoseconds: [UInt64] = [
        200_000_000,
        300_000_000,
        500_000_000,
        1_000_000_000,
        2_000_000_000,
        4_000_000_000,
        4_000_000_000,
        8_000_000_000,
    ]

    /// Absolute retry times are 0.05s, 0.15s, 0.5s, 1s, and 2s after termination.
    private static let terminationRecheckSleepNanoseconds: [UInt64] = [
        50_000_000,
        100_000_000,
        350_000_000,
        500_000_000,
        1_000_000_000,
    ]
    private static let terminationSlowRecheckNanoseconds: UInt64 = 5_000_000_000

    private let workspace: NSWorkspace
    private var processesByPID: [pid_t: ProcessState] = [:]
    private var policyRechecksByPID: [pid_t: PolicyRecheck] = [:]
    private var terminationRechecksByPID: [pid_t: TerminationRecheck] = [:]
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    deinit {
        for recheck in policyRechecksByPID.values {
            recheck.task.cancel()
        }
        for recheck in terminationRechecksByPID.values {
            recheck.task.cancel()
        }
        for observer in observers {
            workspace.notificationCenter.removeObserver(observer)
        }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        subscribeWorkspaceNotifications()
        seedRunningApplications()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        for observer in observers {
            workspace.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        cancelAllPolicyRechecks()
        cancelAllTerminationRechecks()
        processesByPID.removeAll()
        publishProjection()
    }

    func isRunning(_ bundleID: String) -> Bool {
        runningBundleIDs.contains(bundleID)
    }

    func isHidden(_ bundleID: String) -> Bool {
        hiddenBundleIDs.contains(bundleID)
    }

    private func seedRunningApplications() {
        processesByPID.removeAll()
        for application in workspace.runningApplications {
            handleAdmissionCandidate(application, publishImmediately: false)
        }
        publishProjection()
    }

    private func subscribeWorkspaceNotifications() {
        let notificationCenter = workspace.notificationCenter

        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = Self.application(from: notification) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.handleAdmissionCandidate(application)
            }
        })

        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = Self.application(from: notification) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.handleAdmissionCandidate(application)
            }
        })

        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = Self.application(from: notification) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.handleTermination(application)
                self.publishProjection()
            }
        })

        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didHideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = Self.application(from: notification) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.update(application, isHidden: true)
                self.publishProjection()
            }
        })

        observers.append(notificationCenter.addObserver(
            forName: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = Self.application(from: notification) else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isStarted else { return }
                self.update(application, isHidden: false)
                self.publishProjection()
            }
        })
    }

    private func handleAdmissionCandidate(
        _ application: NSRunningApplication,
        publishImmediately: Bool = true
    ) {
        if upsert(application) {
            cancelPolicyRecheck(forPID: application.processIdentifier)
            if publishImmediately {
                publishProjection()
            }
            return
        }

        guard application.activationPolicy != .regular,
              let identity = processIdentity(for: application) else { return }
        let removedStaleProcess = evictStaleProcessState(for: identity)
        schedulePolicyRechecks(for: application, identity: identity)
        if removedStaleProcess, publishImmediately {
            publishProjection()
        }
    }

    @discardableResult
    private func upsert(
        _ application: NSRunningApplication,
        expectedIdentity: ProcessIdentity? = nil
    ) -> Bool {
        guard application.activationPolicy == .regular,
              let identity = processIdentity(for: application),
              expectedIdentity == nil || expectedIdentity == identity else { return false }
        evictStaleProcessState(for: identity)
        cancelTerminationRecheck(forPID: application.processIdentifier)
        processesByPID[application.processIdentifier] = ProcessState(
            identity: identity,
            bundleID: identity.bundleID,
            isHidden: application.isHidden
        )
        return true
    }

    @discardableResult
    private func evictStaleProcessState(for identity: ProcessIdentity) -> Bool {
        let pid = identity.generation.pid
        guard let state = processesByPID[pid],
              state.identity.generation != identity.generation else { return false }
        processesByPID.removeValue(forKey: pid)
        return true
    }

    private func update(_ application: NSRunningApplication, isHidden: Bool) {
        let pid = application.processIdentifier
        guard application.activationPolicy == .regular,
              let identity = processIdentity(for: application) else {
            processesByPID.removeValue(forKey: pid)
            return
        }

        if var state = processesByPID[pid] {
            guard state.identity == identity else { return }
            state.isHidden = isHidden
            processesByPID[pid] = state
            return
        }
        processesByPID[pid] = ProcessState(
            identity: identity,
            bundleID: identity.bundleID,
            isHidden: isHidden
        )
    }

    private func handleTermination(_ application: NSRunningApplication) {
        let pid = application.processIdentifier
        let currentGeneration = processGeneration(pid: pid)

        guard let currentGeneration else {
            processesByPID.removeValue(forKey: pid)
            cancelPolicyRecheck(forPID: pid)
            cancelTerminationRecheck(forPID: pid)
            return
        }

        if let state = processesByPID[pid], state.identity.generation != currentGeneration {
            processesByPID.removeValue(forKey: pid)
        }

        if let recheck = policyRechecksByPID[pid],
           recheck.identity.generation != currentGeneration || recheck.application === application {
            cancelPolicyRecheck(forPID: pid)
        }

        guard processesByPID[pid]?.identity.generation == currentGeneration else {
            cancelTerminationRecheck(forPID: pid)
            return
        }
        scheduleTerminationRechecks(pid: pid, generation: currentGeneration)
    }

    private func schedulePolicyRechecks(
        for application: NSRunningApplication,
        identity: ProcessIdentity
    ) {
        let pid = identity.generation.pid
        cancelTerminationRecheck(forPID: pid)
        if var existing = policyRechecksByPID[pid], existing.identity == identity {
            existing.application = application
            policyRechecksByPID[pid] = existing
            return
        }

        cancelPolicyRecheck(forPID: pid)
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            for sleepNanoseconds in Self.policyRecheckSleepNanoseconds {
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    return
                }

                guard let self else { return }
                guard self.recheckPolicy(identity: identity, token: token) else { return }
            }
            self?.cancelPolicyRecheck(forPID: pid, token: token)
        }
        policyRechecksByPID[pid] = PolicyRecheck(
            identity: identity,
            token: token,
            application: application,
            task: task
        )
    }

    /// Returns true while the bounded retry sequence should continue.
    private func recheckPolicy(identity: ProcessIdentity, token: UUID) -> Bool {
        let pid = identity.generation.pid
        guard isStarted,
              let recheck = policyRechecksByPID[pid],
              recheck.token == token,
              recheck.identity == identity,
              processGeneration(pid: pid) == identity.generation,
              recheck.application.processIdentifier == pid,
              recheck.application.bundleIdentifier == identity.bundleID else {
            cancelPolicyRecheck(forPID: pid, token: token)
            return false
        }

        guard recheck.application.activationPolicy == .regular else { return true }
        guard upsert(recheck.application, expectedIdentity: identity) else {
            cancelPolicyRecheck(forPID: pid, token: token)
            return false
        }

        cancelPolicyRecheck(forPID: pid, token: token)
        publishProjection()
        return false
    }

    private func scheduleTerminationRechecks(pid: pid_t, generation: ProcessGeneration) {
        if terminationRechecksByPID[pid]?.generation == generation { return }

        cancelTerminationRecheck(forPID: pid)
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            for sleepNanoseconds in Self.terminationRecheckSleepNanoseconds {
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    return
                }

                guard let self else { return }
                guard self.recheckTermination(generation: generation, token: token) else { return }
            }
            // A didTerminate notification can precede POSIX disappearance while an app
            // performs a long shutdown. Keep a very cheap liveness check until that exact
            // process generation is gone; otherwise the running projection can stay stale
            // forever because there will be no second termination notification.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.terminationSlowRecheckNanoseconds)
                } catch {
                    return
                }
                guard let self else { return }
                guard self.recheckTermination(generation: generation, token: token) else { return }
            }
        }
        terminationRechecksByPID[pid] = TerminationRecheck(
            generation: generation,
            token: token,
            task: task
        )
    }

    /// Returns true while the bounded liveness recheck sequence should continue.
    private func recheckTermination(generation: ProcessGeneration, token: UUID) -> Bool {
        let pid = generation.pid
        guard isStarted,
              let recheck = terminationRechecksByPID[pid],
              recheck.token == token,
              recheck.generation == generation else {
            cancelTerminationRecheck(forPID: pid, token: token)
            return false
        }

        guard processGeneration(pid: pid) == generation else {
            if processesByPID[pid]?.identity.generation == generation {
                processesByPID.removeValue(forKey: pid)
                publishProjection()
            }
            cancelTerminationRecheck(forPID: pid, token: token)
            return false
        }
        return true
    }

    private func processIdentity(for application: NSRunningApplication) -> ProcessIdentity? {
        guard let bundleID = application.bundleIdentifier, !bundleID.isEmpty,
              let generation = processGeneration(pid: application.processIdentifier) else { return nil }
        return ProcessIdentity(generation: generation, bundleID: bundleID)
    }

    private func processGeneration(pid: pid_t) -> ProcessGeneration? {
        guard ProcessLiveness.isAlive(pid: pid),
              let startTime = ProcessLiveness.startTime(pid: pid) else { return nil }
        return ProcessGeneration(
            pid: pid,
            startTimeSeconds: Int64(startTime.tv_sec),
            startTimeMicroseconds: Int64(startTime.tv_usec)
        )
    }

    private func cancelPolicyRecheck(forPID pid: pid_t, token: UUID? = nil) {
        guard let recheck = policyRechecksByPID[pid],
              token == nil || recheck.token == token else { return }
        policyRechecksByPID.removeValue(forKey: pid)
        recheck.task.cancel()
    }

    private func cancelAllPolicyRechecks() {
        let rechecks = Array(policyRechecksByPID.values)
        policyRechecksByPID.removeAll()
        for recheck in rechecks {
            recheck.task.cancel()
        }
    }

    private func cancelTerminationRecheck(forPID pid: pid_t, token: UUID? = nil) {
        guard let recheck = terminationRechecksByPID[pid],
              token == nil || recheck.token == token else { return }
        terminationRechecksByPID.removeValue(forKey: pid)
        recheck.task.cancel()
    }

    private func cancelAllTerminationRechecks() {
        let rechecks = Array(terminationRechecksByPID.values)
        terminationRechecksByPID.removeAll()
        for recheck in rechecks {
            recheck.task.cancel()
        }
    }

    private func publishProjection() {
        let grouped = Dictionary(grouping: processesByPID.values, by: \ProcessState.bundleID)
        let nextRunning = Set(grouped.keys)
        let nextHidden = Set(grouped.compactMap { bundleID, processes in
            processes.allSatisfy(\.isHidden) ? bundleID : nil
        })

        if runningBundleIDs != nextRunning {
            runningBundleIDs = nextRunning
        }
        if hiddenBundleIDs != nextHidden {
            hiddenBundleIDs = nextHidden
        }
    }

    private nonisolated static func application(from notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }
}
