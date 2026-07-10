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

    private struct ProcessState: Equatable {
        let bundleID: String
        var isHidden: Bool
    }

    private let workspace: NSWorkspace
    private var processesByPID: [pid_t: ProcessState] = [:]
    private var observers: [NSObjectProtocol] = []
    private var isStarted = false

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    deinit {
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
            upsert(application)
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
                self.upsert(application)
                self.publishProjection()
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
                self.processesByPID.removeValue(forKey: application.processIdentifier)
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

    private func upsert(_ application: NSRunningApplication) {
        guard application.activationPolicy == .regular,
              application.isTerminated == false,
              let bundleID = application.bundleIdentifier,
              !bundleID.isEmpty else { return }
        processesByPID[application.processIdentifier] = ProcessState(
            bundleID: bundleID,
            isHidden: application.isHidden
        )
    }

    private func update(_ application: NSRunningApplication, isHidden: Bool) {
        let pid = application.processIdentifier
        guard application.activationPolicy == .regular,
              application.isTerminated == false,
              let bundleID = application.bundleIdentifier,
              !bundleID.isEmpty else {
            processesByPID.removeValue(forKey: pid)
            return
        }

        if var state = processesByPID[pid] {
            state.isHidden = isHidden
            processesByPID[pid] = state
            return
        }
        processesByPID[pid] = ProcessState(bundleID: bundleID, isHidden: isHidden)
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
