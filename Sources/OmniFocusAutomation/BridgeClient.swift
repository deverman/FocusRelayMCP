import Foundation
import FocusRelayVersion
import OmniFocusCore

final class BridgeClient: @unchecked Sendable {
    // Mutable state below is safe without locking: the #170 Bridge lane
    // serializes every request through one FIFO coordinator, so BridgeClient
    // never runs two requests concurrently.
    private var resolvedPaths: IPCPaths?
    private let injectedPaths: IPCPaths?
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let staleInterval: TimeInterval
    private let configuration: BridgeClientConfiguration
    private var didEnsureDirectories = false
    private var didRunStartupMaintenance = false
    private var lastStaleSweep: Date?
    var onResponseWarnings: (@Sendable (_ warnings: [String], _ op: String) -> Void)?
    /// Test seam: replaces the OmniFocus URL dispatch so unit tests can
    /// exercise the full request/response file lifecycle without launching
    /// OmniFocus. Production code never sets this.
    var dispatchHandlerForTesting: ((_ requestId: String) throws -> Void)?

    init(
        paths: IPCPaths? = nil,
        fileManager: FileManager = .default,
        staleInterval: TimeInterval = 600,
        configuration: BridgeClientConfiguration = .fromEnvironment(ProcessInfo.processInfo.environment)
    ) {
        self.injectedPaths = paths
        self.fileManager = fileManager
        self.staleInterval = staleInterval
        self.configuration = configuration
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        self.decoder = BridgeDateDecoding.makeJSONDecoder()
    }

    /// Resolution is deferred to first use so the MCP server starts on
    /// machines without OmniFocus and tool calls fail fast with an actionable
    /// error instead of timing out.
    static func projectItem(from payload: ProjectItemPayload) -> ProjectItem {
                let nextTask = payload.nextTask.map { ProjectTaskSummary(id: $0.id ?? "", name: $0.name ?? "") }
                let reviewInterval = payload.reviewInterval.map { ReviewInterval(steps: $0.steps, unit: $0.unit) }
                return ProjectItem(
                    id: payload.id ?? "",
                    name: payload.name ?? "",
                    note: payload.note,
                    status: payload.status ?? "",
                    flagged: payload.flagged ?? false,
                    lastReviewDate: payload.lastReviewDate,
                    nextReviewDate: payload.nextReviewDate,
                    reviewInterval: reviewInterval,
                    availableTasks: payload.availableTasks,
                    remainingTasks: payload.remainingTasks,
                    completedTasks: payload.completedTasks,
                    droppedTasks: payload.droppedTasks,
                    totalTasks: payload.totalTasks,
                    hasChildren: payload.hasChildren,
                    nextTask: nextTask,
                    containsSingletonActions: payload.containsSingletonActions,
                    isStalled: payload.isStalled,
                    completionDate: payload.completionDate,
                    folderID: payload.folderID,
                    folderName: payload.folderName,
                    folderPath: payload.folderPath.map { elements in
                        elements.map { FolderPathElement(id: $0.id ?? "", name: $0.name ?? "") }
                    }
                )
    }

    static func tagItem(from payload: TagItemPayload) -> TagItem {
        TagItem(
                    id: payload.id ?? "",
                    name: payload.name ?? "",
                    status: payload.status,
                    availableTasks: payload.availableTasks,
                    remainingTasks: payload.remainingTasks,
                    totalTasks: payload.totalTasks,
                    parentID: payload.parentID,
                    parentName: payload.parentName,
                    path: payload.path,
                    childrenAreMutuallyExclusive: payload.childrenAreMutuallyExclusive
                )
    }

    private func requirePaths() throws -> IPCPaths {
        if let resolvedPaths { return resolvedPaths }
        let paths = try injectedPaths ?? IPCPaths.resolve(fileManager: fileManager)
        resolvedPaths = paths
        return paths
    }

