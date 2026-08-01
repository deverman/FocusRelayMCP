import Foundation
import Testing
@testable import OmniFocusAutomation

private func makeTemporaryIPCPaths() throws -> IPCPaths {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("focusrelay-ipc-tests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let paths = IPCPaths(baseURL: base)
    for url in [paths.baseURL, paths.requestsURL, paths.responsesURL, paths.locksURL, paths.dispatchURL] {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    return paths
}

private func makeMaintenance(
    paths: IPCPaths,
    staleInterval: TimeInterval = 600,
    swiftVersion: String = "1.0.0-test"
) -> IPCMaintenance {
    IPCMaintenance(
        fileManager: .default,
        paths: paths,
        staleInterval: staleInterval,
        currentSwiftVersion: swiftVersion
    )
}

private func write(_ text: String, to url: URL, modified: Date? = nil) throws {
    try text.data(using: .utf8)!.write(to: url)
    if let modified {
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    }
}

private func posixPermissions(at url: URL) -> Int? {
    (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? Int
}

@Suite("IPC maintenance policy")
struct IPCMaintenancePolicyTests {
    @Test func outOfPolicyClassificationPurgesOrphansAndKeepsProtocolDirs() {
        #expect(!isOutOfPolicyIPCEntry(name: "requests"))
        #expect(!isOutOfPolicyIPCEntry(name: "responses"))
        #expect(!isOutOfPolicyIPCEntry(name: "locks"))
        #expect(!isOutOfPolicyIPCEntry(name: "dispatch"))
        #expect(!isOutOfPolicyIPCEntry(name: "bridge-version.json"))
        #expect(isOutOfPolicyIPCEntry(name: "logs"))
        #expect(isOutOfPolicyIPCEntry(name: "pid-12345"))
        #expect(isOutOfPolicyIPCEntry(name: "default"))
        #expect(isOutOfPolicyIPCEntry(name: "ABC123.trace.json"))
        #expect(isOutOfPolicyIPCEntry(name: "anything-unknown"))
    }

    @Test func staleFileDecisionRespectsInterval() {
        let now = Date()
        #expect(shouldDeleteStaleIPCFile(modified: now.addingTimeInterval(-601), now: now, staleInterval: 600))
        #expect(!shouldDeleteStaleIPCFile(modified: now.addingTimeInterval(-599), now: now, staleInterval: 600))
    }

    @Test func staleSweepThrottleSkipsRecentSweep() {
        let now = Date()
        #expect(shouldRunStaleSweep(lastSweep: nil, now: now, minimumInterval: 600))
        #expect(shouldRunStaleSweep(lastSweep: now.addingTimeInterval(-600), now: now, minimumInterval: 600))
        #expect(!shouldRunStaleSweep(lastSweep: now.addingTimeInterval(-1), now: now, minimumInterval: 600))
    }

    @Test func versionMarkerMismatchDetection() {
        let marker = IPCVersionMarker(
            schemaVersion: 1,
            swiftVersion: "0.12.0-beta",
            pluginVersion: "0.12.0-beta",
            updatedAt: Date()
        )
        #expect(bridgeVersionMarkerMatches(marker: marker, currentSwiftVersion: "0.12.0-beta"))
        #expect(!bridgeVersionMarkerMatches(marker: marker, currentSwiftVersion: "0.13.0-beta"))
        #expect(!bridgeVersionMarkerMatches(marker: nil, currentSwiftVersion: "0.12.0-beta"))
    }
}

@Suite("IPC maintenance filesystem behavior")
struct IPCMaintenanceBehaviorTests {
    @Test func startupPurgeRemovesOrphansAndPreservesFreshInFlightFiles() throws {
        let paths = try makeTemporaryIPCPaths()
        defer { try? FileManager.default.removeItem(at: paths.baseURL) }
        let fm = FileManager.default

        // Establish the marker first so this run exercises the steady state,
        // not the first-run upgrade reset (covered by the version test).
        makeMaintenance(paths: paths).performStartupMaintenance()

        // Orphans at the top level.
        try fm.createDirectory(at: paths.baseURL.appendingPathComponent("pid-9999"), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.baseURL.appendingPathComponent("default"), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.baseURL.appendingPathComponent("logs"), withIntermediateDirectories: true)
        try write("{}", to: paths.baseURL.appendingPathComponent("ABC.trace.json"))
        // Fresh in-flight protocol file.
        let inflight = paths.requestsURL.appendingPathComponent("fresh.json")
        try write("{}", to: inflight)

        makeMaintenance(paths: paths).performStartupMaintenance()

        let remaining = Set(try fm.contentsOfDirectory(atPath: paths.baseURL.path))
        #expect(!remaining.contains("pid-9999"))
        #expect(!remaining.contains("default"))
        #expect(!remaining.contains("logs"))
        #expect(!remaining.contains("ABC.trace.json"))
        #expect(fm.fileExists(atPath: inflight.path),
                "fresh in-flight files must survive maintenance when the version matches")
        #expect(remaining.contains("bridge-version.json"), "startup maintenance writes the version marker")
    }

    @Test func startupResetOnVersionMismatchClearsProtocolDirs() throws {
        let paths = try makeTemporaryIPCPaths()
        defer { try? FileManager.default.removeItem(at: paths.baseURL) }
        let fm = FileManager.default

        // A missing marker means the directory predates hardening — treated
        // as an upgrade, so the first run resets the protocol dirs.
        let preHardening = paths.responsesURL.appendingPathComponent("old.json")
        try write("{}", to: preHardening)
        makeMaintenance(paths: paths, swiftVersion: "1.0.0").performStartupMaintenance()
        #expect(!fm.fileExists(atPath: preHardening.path),
                "missing marker must be treated as an upgrade and reset protocol dirs")

        // Same version again: fresh protocol files survive.
        let kept = paths.responsesURL.appendingPathComponent("kept.json")
        try write("{}", to: kept)
        makeMaintenance(paths: paths, swiftVersion: "1.0.0").performStartupMaintenance()
        #expect(fm.fileExists(atPath: kept.path), "matching version must not reset protocol dirs")

        // Version bump: protocol dirs are cleared exactly once.
        makeMaintenance(paths: paths, swiftVersion: "2.0.0").performStartupMaintenance()
        #expect(!fm.fileExists(atPath: kept.path), "version mismatch must clear protocol dirs")

        let maintenance = makeMaintenance(paths: paths, swiftVersion: "2.0.0")
        #expect(maintenance.readMarker()?.swiftVersion == "2.0.0")
    }

    @Test func pluginVersionChangeResetsProtocolDirsOnce() throws {
        let paths = try makeTemporaryIPCPaths()
        defer { try? FileManager.default.removeItem(at: paths.baseURL) }
        let fm = FileManager.default
        let maintenance = makeMaintenance(paths: paths)
        maintenance.performStartupMaintenance()

        // First observation records the version without a reset.
        let beforeFirst = paths.responsesURL.appendingPathComponent("a.json")
        try write("{}", to: beforeFirst)
        maintenance.recordObservedPluginVersion("1.0.0")
        #expect(fm.fileExists(atPath: beforeFirst.path), "first plugin observation must not reset")
        #expect(maintenance.readMarker()?.pluginVersion == "1.0.0")

        // Same version again: no reset.
        maintenance.recordObservedPluginVersion("1.0.0")
        #expect(fm.fileExists(atPath: beforeFirst.path))

        // Changed version: reset once.
        maintenance.recordObservedPluginVersion("2.0.0")
        #expect(!fm.fileExists(atPath: beforeFirst.path), "plugin version change must reset protocol dirs")
        #expect(maintenance.readMarker()?.pluginVersion == "2.0.0")
    }

    @Test func maintenanceAssertsOwnerOnlyDirectoryPermissions() throws {
        let paths = try makeTemporaryIPCPaths()
        defer { try? FileManager.default.removeItem(at: paths.baseURL) }
        // Simulate pre-hardening world-readable directories.
        for url in [paths.baseURL, paths.requestsURL, paths.responsesURL, paths.locksURL, paths.dispatchURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }

        makeMaintenance(paths: paths).performStartupMaintenance()

        for url in [paths.baseURL, paths.requestsURL, paths.responsesURL, paths.locksURL, paths.dispatchURL] {
            #expect(posixPermissions(at: url) == 0o700, "\(url.lastPathComponent) must be owner-only")
        }
        let marker = paths.baseURL.appendingPathComponent(ipcVersionMarkerFileName)
        #expect(posixPermissions(at: marker) == 0o600, "marker must be owner-only")
    }

    @Test func sweepIncludesDispatchDirectory() throws {
        let paths = try makeTemporaryIPCPaths()
        defer { try? FileManager.default.removeItem(at: paths.baseURL) }
        let fm = FileManager.default
        let old = Date().addingTimeInterval(-3600)

        let staleDispatch = paths.dispatchURL.appendingPathComponent("request.json")
        let staleResponse = paths.responsesURL.appendingPathComponent("stale.json")
        let freshRequest = paths.requestsURL.appendingPathComponent("fresh.json")
        try write("{}", to: staleDispatch, modified: old)
        try write("{}", to: staleResponse, modified: old)
        try write("{}", to: freshRequest)

        makeMaintenance(paths: paths).sweepStaleFiles()

        #expect(!fm.fileExists(atPath: staleDispatch.path), "dispatch/ must be swept")
        #expect(!fm.fileExists(atPath: staleResponse.path))
        #expect(fm.fileExists(atPath: freshRequest.path))
    }

    @Test func resolveThrowsActionableErrorWithoutOmniFocusContainer() throws {
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("focusrelay-fake-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        #expect {
            _ = try IPCPaths.resolve(home: fakeHome)
        } throws: { error in
            guard case let AutomationError.executionFailed(message) = error else { return false }
            return message.contains("OmniFocus 4") && message.contains("Install")
        }
    }

    @Test func resolveReturnsContainerPathWhenPresent() throws {
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("focusrelay-fake-home-\(UUID().uuidString)", isDirectory: true)
        let containerData = fakeHome
            .appendingPathComponent("Library/Containers/com.omnigroup.OmniFocus4/Data", isDirectory: true)
        try FileManager.default.createDirectory(at: containerData, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        let paths = try IPCPaths.resolve(home: fakeHome)
        #expect(paths.baseURL.path.hasSuffix("Data/Documents/FocusRelayIPC"))
    }
}

@Suite("BridgeClient response consumption")
struct BridgeClientResponseConsumptionTests {
    @Test func successfulDecodeRemovesResponseRequestAndLock() throws {
        let paths = try makeTemporaryIPCPaths()
        defer { try? FileManager.default.removeItem(at: paths.baseURL) }
        let fm = FileManager.default

        let client = BridgeClient(paths: paths)
        // Simulated plugin: answer every dispatched request with a valid ping
        // response, exercising the real sendRequest/waitForResponse path
        // without launching OmniFocus.
        client.dispatchHandlerForTesting = { requestId in
            let response = #"{"schemaVersion":1,"requestId":"\#(requestId)","ok":true,"data":{"ok":true,"plugin":"FocusRelay Bridge","version":"1.0.0-test"}}"#
            try response.data(using: .utf8)!.write(
                to: paths.responsesURL.appendingPathComponent("\(requestId).json")
            )
        }

        let response = try client.ping()
        #expect(response.ok)
        #expect(response.data?.version == "1.0.0-test")

        for directory in [paths.requestsURL, paths.responsesURL, paths.locksURL] {
            let entries = try fm.contentsOfDirectory(atPath: directory.path)
            #expect(entries.isEmpty, "\(directory.lastPathComponent) must hold no artifacts after a successful call")
        }
        let dispatchEntries = try fm.contentsOfDirectory(atPath: paths.dispatchURL.path)
        #expect(dispatchEntries.isEmpty, "dispatch/request.json must be removed after a successful call")
    }

    @Test func timeoutPathRetainsArtifacts() throws {
        let paths = try makeTemporaryIPCPaths()
        defer { try? FileManager.default.removeItem(at: paths.baseURL) }
        let fm = FileManager.default

        let client = BridgeClient(
            paths: paths,
            configuration: BridgeClientConfiguration(responseTimeout: 0.3, responsePollInterval: 0.02)
        )
        // Simulated stuck plugin: write the lock so redispatch/late-recovery
        // stay off, then never answer.
        client.dispatchHandlerForTesting = { requestId in
            let lockURL = paths.locksURL.appendingPathComponent("\(requestId).lock")
            if !fm.fileExists(atPath: lockURL.path) {
                try Data("{}".utf8).write(to: lockURL)
            }
        }

        #expect(throws: AutomationError.self) {
            _ = try client.ping()
        }
        let requestEntries = try fm.contentsOfDirectory(atPath: paths.requestsURL.path)
        #expect(!requestEntries.isEmpty, "timeout must retain the request for late-arrival recovery")
    }

    @Test func requestFilesAreWrittenOwnerOnly() throws {
        let paths = try makeTemporaryIPCPaths()
        defer { try? FileManager.default.removeItem(at: paths.baseURL) }

        let client = BridgeClient(paths: paths)
        var observedRequestMode: Int?
        client.dispatchHandlerForTesting = { requestId in
            let requestURL = paths.requestsURL.appendingPathComponent("\(requestId).json")
            observedRequestMode = posixPermissions(at: requestURL)
            let response = #"{"schemaVersion":1,"requestId":"\#(requestId)","ok":true,"data":{"ok":true,"plugin":"FocusRelay Bridge","version":"1.0.0-test"}}"#
            try response.data(using: .utf8)!.write(
                to: paths.responsesURL.appendingPathComponent("\(requestId).json")
            )
        }

        _ = try client.ping()
        #expect(observedRequestMode == 0o600, "request payloads must be owner-only on disk")
    }
}
