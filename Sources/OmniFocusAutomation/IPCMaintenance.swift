import Foundation

/// Names allowed at the top level of the IPC base directory. Anything else is
/// debris from an older build and is purged during startup maintenance.
let ipcAllowedTopLevelNames: Set<String> = [
    "requests",
    "responses",
    "locks",
    "dispatch",
    ipcVersionMarkerFileName
]

let ipcVersionMarkerFileName = "bridge-version.json"

func isOutOfPolicyIPCEntry(name: String) -> Bool {
    !ipcAllowedTopLevelNames.contains(name)
}

func shouldDeleteStaleIPCFile(modified: Date, now: Date, staleInterval: TimeInterval) -> Bool {
    now.timeIntervalSince(modified) > staleInterval
}

func shouldRunStaleSweep(lastSweep: Date?, now: Date, minimumInterval: TimeInterval) -> Bool {
    guard let lastSweep else { return true }
    return now.timeIntervalSince(lastSweep) >= minimumInterval
}

func bridgeVersionMarkerMatches(marker: IPCVersionMarker?, currentSwiftVersion: String) -> Bool {
    marker?.swiftVersion == currentSwiftVersion
}

struct IPCVersionMarker: Codable, Equatable {
    var schemaVersion: Int
    var swiftVersion: String
    var pluginVersion: String?
    var updatedAt: Date
}

/// Owns the impure IPC directory operations: one-time startup purge, throttled
/// stale sweeps, permission repair, and the upgrade-invalidation marker.
/// Pure decision logic stays in the free functions above so it is testable
/// without a filesystem.
struct IPCMaintenance {
    let fileManager: FileManager
    let paths: IPCPaths
    let staleInterval: TimeInterval
    let currentSwiftVersion: String

    private static var ownerOnlyDirectory: [FileAttributeKey: Any] { [.posixPermissions: 0o700] }
    private static var ownerOnlyFile: [FileAttributeKey: Any] { [.posixPermissions: 0o600] }

    private var protocolDirectories: [URL] {
        [paths.requestsURL, paths.responsesURL, paths.locksURL, paths.dispatchURL]
    }

    private var markerURL: URL {
        paths.baseURL.appendingPathComponent(ipcVersionMarkerFileName)
    }

    /// Runs once per process before the first bridge request: purges debris,
    /// resets the protocol directories when the binary version changed, and
    /// repairs permissions.
    func performStartupMaintenance(now: Date = Date()) {
        purgeOutOfPolicyEntries()
        if !bridgeVersionMarkerMatches(marker: readMarker(), currentSwiftVersion: currentSwiftVersion) {
            resetProtocolDirectories()
            writeMarker(pluginVersion: nil, now: now)
        }
        sweepStaleFiles(now: now)
        assertOwnerOnlyPermissions()
    }

    /// Called when a bridge health check observes the plugin version. Resets
    /// the protocol directories once when the plugin changed underneath us.
    func recordObservedPluginVersion(_ pluginVersion: String, now: Date = Date()) {
        let marker = readMarker()
        guard marker?.pluginVersion != pluginVersion else { return }
        if marker?.pluginVersion != nil {
            resetProtocolDirectories()
        }
        writeMarker(pluginVersion: pluginVersion, now: now)
    }

    /// Deletes protocol files older than `staleInterval` in every protocol
    /// directory, including `dispatch/`.
    func sweepStaleFiles(now: Date = Date()) {
        for directory in protocolDirectories {
            guard let items = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for url in items {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate else { continue }
                if shouldDeleteStaleIPCFile(modified: modified, now: now, staleInterval: staleInterval) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }

    /// Removes every top-level entry that is not part of the IPC protocol:
    /// legacy `pid-*` trees, `default/`, trace files, and the retired `logs/`
    /// directory. Never touches the protocol directories themselves.
    private func purgeOutOfPolicyEntries() {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: paths.baseURL,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in entries where isOutOfPolicyIPCEntry(name: url.lastPathComponent) {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Clears the contents of the protocol directories without removing the
    /// directories themselves, so in-flight path handles stay valid.
    private func resetProtocolDirectories() {
        for directory in protocolDirectories {
            guard let items = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) else { continue }
            for url in items {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func assertOwnerOnlyPermissions() {
        for url in [paths.baseURL] + protocolDirectories {
            try? fileManager.setAttributes(Self.ownerOnlyDirectory, ofItemAtPath: url.path)
        }
        if fileManager.fileExists(atPath: markerURL.path) {
            try? fileManager.setAttributes(Self.ownerOnlyFile, ofItemAtPath: markerURL.path)
        }
    }

    func readMarker() -> IPCVersionMarker? {
        guard let data = try? Data(contentsOf: markerURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(IPCVersionMarker.self, from: data)
    }

    private func writeMarker(pluginVersion: String?, now: Date) {
        let preservedPluginVersion = pluginVersion ?? readMarker()?.pluginVersion
        let marker = IPCVersionMarker(
            schemaVersion: 1,
            swiftVersion: currentSwiftVersion,
            pluginVersion: preservedPluginVersion,
            updatedAt: now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(marker) else { return }
        try? data.write(to: markerURL, options: .atomic)
        try? fileManager.setAttributes(Self.ownerOnlyFile, ofItemAtPath: markerURL.path)
    }
}
