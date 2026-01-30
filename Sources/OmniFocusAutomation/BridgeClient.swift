import Foundation
import OmniFocusCore

final class BridgeClient: @unchecked Sendable {
    private let paths: IPCPaths
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let staleInterval: TimeInterval

    init(paths: IPCPaths = .default(), fileManager: FileManager = .default, staleInterval: TimeInterval = 600) {
        self.paths = paths
        self.fileManager = fileManager
        self.staleInterval = staleInterval
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
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
                    deferDate: payload.deferDate,
                    completionDate: payload.completionDate,
                    completed: payload.completed ?? false,
                    flagged: payload.flagged ?? false,
                    estimatedMinutes: payload.estimatedMinutes,
                    available: payload.available ?? false
                )
            }
            return Page(items: items, nextCursor: payloadPage.nextCursor, totalCount: payloadPage.totalCount)
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
            fields: nil,
            page: nil
        )

        return try sendRequest(request, responseType: BridgePing.self)
    }

    func listProjects(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool, fields: [String]?) throws -> Page<ProjectItem> {
        let requestId = UUID().uuidString
        let projectFilter = ProjectFilter(statusFilter: statusFilter, includeTaskCounts: includeTaskCounts)
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
            fields: fields,
            page: page
        )

        let response: BridgeResponse<Page<ProjectItemPayload>> = try sendRequest(request, responseType: Page<ProjectItemPayload>.self)
        if response.ok, let payloadPage = response.data {
            let items = payloadPage.items.map { payload in
                let nextTask = payload.nextTask.map { ProjectTaskSummary(id: $0.id ?? "", name: $0.name ?? "") }
                return ProjectItem(
                    id: payload.id ?? "",
                    name: payload.name ?? "",
                    note: payload.note,
                    status: payload.status ?? "",
                    flagged: payload.flagged ?? false,
                    availableTasks: payload.availableTasks,
                    remainingTasks: payload.remainingTasks,
                    completedTasks: payload.completedTasks,
                    droppedTasks: payload.droppedTasks,
                    totalTasks: payload.totalTasks,
                    hasChildren: payload.hasChildren,
                    nextTask: nextTask,
                    containsSingletonActions: payload.containsSingletonActions,
                    isStalled: payload.isStalled
                )
            }
            return Page(items: items, nextCursor: payloadPage.nextCursor, totalCount: payloadPage.totalCount)
        }

        let message = response.error?.message ?? "Unknown bridge error"
        throw AutomationError.executionFailed(message)
    }

    func listTags(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool) throws -> Page<TagItem> {
        let requestId = UUID().uuidString
        let tagFilter = TagFilter(statusFilter: statusFilter, includeTaskCounts: includeTaskCounts)
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
            fields: nil,
            page: page
        )

        let response: BridgeResponse<Page<TagItemPayload>> = try sendRequest(request, responseType: Page<TagItemPayload>.self)
        if response.ok, let payloadPage = response.data {
            let items = payloadPage.items.map { payload in
                TagItem(
                    id: payload.id ?? "",
                    name: payload.name ?? "",
                    status: payload.status,
                    availableTasks: payload.availableTasks,
                    remainingTasks: payload.remainingTasks,
                    totalTasks: payload.totalTasks
                )
            }
            return Page(items: items, nextCursor: payloadPage.nextCursor, totalCount: payloadPage.totalCount)
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
                deferDate: payload.deferDate,
                completionDate: payload.completionDate,
                completed: payload.completed ?? false,
                flagged: payload.flagged ?? false,
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

    private func ensureDirectories() throws {
        try [paths.baseURL, paths.requestsURL, paths.responsesURL, paths.locksURL, paths.logsURL].forEach { url in
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        cleanupStaleFiles()
    }

    private func writeRequest(_ request: BridgeRequest, requestId: String) throws {
        let requestURL = paths.requestsURL.appendingPathComponent("\(requestId).json")
        let data = try encoder.encode(request)
        try data.write(to: requestURL, options: .atomic)
    }

    private func triggerOmniFocus(requestId: String) throws {
        let script = bridgeScript(basePath: paths.baseURL.path, requestId: requestId)
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
        try writeRequest(request, requestId: request.requestId)
        try triggerOmniFocus(requestId: request.requestId)

        let responseURL = paths.responsesURL.appendingPathComponent("\(request.requestId).json")
        let requestURL = paths.requestsURL.appendingPathComponent("\(request.requestId).json")
        let lockURL = paths.locksURL.appendingPathComponent("\(request.requestId).lock")
        do {
            return try waitForResponse(at: responseURL, timeout: 10.0, responseType: responseType)
        } catch {
            removeIfExists(url: requestURL)
            removeIfExists(url: lockURL)
            throw error
        }
    }

    private func waitForResponse<T: Decodable>(at url: URL, timeout: TimeInterval, responseType: T.Type) throws -> BridgeResponse<T> {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if fileManager.fileExists(atPath: url.path) {
                let data = try Data(contentsOf: url)
                return try decoder.decode(BridgeResponse<T>.self, from: data)
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw AutomationError.executionFailed("Bridge response timed out")
    }

    private func cleanupStaleFiles() {
        let now = Date()
        [paths.requestsURL, paths.responsesURL, paths.locksURL].forEach { dir in
            guard let items = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
                return
            }
            for url in items {
                guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                      let modified = values.contentModificationDate else {
                    continue
                }
                if now.timeIntervalSince(modified) > staleInterval {
                    removeIfExists(url: url)
                }
            }
        }
    }

    private func removeIfExists(url: URL) {
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
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
        ensureDir(basePath + "/logs");
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