    private func makeMaintenance(paths: IPCPaths) -> IPCMaintenance {
        IPCMaintenance(
            fileManager: fileManager,
            paths: paths,
            staleInterval: staleInterval,
            currentSwiftVersion: FocusRelayBuildVersion.current
        )
    }

    /// Called by the health check when the plugin reports its version, so a
    /// plugin-only reinstall invalidates the IPC directory once.
    func recordObservedPluginVersion(_ version: String) {
        guard let paths = try? requirePaths() else { return }
        makeMaintenance(paths: paths).recordObservedPluginVersion(version)
    }

    func listTasks(filter: TaskFilter, page: PageRequest, fields: [String]?) throws -> Page<TaskItem> {
        let requestId = UUID().uuidString
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: requestId,
            op: "list_tasks",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: filter,
            tagFilter: nil,
            projectFilter: nil,
            mutation: nil,
            fields: fields,
            page: page
        )

        let response: BridgeResponse<Page<TaskItemPayload>> = try sendRequest(request, responseType: Page<TaskItemPayload>.self)

        if response.ok, let payloadPage = response.data {
            let items = payloadPage.items.map { payload in
                TaskItem(
                    id: payload.id ?? "",
                    name: payload.name ?? "",
                    note: payload.note,
                    projectID: payload.projectID,
                    projectName: payload.projectName,
                    tagIDs: payload.tagIDs ?? [],
                    tagNames: payload.tagNames ?? [],
                    dueDate: payload.dueDate,
                    plannedDate: payload.plannedDate,
                    deferDate: payload.deferDate,
                    completionDate: payload.completionDate,
                    completed: payload.completed ?? false,
                    flagged: payload.flagged ?? false,
                    effectiveFlagged: payload.effectiveFlagged,
                    estimatedMinutes: payload.estimatedMinutes,
                    available: payload.available ?? false
                )
            }
            return Page(items: items, nextCursor: payloadPage.nextCursor, returnedCount: payloadPage.returnedCount, totalCount: payloadPage.totalCount, warnings: response.warnings)
        }

