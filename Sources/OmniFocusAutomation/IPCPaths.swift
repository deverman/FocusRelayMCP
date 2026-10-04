import Foundation

struct IPCPaths {
    let baseURL: URL
    let requestsURL: URL
    let responsesURL: URL
    let locksURL: URL
    let dispatchURL: URL

    init(baseURL: URL) {
        self.baseURL = baseURL
        self.requestsURL = baseURL.appendingPathComponent("requests", isDirectory: true)
        self.responsesURL = baseURL.appendingPathComponent("responses", isDirectory: true)
        self.locksURL = baseURL.appendingPathComponent("locks", isDirectory: true)
        self.dispatchURL = baseURL.appendingPathComponent("dispatch", isDirectory: true)
    }

    /// Resolves the fixed IPC location inside the OmniFocus 4 container.
    /// The bridge plug-in can only write inside that container, so there is no
    /// usable fallback location: when the container is absent the bridge can
    /// never answer, and failing fast beats a silent response timeout.
    static func resolve(
        fileManager: FileManager = .default,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> IPCPaths {
        let containerData = home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Containers", isDirectory: true)
            .appendingPathComponent("com.omnigroup.OmniFocus4", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)

        guard fileManager.fileExists(atPath: containerData.path) else {
            throw AutomationError.executionFailed(
                "OmniFocus 4 container not found at ~/Library/Containers/com.omnigroup.OmniFocus4. "
                    + "Install OmniFocus 4 and launch it once, then retry."
            )
        }

        let base = containerData
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("FocusRelayIPC", isDirectory: true)
        return IPCPaths(baseURL: base)
    }
}

/// Public view of the IPC location for tooling (benchmark diagnostics) that
/// must not duplicate the container path.
public enum IPCEnvironment {
    public static func defaultBaseURL() throws -> URL {
        try IPCPaths.resolve().baseURL
    }
}
