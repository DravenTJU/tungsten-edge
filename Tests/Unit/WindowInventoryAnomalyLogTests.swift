import Foundation
import XCTest

final class WindowInventoryAnomalyLogTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDown() {
        roots.forEach { try? FileManager.default.removeItem(at: $0) }
        roots.removeAll()
        super.tearDown()
    }

    func testEnablementDefaultsOffAndEnvironmentOverridesDefaults() {
        let suite = "WindowInventoryAnomalyLogTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(WindowInventoryLogConfiguration.resolvedEnabled(environment: [:], defaults: defaults))
        defaults.set(false, forKey: WindowInventoryLogConfiguration.defaultsKey)
        XCTAssertFalse(WindowInventoryLogConfiguration.resolvedEnabled(environment: [:], defaults: defaults))
        defaults.set(true, forKey: WindowInventoryLogConfiguration.defaultsKey)
        XCTAssertTrue(WindowInventoryLogConfiguration.resolvedEnabled(environment: [:], defaults: defaults))
        XCTAssertFalse(WindowInventoryLogConfiguration.resolvedEnabled(
            environment: ["DOCK_INVENTORY_LOG": "0"], defaults: defaults
        ))
        defaults.set(false, forKey: WindowInventoryLogConfiguration.defaultsKey)
        XCTAssertTrue(WindowInventoryLogConfiguration.resolvedEnabled(
            environment: ["DOCK_INVENTORY_LOG": "1"], defaults: defaults
        ))
        XCTAssertFalse(WindowInventoryLogConfiguration.resolvedEnabled(
            environment: ["DOCK_INVENTORY_LOG": "other"], defaults: defaults
        ))
    }

    func testDisabledLoggerCreatesNoDirectory() {
        let root = makeRoot()
        let directory = root.appendingPathComponent("logs")
        let log = makeLogger(directory: directory, enabled: false)

        log.record(.sessionStart(sessionPayload()))
        log.flush()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testAppendsParseableJSONLinesWithMonotonicSequence() throws {
        let directory = makeRoot().appendingPathComponent("logs")
        let log = makeLogger(directory: directory)

        log.record(.sessionStart(sessionPayload()))
        log.record(.sessionStart(sessionPayload()))
        log.flush()

        let records = try jsonRecords(at: log.currentFileURL)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.compactMap { $0["seq"] as? Int }, [1, 2])
        XCTAssertEqual(records.compactMap { $0["schemaVersion"] as? Int }, [1, 1])
        XCTAssertEqual(records.compactMap { $0["event"] as? String }, ["sessionStart", "sessionStart"])
        XCTAssertEqual(Set(records.compactMap { $0["sessionID"] as? String }).count, 1)
    }

    func testConcurrentWritersDoNotInterleaveLines() throws {
        let directory = makeRoot().appendingPathComponent("logs")
        let first = makeLogger(directory: directory, maxFileSize: 1_000_000)
        let second = makeLogger(directory: directory, maxFileSize: 1_000_000)
        let group = DispatchGroup()
        let payload = sessionPayload()

        for index in 0..<80 {
            group.enter()
            DispatchQueue.global().async {
                (index.isMultiple(of: 2) ? first : second).record(.sessionStart(payload))
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        first.flush()
        second.flush()

        XCTAssertEqual(try jsonRecords(at: first.currentFileURL).count, 80)
    }

    func testRepairsPartialTailBeforeAppending() throws {
        let directory = makeRoot().appendingPathComponent("logs")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("window-inventory.jsonl")
        try Data("{partial".utf8).write(to: file)
        let log = makeLogger(directory: directory)

        log.record(.sessionStart(sessionPayload()))
        log.flush()

        XCTAssertEqual(try jsonRecords(at: file).count, 1)
    }

    func testExactThresholdDoesNotRotateAndNextLineDoes() throws {
        let directory = makeRoot().appendingPathComponent("logs")
        let seed = makeLogger(directory: directory, maxFileSize: 1_000_000)
        seed.record(.sessionStart(sessionPayload()))
        seed.flush()
        let lineSize = try fileSize(seed.currentFileURL)

        let boundary = makeLogger(directory: directory, maxFileSize: lineSize * 2)
        boundary.record(.sessionStart(sessionPayload()))
        boundary.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: boundary.archiveURL(1).path))
        XCTAssertEqual(try fileSize(boundary.currentFileURL), lineSize * 2)

        boundary.record(.sessionStart(sessionPayload()))
        boundary.flush()
        XCTAssertTrue(FileManager.default.fileExists(atPath: boundary.archiveURL(1).path))
        XCTAssertEqual(try jsonRecords(at: boundary.currentFileURL).count, 1)
    }

    func testRotationKeepsCurrentAndFourArchives() {
        let directory = makeRoot().appendingPathComponent("logs")
        let log = makeLogger(directory: directory, maxFileSize: 1)

        for _ in 0..<8 { log.record(.sessionStart(sessionPayload())) }
        log.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: log.currentFileURL.path))
        for index in 1...4 {
            XCTAssertTrue(FileManager.default.fileExists(atPath: log.archiveURL(index).path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.archiveURL(5).path))
    }

    func testPermissionsArePrivate() throws {
        let directory = makeRoot().appendingPathComponent("logs")
        let log = makeLogger(directory: directory)
        log.record(.sessionStart(sessionPayload()))
        log.flush()

        let directoryMode = try posixPermissions(directory)
        let fileMode = try posixPermissions(log.currentFileURL)
        let lockMode = try posixPermissions(log.lockFileURL)
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        XCTAssertEqual(fileMode & 0o777, 0o600)
        XCTAssertEqual(lockMode & 0o777, 0o600)
    }

    func testFirstWriteFailureDisablesSessionAndReportsOnce() throws {
        let root = makeRoot()
        let blocker = root.appendingPathComponent("blocker")
        try Data("file".utf8).write(to: blocker)
        let badDirectory = blocker.appendingPathComponent("logs")
        let lock = NSLock()
        var failures = 0
        let log = makeLogger(directory: badDirectory, failureReporter: { _ in
            lock.lock()
            failures += 1
            lock.unlock()
        })

        log.record(.sessionStart(sessionPayload()))
        log.record(.sessionStart(sessionPayload()))
        log.flush()

        XCTAssertEqual(failures, 1)
    }

    func testAbsenceEpisodeUsesAbsentSinceBoundary() {
        var absentSince: Date?
        var episodeID: UUID?
        let firstID = UUID()
        let secondID = UUID()
        let now = Date(timeIntervalSince1970: 100)

        InventoryAbsenceEpisode.beginIfNeeded(
            absentSince: &absentSince, episodeID: &episodeID, now: now, makeID: { firstID }
        )
        XCTAssertEqual(absentSince, now)
        XCTAssertEqual(episodeID, firstID)

        InventoryAbsenceEpisode.beginIfNeeded(
            absentSince: &absentSince, episodeID: &episodeID,
            now: now.addingTimeInterval(5), makeID: { XCTFail("must preserve episode"); return secondID }
        )
        XCTAssertEqual(absentSince, now)
        XCTAssertEqual(episodeID, firstID)

        InventoryAbsenceEpisode.clear(absentSince: &absentSince, episodeID: &episodeID)
        XCTAssertNil(absentSince)
        XCTAssertNil(episodeID)

        InventoryAbsenceEpisode.beginIfNeeded(
            absentSince: &absentSince, episodeID: &episodeID,
            now: now.addingTimeInterval(20), makeID: { secondID }
        )
        XCTAssertEqual(episodeID, secondID)
    }

    func testPhantomHeldDeduplicatorRecordsReasonChangesAndNewEpisodes() {
        var deduplicator = InventoryPhantomHeldDeduplicator()
        let first = UUID()
        let second = UUID()
        let visible: Set<PhantomSeatDecision.HoldReason> = [.everSeenVisible]
        let twoReasons: Set<PhantomSeatDecision.HoldReason> = [.everSeenVisible, .noAXPresentSibling]

        XCTAssertTrue(deduplicator.shouldRecord(pid: 1, seatToken: "seat-a", episodeID: first, reasons: visible))
        XCTAssertFalse(deduplicator.shouldRecord(pid: 1, seatToken: "seat-a", episodeID: first, reasons: visible))
        XCTAssertTrue(deduplicator.shouldRecord(pid: 1, seatToken: "seat-a", episodeID: first, reasons: twoReasons))
        XCTAssertTrue(deduplicator.shouldRecord(pid: 1, seatToken: "seat-a", episodeID: second, reasons: visible))
        XCTAssertTrue(deduplicator.shouldRecord(pid: 1, seatToken: "seat-b", episodeID: first, reasons: visible))
        XCTAssertTrue(deduplicator.shouldRecord(pid: 2, seatToken: "seat-a", episodeID: first, reasons: visible))
        deduplicator.clear(pid: 1, seatToken: "seat-a", episodeID: first)
        XCTAssertTrue(deduplicator.shouldRecord(pid: 1, seatToken: "seat-a", episodeID: first, reasons: visible))
    }

    func testTitleRelationIsNormalizedWithoutPersistingTitle() {
        XCTAssertTrue(WindowInventoryDiagnosticRelations.normalizedTitlesMatch(
            " Review\u{200B} Window ", "review window"
        ))
        XCTAssertFalse(WindowInventoryDiagnosticRelations.normalizedTitlesMatch("", ""))
        XCTAssertFalse(WindowInventoryDiagnosticRelations.normalizedTitlesMatch("One", "Two"))
    }

    func testAllSeatCreationReasons() {
        XCTAssertEqual(
            InventorySeatCreationReason.classify(
                hasPlacedSeat: false, isTearOut: false, isMinimized: true, isOnScreen: false
            ),
            .firstSeat
        )
        XCTAssertEqual(
            InventorySeatCreationReason.classify(
                hasPlacedSeat: true, isTearOut: true, isMinimized: false, isOnScreen: true
            ),
            .tearOut
        )
        XCTAssertEqual(
            InventorySeatCreationReason.classify(
                hasPlacedSeat: true, isTearOut: false, isMinimized: true, isOnScreen: false
            ),
            .minimizedFoldMiss
        )
        XCTAssertEqual(
            InventorySeatCreationReason.classify(
                hasPlacedSeat: true, isTearOut: false, isMinimized: false, isOnScreen: false
            ),
            .offscreenNonMinimized
        )
        XCTAssertEqual(
            InventorySeatCreationReason.classify(
                hasPlacedSeat: true, isTearOut: false, isMinimized: false, isOnScreen: true
            ),
            .visibleUnclaimed
        )
    }

    func testPhantomOwnerRequiresExactlyOneCandidate() {
        let first = InventoryPhantomOwner(seatToken: "seat-a", activeCgID: 10)
        let second = InventoryPhantomOwner(seatToken: "seat-b", activeCgID: 20)

        XCTAssertNil(InventoryPhantomOwnerResolution.uniqueOwner(from: []))
        XCTAssertEqual(InventoryPhantomOwnerResolution.uniqueOwner(from: [first]), first)
        XCTAssertNil(InventoryPhantomOwnerResolution.uniqueOwner(from: [first, second]))
    }

    private func makeLogger(
        directory: URL,
        enabled: Bool = true,
        maxFileSize: Int = 1_000_000,
        archiveCount: Int = 4,
        failureReporter: ((String) -> Void)? = nil
    ) -> WindowInventoryAnomalyLog {
        WindowInventoryAnomalyLog(
            configuration: WindowInventoryLogConfiguration(
                enabled: enabled,
                directoryURL: directory,
                maxFileSize: maxFileSize,
                archiveCount: archiveCount
            ),
            failureReporter: failureReporter
        )
    }

    private func sessionPayload() -> InventorySessionStartPayload {
        InventorySessionStartPayload(
            version: "1.0", build: "1", processID: 42, operatingSystem: "test"
        )
    }

    private func makeRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowInventoryAnomalyLogTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        roots.append(url)
        return url
    }

    private func jsonRecords(at url: URL) throws -> [[String: Any]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.split(separator: "\n").map { line in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        }
    }

    private func fileSize(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.size] as? NSNumber).intValue
    }

    private func posixPermissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }
}