        let message = response.error?.message ?? "Unknown bridge error"
        throw AutomationError.executionFailed(message)
    }

    func ping() throws -> BridgeResponse<BridgePing> {
        let requestId = UUID().uuidString
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: requestId,
            op: "ping",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: nil,
            tagFilter: nil,
            projectFilter: nil,
            mutation: nil,
            fields: nil,
            page: nil
        )

        return try sendRequest(request, responseType: BridgePing.self)
    }

    func listProjects(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool,
        search: String? = nil,
        rootOnly: Bool = false,
        reviewDueBefore: Date?,
        reviewDueAfter: Date?,
        reviewPerspective: Bool,
        completed: Bool?,
        completedBefore: Date?,
        completedAfter: Date?,
        fields: [String]?
    ) throws -> Page<ProjectItem> {
        let requestId = UUID().uuidString
        let projectFilter = ProjectFilter(
            rootOnly: rootOnly ? true : nil,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            search: search,
            reviewDueBefore: reviewDueBefore,
            reviewDueAfter: reviewDueAfter,
            reviewPerspective: reviewPerspective,
            completed: completed,
            completedBefore: completedBefore,
            completedAfter: completedAfter
        )
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: requestId,
            op: "list_projects",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: nil,
            tagFilter: nil,
            projectFilter: projectFilter,
            mutation: nil,
            fields: fields,
            page: page
        )

        let response: BridgeResponse<Page<ProjectItemPayload>> = try sendRequest(request, responseType: Page<ProjectItemPayload>.self)
        if response.ok, let payloadPage = response.data {
            let items = payloadPage.items.map(Self.projectItem(from:))
            return Page(items: items, nextCursor: payloadPage.nextCursor, returnedCount: payloadPage.returnedCount, totalCount: payloadPage.totalCount, warnings: response.warnings)
        }

        let message = response.error?.message ?? "Unknown bridge error"
        throw AutomationError.executionFailed(message)
    }

    func listTags(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool,
        search: String? = nil,
        fields: [String]? = nil
    ) throws -> Page<TagItem> {
        let requestId = UUID().uuidString
        let tagFilter = TagFilter(
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            search: search
        )
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: requestId,
            op: "list_tags",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: nil,
            tagFilter: tagFilter,
            projectFilter: nil,
            mutation: nil,
            fields: fields,
            page: page
        )

        let response: BridgeResponse<Page<TagItemPayload>> = try sendRequest(request, responseType: Page<TagItemPayload>.self)
        if response.ok, let payloadPage = response.data {
            let items = payloadPage.items.map(Self.tagItem(from:))
            return Page(items: items, nextCursor: payloadPage.nextCursor, returnedCount: payloadPage.returnedCount, totalCount: payloadPage.totalCount, warnings: response.warnings)
        }

        let message = response.error?.message ?? "Unknown bridge error"
        throw AutomationError.executionFailed(message)
    }

    func listFolders(page: PageRequest, fields: [String]?) throws -> Page<FolderItem> {
        let requestId = UUID().uuidString
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: requestId,
            op: "list_folders",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: nil,
            tagFilter: nil,
            projectFilter: nil,
            mutation: nil,
            fields: fields,
            page: page
        )

        let response: BridgeResponse<Page<FolderItemPayload>> = try sendRequest(request, responseType: Page<FolderItemPayload>.self)
        if response.ok, let payloadPage = response.data {
            let items = payloadPage.items.map { payload in
                FolderItem(
                    id: payload.id ?? "",
                    name: payload.name ?? "",
                    parentID: payload.parentID,
                    parentName: payload.parentName,
                    projectCount: payload.projectCount,
                    childFolderCount: payload.childFolderCount
                )
            }
            return Page(items: items, nextCursor: payloadPage.nextCursor, returnedCount: payloadPage.returnedCount, totalCount: payloadPage.totalCount, warnings: response.warnings)
        }

        let message = response.error?.message ?? "Unknown bridge error"
        throw AutomationError.executionFailed(message)
    }

    func getTask(id: String, fields: [String]?) throws -> TaskItem {
        let requestId = UUID().uuidString
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: requestId,
            op: "get_task",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: id,
            filter: nil,
            tagFilter: nil,
            projectFilter: nil,
            mutation: nil,
            fields: fields,
            page: nil
        )

        let response: BridgeResponse<TaskItemPayload> = try sendRequest(request, responseType: TaskItemPayload.self)
        if response.ok, let payload = response.data {
            return TaskItem(
                id: payload.id ?? "",
                name: payload.name ?? "",
                note: payload.note,
                projectID: payload.projectID,
                projectName: payload.projectName,
                tagIDs: payload.tagIDs ?? [],
                tagNames: payload.tagNames ?? [],
                dueDate: payload.dueDate,
                plannedDate: payload.plannedDate,
                deferDate: payload.deferDate,
                completionDate: payload.completionDate,
                completed: payload.completed ?? false,
                flagged: payload.flagged ?? false,
                effectiveFlagged: payload.effectiveFlagged,
                estimatedMinutes: payload.estimatedMinutes,
                available: payload.available ?? false
            )
        }

        let message = response.error?.message ?? "Unknown bridge error"
        throw AutomationError.executionFailed(message)
    }

    func getTaskCounts(filter: TaskFilter) throws -> TaskCounts {
        let requestId = UUID().uuidString
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: requestId,
            op: "get_task_counts",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: filter,
            tagFilter: nil,
            projectFilter: nil,
            mutation: nil,
            fields: nil,
            page: nil
        )

        let response: BridgeResponse<TaskCounts> = try sendRequest(request, responseType: TaskCounts.self)
        if response.ok, let counts = response.data {
            return counts
        }

        let message = response.error?.message ?? "Unknown bridge error"
        throw AutomationError.executionFailed(message)
    }

    func getProjectCounts(filter: TaskFilter) throws -> ProjectCounts {
        let requestId = UUID().uuidString
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: requestId,
            op: "get_project_counts",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: filter,
            tagFilter: nil,
            projectFilter: nil,
            mutation: nil,
            fields: nil,
            page: nil
        )

        let response: BridgeResponse<ProjectCounts> = try sendRequest(request, responseType: ProjectCounts.self)
        if response.ok, let counts = response.data {
            return counts
        }

        let message = response.error?.message ?? "Unknown bridge error"
        throw AutomationError.executionFailed(message)
    }

    func performMutation(_ mutation: MutationRequest) throws -> MutationResponse {
        try mutation.validate()

        let requestId = UUID().uuidString
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: requestId,
            op: "perform_mutation",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: nil,
            tagFilter: nil,
            projectFilter: nil,
            mutation: mutation,
            fields: nil,
            page: nil
        )

        let response: BridgeResponse<MutationResponse> = try sendRequest(request, responseType: MutationResponse.self)
        if response.ok, let mutationResponse = response.data {
            return mutationResponse
        }

        let message = response.error?.message ?? "Unknown bridge error"
        throw AutomationError.executionFailed(message)
    }

    private func ensureDirectories() throws {
        let paths = try requirePaths()
        if !didEnsureDirectories {
            let ownerOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
            try [paths.baseURL, paths.requestsURL, paths.responsesURL, paths.locksURL, paths.dispatchURL].forEach { url in
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: ownerOnly)
            }
            didEnsureDirectories = true
        }
        if !didRunStartupMaintenance {
            makeMaintenance(paths: paths).performStartupMaintenance()
            didRunStartupMaintenance = true
            lastStaleSweep = Date()
        } else if shouldRunStaleSweep(lastSweep: lastStaleSweep, now: Date(), minimumInterval: staleInterval) {
            makeMaintenance(paths: paths).sweepStaleFiles()
            lastStaleSweep = Date()
        }
    }

    private func writeRequest(_ request: BridgeRequest, requestId: String) throws {
        let requestURL = try requirePaths().requestsURL.appendingPathComponent("\(requestId).json")
        let data = try encoder.encode(request)
        try data.write(to: requestURL, options: .atomic)
        // Atomic replace discards custom modes, so tighten after the write.
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: requestURL.path)
    }

    private func dispatchRequestURL() throws -> URL {
        try requirePaths().dispatchURL.appendingPathComponent("request.json")
    }

    private func writeDispatchRequestId(_ requestId: String) throws {
        let paths = try requirePaths()
        try fileManager.createDirectory(at: paths.dispatchURL, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let payload = ["requestId": requestId]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        let url = paths.dispatchURL.appendingPathComponent("request.json")
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func triggerOmniFocus(requestId: String) throws {
        if let dispatchHandlerForTesting {
            try dispatchHandlerForTesting(requestId)
            return
        }
        let script = bridgeScript(basePath: try requirePaths().baseURL.path, requestId: requestId)
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?")
        let encodedScript = script.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let argJSON = jsonString(requestId)
        let encodedArg = argJSON.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        let urlString = "omnifocus:///omnijs-run?script=\(encodedScript)&arg=\(encodedArg)"
        guard let url = URL(string: urlString) else {
            throw AutomationError.executionFailed("Failed to build OmniFocus bridge URL")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-g", "-a", "OmniFocus", url.absoluteString]
        try process.run()
    }

    private func sendRequest<T: Decodable>(_ request: BridgeRequest, responseType: T.Type) throws -> BridgeResponse<T> {
        try ensureDirectories()
        let paths = try requirePaths()
        let responseURL = paths.responsesURL.appendingPathComponent("\(request.requestId).json")
        let requestURL = paths.requestsURL.appendingPathComponent("\(request.requestId).json")
        let lockURL = paths.locksURL.appendingPathComponent("\(request.requestId).lock")
        do {
            try writeRequest(request, requestId: request.requestId)
            try writeDispatchRequestId(request.requestId)
            try triggerOmniFocus(requestId: request.requestId)
            let response = try waitForResponse(
                at: responseURL,
                requestURL: requestURL,
                lockURL: lockURL,
                requestId: request.requestId,
                timeout: configuration.responseTimeout,
                responseType: responseType
            )
            // Response payloads carry task data; remove them as soon as they
            // are consumed. Request and lock are belt-and-braces: the plugin
            // also deletes them but swallows its own removal errors. Request
            // IDs are never re-dispatched after success, so the plugin's
            // duplicate-processing check is unaffected.
            removeIfExists(url: responseURL)
            removeIfExists(url: requestURL)
            removeIfExists(url: lockURL)
            removeIfExists(url: try dispatchRequestURL())
            if let warnings = response.warnings, !warnings.isEmpty {
                onResponseWarnings?(warnings, request.op)
            }
            return response
        } catch {
            if !isTimeoutError(error) {
                removeIfExists(url: requestURL)
                removeIfExists(url: lockURL)
                removeIfExists(url: (try? dispatchRequestURL()))
            }
            throw error
        }
    }

    private func waitForResponse<T: Decodable>(
        at url: URL,
        requestURL: URL,
        lockURL: URL,
        requestId: String,
        timeout: TimeInterval,
        responseType: T.Type
    ) throws -> BridgeResponse<T> {
        let start = Date()
        var lastReadError: Error?
        var hasRedispatchedStrandedRequest = false
        while Date().timeIntervalSince(start) < timeout {
            if fileManager.fileExists(atPath: url.path) {
                do {
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(BridgeResponse<T>.self, from: data)
                } catch {
                    lastReadError = error
                }
            }

            if !hasRedispatchedStrandedRequest,
               shouldRedispatchStrandedRequest(
                elapsed: Date().timeIntervalSince(start),
                timeout: timeout,
                requestURL: requestURL,
                responseURL: url,
                lockURL: lockURL
               ) {
                do {
                    try triggerOmniFocus(requestId: requestId)
                    hasRedispatchedStrandedRequest = true
                } catch {
                    lastReadError = error
                }
            }
            Thread.sleep(forTimeInterval: configuration.responsePollInterval)
        }

        if fileManager.fileExists(atPath: url.path) {
            do {
                let data = try Data(contentsOf: url)
                return try decoder.decode(BridgeResponse<T>.self, from: data)
            } catch {
                lastReadError = error
            }
        }

        let requestExists = fileManager.fileExists(atPath: requestURL.path)
        let responseExists = fileManager.fileExists(atPath: url.path)
        let lockExists = fileManager.fileExists(atPath: lockURL.path)

        if shouldAttemptLateStrandedRecovery(
            requestExists: requestExists,
            responseExists: responseExists,
            lockExists: lockExists
        ) {
            do {
                if let recovered: BridgeResponse<T> = try attemptLateStrandedRecovery(
                    at: url,
                    requestId: requestId,
                    timeout: timeout,
                    responseType: responseType
                ) {
                    return recovered
                }
            } catch {
                lastReadError = error
            }
        }

        let timeoutSeconds = String(format: "%.1f", timeout)
        let lastReadDetail = lastReadError.map { String(describing: $0) } ?? "none"
        let pickupState = bridgePickupState(
            requestExists: requestExists,
            responseExists: responseExists,
            lockExists: lockExists
        )
        throw AutomationError.executionFailed(
            "Bridge response timed out after \(timeoutSeconds)s (requestId=\(requestId), pickupState=\(pickupState), requestExists=\(requestExists), responseExists=\(responseExists), lockExists=\(lockExists), strandedRedispatched=\(hasRedispatchedStrandedRequest), lastReadError=\(lastReadDetail))"
        )
    }

    private func attemptLateStrandedRecovery<T: Decodable>(
        at responseURL: URL,
        requestId: String,
        timeout: TimeInterval,
        responseType: T.Type
    ) throws -> BridgeResponse<T>? {
        try writeDispatchRequestId(requestId)
        try triggerOmniFocus(requestId: requestId)
        let graceDeadline = Date().addingTimeInterval(lateStrandedRecoveryGrace(timeout: timeout))

        while Date() < graceDeadline {
            if fileManager.fileExists(atPath: responseURL.path) {
                let data = try Data(contentsOf: responseURL)
                return try decoder.decode(BridgeResponse<T>.self, from: data)
            }
            Thread.sleep(forTimeInterval: configuration.responsePollInterval)
        }

        return nil
    }

    private func removeIfExists(url: URL?) {
        guard let url, fileManager.fileExists(atPath: url.path) else { return }
        try? fileManager.removeItem(at: url)
    }

    private func shouldRedispatchStrandedRequest(
        elapsed: TimeInterval,
        timeout: TimeInterval,
        requestURL: URL,
        responseURL: URL,
        lockURL: URL
    ) -> Bool {
        guard elapsed >= strandedRedispatchDelay(timeout: timeout) else {
            return false
        }
        return fileManager.fileExists(atPath: requestURL.path)
            && !fileManager.fileExists(atPath: responseURL.path)
            && !fileManager.fileExists(atPath: lockURL.path)
    }

    private func isTimeoutError(_ error: Error) -> Bool {
        guard let automationError = error as? AutomationError else {
            return false
        }
        switch automationError {
        case .executionFailed(let message):
            let lower = message.lowercased()
            return lower.contains("timed out") || lower.contains("timeout")
        }
    }
}

struct BridgeClientConfiguration: Equatable {
    let responseTimeout: TimeInterval
    let responsePollInterval: TimeInterval

    static func fromEnvironment(_ environment: [String: String]) -> BridgeClientConfiguration {
        let parsedTimeout = environment["FOCUS_RELAY_BRIDGE_RESPONSE_TIMEOUT_SECONDS"].flatMap(TimeInterval.init)
        let timeout = (parsedTimeout ?? 0) > 0 ? parsedTimeout! : 45.0

        let parsedPollInterval = environment["FOCUS_RELAY_BRIDGE_RESPONSE_POLL_MS"]
            .flatMap(Double.init)
            .map { $0 / 1000.0 }
        let pollInterval = (parsedPollInterval ?? 0) > 0 ? parsedPollInterval! : 0.05

        return BridgeClientConfiguration(
            responseTimeout: timeout,
            responsePollInterval: pollInterval
        )
    }
}

func strandedRedispatchDelay(timeout: TimeInterval) -> TimeInterval {
    min(2.0, max(0.5, timeout * 0.1))
}

func bridgePickupState(requestExists: Bool, responseExists: Bool, lockExists: Bool) -> String {
    if responseExists { return "response_written" }
    if lockExists { return "bridge_processing" }
    if requestExists { return "stranded_not_picked_up" }
    return "request_missing"
}

func lateStrandedRecoveryGrace(timeout: TimeInterval) -> TimeInterval {
    min(10.0, max(3.0, timeout * 0.2))
}

func shouldAttemptLateStrandedRecovery(
    requestExists: Bool,
    responseExists: Bool,
    lockExists: Bool
) -> Bool {
    requestExists && !responseExists && !lockExists
}

private func bridgeScript(basePath: String, requestId: String) -> String {
    return """
    (function() {
      var requestId = argument;
      var basePath = \(jsonString(basePath));
      var requestPath = basePath + "/requests/" + requestId + ".json";
      var responsePath = basePath + "/responses/" + requestId + ".json";

      function safe(fn) {
        try { return fn(); } catch (e) { return null; }
      }

      function readJSON(path) {
        var url = URL.fromString("file://" + path);
        var wrapper = FileWrapper.fromURL(url);
        return JSON.parse(wrapper.contents.toString());
      }

      function ensureDir(path) {
        try {
          var url = URL.fromString("file://" + path);
          var wrapper = FileWrapper.fromURL(url);
          if (wrapper.type === FileWrapper.Type.Directory) { return; }
        } catch (e) {}
        var url = URL.fromString("file://" + path);
        var dir = FileWrapper.withChildren(null, []);
        dir.write(url, [FileWrapper.WritingOptions.Atomic], null);
      }

      function writeJSON(path, obj) {
        var url = URL.fromString("file://" + path);
        var data = Data.fromString(JSON.stringify(obj));
        var wrapper = FileWrapper.withContents(null, data);
        wrapper.write(url, [FileWrapper.WritingOptions.Atomic], null);
      }

      try {
        ensureDir(basePath);
        ensureDir(basePath + "/requests");
        ensureDir(basePath + "/responses");
        ensureDir(basePath + "/locks");
        var plugin = PlugIn.find("com.focusrelay.bridge");
        if (!plugin) {
          writeJSON(responsePath, { schemaVersion: 1, requestId: requestId, ok: false, error: { code: "PLUGIN_MISSING", message: "FocusRelay Bridge plug-in not installed" } });
          return;
        }
        var lib = plugin.library("BridgeLibrary");
        lib.handleRequest(requestId, basePath);
      } catch (err) {
        writeJSON(responsePath, { schemaVersion: 1, requestId: requestId, ok: false, error: { code: "BRIDGE_ERROR", message: String(err) } });
      }
    })();
    """
}

private func jsonString(_ value: String) -> String {
    let data = try? JSONEncoder().encode(value)
    let encoded = data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    return encoded
}

// MARK: - Batch name resolution

struct NameSearchGroupPayload<Item: Codable>: Codable {
    let search: String?
    let items: [Item]?
    let returnedCount: Int?
    let truncated: Bool?
}

struct BatchSearchPayload<Item: Codable>: Codable {
    let searchResults: [NameSearchGroupPayload<Item>]?
    let returnedCount: Int?
}

extension BridgeClient {
    func resolveProjectNames(
        searches: [String],
        matchLimitPerSearch: Int,
        statusFilter: String?,
        fields: [String]?
    ) throws -> [NameSearchGroup<ProjectItem>] {
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: UUID().uuidString,
            op: "list_projects",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: nil,
            tagFilter: nil,
            projectFilter: ProjectFilter(
                searches: searches,
                matchLimitPerSearch: matchLimitPerSearch,
                statusFilter: statusFilter,
                includeTaskCounts: false
            ),
            mutation: nil,
            fields: fields,
            page: nil
        )
        let response: BridgeResponse<BatchSearchPayload<ProjectItemPayload>> =
            try sendRequest(request, responseType: BatchSearchPayload<ProjectItemPayload>.self)
        guard response.ok, let data = response.data else {
            throw AutomationError.executionFailed(response.error?.message ?? "Unknown bridge error")
        }
        return (data.searchResults ?? []).map { group in
            NameSearchGroup(
                search: group.search ?? "",
                items: (group.items ?? []).map(Self.projectItem(from:)),
                truncated: group.truncated ?? false
            )
        }
    }

    func resolveTagNames(
        searches: [String],
        matchLimitPerSearch: Int,
        statusFilter: String?,
        fields: [String]?
    ) throws -> [NameSearchGroup<TagItem>] {
        let request = BridgeRequest(
            schemaVersion: 1,
            requestId: UUID().uuidString,
            op: "list_tags",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            userTimeZone: TimeZone.current.identifier,
            id: nil,
            filter: nil,
            tagFilter: TagFilter(
                searches: searches,
                matchLimitPerSearch: matchLimitPerSearch,
                statusFilter: statusFilter,
                includeTaskCounts: false
            ),
            projectFilter: nil,
            mutation: nil,
            fields: fields,
            page: nil
        )
        let response: BridgeResponse<BatchSearchPayload<TagItemPayload>> =
            try sendRequest(request, responseType: BatchSearchPayload<TagItemPayload>.self)
        guard response.ok, let data = response.data else {
            throw AutomationError.executionFailed(response.error?.message ?? "Unknown bridge error")
        }
        return (data.searchResults ?? []).map { group in
            NameSearchGroup(
                search: group.search ?? "",
                items: (group.items ?? []).map(Self.tagItem(from:)),
                truncated: group.truncated ?? false
            )
        }
    }
}
