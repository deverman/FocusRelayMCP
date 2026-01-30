import Foundation
import OSAKit
import OmniFocusCore

public enum AutomationError: Error, LocalizedError {
    case executionFailed(String)
    case scriptCreationFailed
    case notImplemented

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "Automation execution failed: \(message)"
        case .scriptCreationFailed:
            return "Failed to create automation script"
        case .notImplemented:
            return "OmniFocus automation is not implemented yet."
        }
    }
}

public final class ScriptRunner: Sendable {
    public init() {}

    public func runJavaScript(_ source: String) throws -> String {
        guard let language = OSALanguage(forName: "JavaScript") else {
            throw AutomationError.scriptCreationFailed
        }
        let script = OSAScript(source: source, language: language)
        var errorInfo: NSDictionary?
        let output = script.executeAndReturnError(&errorInfo)

        if let errorInfo = errorInfo {
            throw AutomationError.executionFailed(errorInfo.description)
        }

        return output?.stringValue ?? ""
    }
}

public final class OmniAutomationService: OmniFocusService {
    private let runner: ScriptRunner
    private let decoder: JSONDecoder

    public init(runner: ScriptRunner = ScriptRunner()) {
        self.runner = runner
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func listTasks(filter: TaskFilter, page: PageRequest, fields: [String]?) async throws -> Page<TaskItem> {
        var effectiveFilter = filter
        if effectiveFilter.inboxOnly == true && effectiveFilter.completed == nil {
            effectiveFilter.completed = false
        }

        guard effectiveFilter.inboxOnly == true else {
            throw AutomationError.executionFailed("Only inboxOnly is supported for listTasks in v0.1")
        }

        let request = ListTasksRequest(filter: effectiveFilter, page: page, fields: fields)
        let requestData = try JSONEncoder().encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw AutomationError.executionFailed("Failed to encode request JSON")
        }

        let script = listInboxTasksScript(requestJSON: requestJSON)
        let output = try runner.runJavaScript(script)
        let data = Data(output.utf8)
        let payloadPage = try decoder.decode(Page<TaskItemPayload>.self, from: data)
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
                completed: payload.completed ?? false,
                flagged: payload.flagged ?? false,
                estimatedMinutes: payload.estimatedMinutes,
                available: payload.available ?? false
            )
        }
        return Page(items: items, nextCursor: payloadPage.nextCursor)
    }

    public func getTask(id: String, fields: [String]?) async throws -> TaskItem {
        _ = runner
        throw AutomationError.notImplemented
    }

    public func listProjects(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool, fields: [String]?) async throws -> Page<ProjectItem> {
        let request = ListProjectsRequest(page: page, statusFilter: statusFilter, includeTaskCounts: includeTaskCounts, fields: fields)
        let requestData = try JSONEncoder().encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw AutomationError.executionFailed("Failed to encode request JSON")
        }

        let script = listProjectsScript(requestJSON: requestJSON)
        let output = try runner.runJavaScript(script)
        let data = Data(output.utf8)
        let payloadPage = try decoder.decode(Page<ProjectItemPayload>.self, from: data)
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
                nextTask: nextTask
            )
        }
        return Page(items: items, nextCursor: payloadPage.nextCursor)
    }

    public func listTags(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool) async throws -> Page<TagItem> {
        _ = runner
        throw AutomationError.notImplemented
    }

    public func getTaskCounts(filter: TaskFilter) async throws -> TaskCounts {
        _ = runner
        throw AutomationError.notImplemented
    }

    public func getProjectCounts(filter: TaskFilter) async throws -> ProjectCounts {
        _ = runner
        throw AutomationError.notImplemented
    }

    public func debugInboxProbe() async throws -> InboxProbe {
        let script = inboxProbeScript()
        let output = try runner.runJavaScript(script)
        let data = Data(output.utf8)
        return try decoder.decode(InboxProbe.self, from: data)
    }

    public func debugInboxProbeAlt() async throws -> InboxProbeAlt {
        let script = inboxProbeAltScript()
        let output = try runner.runJavaScript(script)
        let data = Data(output.utf8)
        return try decoder.decode(InboxProbeAlt.self, from: data)
    }
}

private struct ListTasksRequest: Codable {
    let filter: TaskFilter
    let page: PageRequest
    let fields: [String]?
}


private struct ListProjectsRequest: Codable {
    let page: PageRequest
    let statusFilter: String?
    let includeTaskCounts: Bool
    let fields: [String]?
}


public struct InboxProbe: Codable, Sendable {
    public let inboxTasksCount: Int
    public let inboxInInboxCount: Int
    public let inboxNotCompletedCount: Int
    public let inboxNotDroppedCount: Int
    public let inboxAvailableCount: Int
    public let inboxAvailableNotCompletedCount: Int
    public let inboxNoDeferDateCount: Int
    public let inboxNoEffectiveDeferDateCount: Int
    public let inboxInInboxNotCompletedCount: Int
    public let sampleInboxTasks: [String]
    public let sampleInboxMeta: [InboxProbeItem]
}

public struct InboxProbeItem: Codable, Sendable {
    public let name: String
    public let inInbox: Bool?
    public let completed: Bool?
    public let taskStatus: String?
    public let available: Bool?
    public let deferDate: Date?
    public let effectiveDeferDate: Date?
    public let projectName: String?
    public let parentName: String?
}

public struct InboxProbeAlt: Codable, Sendable {
    public let inboxTasksCount: Int
    public let inboxInInboxCount: Int
    public let flattenedInInboxCount: Int
    public let flattenedInInboxNotCompletedCount: Int
    public let inboxTasksMs: Int
    public let flattenedFilterMs: Int
}

private func listInboxTasksScript(requestJSON: String) -> String {
    return """
    (function() {
      var request = \(requestJSON);
      var limit = (request.page && request.page.limit) ? request.page.limit : 50;
      var offset = 0;
      if (request.page && request.page.cursor) {
        var parsed = parseInt(request.page.cursor, 10);
        if (!isNaN(parsed) && parsed >= 0) { offset = parsed; }
      }
      var fields = (request.fields && Array.isArray(request.fields)) ? request.fields : [];
      function hasField(name) {
        return fields.length === 0 || fields.indexOf(name) !== -1;
      }

      function safe(fn) {
        try { return fn(); } catch (e) { return null; }
      }

      var app = Application('OmniFocus');
      var doc = app.defaultDocument();
      var tasks = doc.inboxTasks();
      var completedFilter = null;
      if (request.filter && typeof request.filter.completed === "boolean") {
        completedFilter = request.filter.completed;
      }
      if (completedFilter !== null) {
        tasks = tasks.filter(function(t) {
          return Boolean(safe(function() { return t.completed(); })) === completedFilter;
        });
      }

      tasks = tasks.filter(function(t) {
        var dropDate = safe(function() { return t.dropDate(); });
        if (dropDate) { return false; }
        if (completedFilter === null) {
          if (Boolean(safe(function() { return t.completed(); }))) { return false; }
        }
        return true;
      });
      var projectFilter = null;
      if (request.filter && typeof request.filter.project === "string" && request.filter.project.length > 0) {
        projectFilter = request.filter.project;
      }
      if (projectFilter !== null) {
        tasks = tasks.filter(function(t) {
          var project = safe(function() { return t.containingProject(); });
          if (!project) { return false; }
          var projectID = String(safe(function() { return project.id(); }) || "");
          var projectName = String(safe(function() { return project.name(); }) || "");
          return projectID === projectFilter || projectName === projectFilter;
        });
      }
      var availableOnly = null;
      if (request.filter && typeof request.filter.availableOnly === "boolean") {
        availableOnly = request.filter.availableOnly;
      }
      if (availableOnly === true) {
        tasks = tasks.filter(function(t) {
          return Boolean(safe(function() { return t.isAvailable(); }));
        });
      }
      var total = tasks.length;
      var slice = tasks.slice(offset, offset + limit);

      var items = slice.map(function(t) {
        var project = hasField("projectID") || hasField("projectName") ? safe(function() { return t.containingProject(); }) : null;
        var tags = (hasField("tagIDs") || hasField("tagNames")) ? (safe(function() { return t.tags(); }) || []) : [];
        var dueDate = hasField("dueDate") ? safe(function() { return t.dueDate(); }) : null;
        var deferDate = hasField("deferDate") ? safe(function() { return t.deferDate(); }) : null;

        return {
          id: hasField("id") ? String(safe(function() { return t.id(); }) || "") : null,
          name: hasField("name") ? String(safe(function() { return t.name(); }) || "") : null,
          note: hasField("note") ? safe(function() { return t.note(); }) : null,
          projectID: hasField("projectID") && project ? String(safe(function() { return project.id(); }) || "") : null,
          projectName: hasField("projectName") && project ? String(safe(function() { return project.name(); }) || "") : null,
          tagIDs: hasField("tagIDs") ? tags.map(function(tag) { return String(safe(function() { return tag.id(); }) || ""); }) : null,
          tagNames: hasField("tagNames") ? tags.map(function(tag) { return String(safe(function() { return tag.name(); }) || ""); }) : null,
          dueDate: hasField("dueDate") && dueDate ? dueDate.toISOString() : null,
          deferDate: hasField("deferDate") && deferDate ? deferDate.toISOString() : null,
          completed: hasField("completed") ? Boolean(safe(function() { return t.completed(); })) : null,
          flagged: hasField("flagged") ? Boolean(safe(function() { return t.flagged(); })) : null,
          estimatedMinutes: hasField("estimatedMinutes") ? safe(function() { return t.estimatedMinutes(); }) : null,
          available: hasField("available") ? Boolean(safe(function() { return t.isAvailable(); })) : null
        };
      });

      var nextCursor = (offset + limit < total) ? String(offset + limit) : null;
      return JSON.stringify({ items: items, nextCursor: nextCursor });
    })();
    """
}

private func listProjectsScript(requestJSON: String) -> String {
    return """
    (function() {
      var request = \(requestJSON);
      var limit = (request.page && request.page.limit) ? request.page.limit : 50;
      var offset = 0;
      if (request.page && request.page.cursor) {
        var parsed = parseInt(request.page.cursor, 10);
        if (!isNaN(parsed) && parsed >= 0) { offset = parsed; }
      }
      var fields = (request.fields && Array.isArray(request.fields)) ? request.fields : [];
      function hasField(name) {
        return fields.length === 0 || fields.indexOf(name) !== -1;
      }
      function safe(fn) {
        try { return fn(); } catch (e) { return null; }
      }

      var app = Application('OmniFocus');
      var doc = app.defaultDocument();
      var projects = doc.flattenedProjects();
      var total = projects.length;
      var slice = projects.slice(offset, offset + limit);

      var items = slice.map(function(p) {
        return {
          id: hasField("id") ? String(safe(function() { return p.id(); }) || "") : null,
          name: hasField("name") ? String(safe(function() { return p.name(); }) || "") : null,
          note: hasField("note") ? safe(function() { return p.note(); }) : null,
          status: hasField("status") ? String(safe(function() { return p.status(); }) || "") : null,
          flagged: hasField("flagged") ? Boolean(safe(function() { return p.flagged(); })) : null
        };
      });

      var nextCursor = (offset + limit < total) ? String(offset + limit) : null;
      return JSON.stringify({ items: items, nextCursor: nextCursor });
    })();
    """
}

private func inboxProbeScript() -> String {
    return """
    (function() {
      function safe(fn) {
        try { return fn(); } catch (e) { return null; }
      }

      var app = Application('OmniFocus');
      var doc = app.defaultDocument();
      var inboxTasks = doc.inboxTasks();

      var inboxInInbox = inboxTasks.filter(function(t) {
        var inInbox = safe(function() { return t.inInbox(); });
        if (inInbox === null || typeof inInbox === "undefined") { return false; }
        return Boolean(inInbox);
      });

      var inboxNotCompleted = inboxTasks.filter(function(t) {
        return !Boolean(safe(function() { return t.completed(); }));
      });

      var inboxNotDropped = inboxNotCompleted.filter(function(t) {
        var dropDate = safe(function() { return t.dropDate(); });
        return !dropDate;
      });

      var inboxAvailable = inboxTasks.filter(function(t) {
        return Boolean(safe(function() { return t.isAvailable(); }));
      });

      var inboxAvailableNotCompleted = inboxNotCompleted.filter(function(t) {
        return Boolean(safe(function() { return t.isAvailable(); }));
      });

      var inboxNoDeferDate = inboxTasks.filter(function(t) {
        var dd = safe(function() { return t.deferDate(); });
        return !dd;
      });

      var inboxNoEffectiveDeferDate = inboxTasks.filter(function(t) {
        var edd = safe(function() { return t.effectiveDeferDate(); });
        return !edd;
      });

      var inboxInInboxNotCompleted = inboxInInbox.filter(function(t) {
        return !Boolean(safe(function() { return t.completed(); }));
      });

      function nameOf(t) {
        return String(safe(function() { return t.name(); }) || "");
      }

      var sampleInboxTasks = inboxTasks.slice(0, 5).map(nameOf);

      var sampleInboxMeta = inboxTasks.slice(0, 5).map(function(t) {
        var project = safe(function() { return t.containingProject(); });
        var parent = safe(function() { return t.parent(); });
        var dropDate = safe(function() { return t.dropDate(); });
        var statusName = dropDate ? "Dropped" : (Boolean(safe(function() { return t.completed(); })) ? "Completed" : "Active");
        return {
          name: nameOf(t),
          inInbox: safe(function() { return t.inInbox(); }),
          completed: safe(function() { return t.completed(); }),
          taskStatus: statusName,
          available: safe(function() { return t.isAvailable(); }),
          deferDate: safe(function() { return t.deferDate(); }),
          effectiveDeferDate: safe(function() { return t.effectiveDeferDate(); }),
          projectName: project ? String(safe(function() { return project.name(); }) || "") : null,
          parentName: parent ? String(safe(function() { return parent.name(); }) || "") : null
        };
      });

      return JSON.stringify({
        inboxTasksCount: inboxTasks.length,
        inboxInInboxCount: inboxInInbox.length,
        inboxNotCompletedCount: inboxNotCompleted.length,
        inboxNotDroppedCount: inboxNotDropped.length,
        inboxAvailableCount: inboxAvailable.length,
        inboxAvailableNotCompletedCount: inboxAvailableNotCompleted.length,
        inboxNoDeferDateCount: inboxNoDeferDate.length,
        inboxNoEffectiveDeferDateCount: inboxNoEffectiveDeferDate.length,
        inboxInInboxNotCompletedCount: inboxInInboxNotCompleted.length,
        sampleInboxTasks: sampleInboxTasks,
        sampleInboxMeta: sampleInboxMeta
      });
    })();
    """
}

private func inboxProbeAltScript() -> String {
    return """
    (function() {
      function safe(fn) {
        try { return fn(); } catch (e) { return null; }
      }

      var app = Application('OmniFocus');
      var doc = app.defaultDocument();

      var t0 = Date.now();
      var inboxTasks = doc.inboxTasks();
      var inboxTasksMs = Date.now() - t0;

      var inboxInInbox = inboxTasks.filter(function(t) {
        var inInbox = safe(function() { return t.inInbox(); });
        return Boolean(inInbox);
      });

      var t1 = Date.now();
      var flattenedInInbox = doc.flattenedTasks().filter(function(t) {
        var inInbox = safe(function() { return t.inInbox(); });
        return Boolean(inInbox);
      });
      var flattenedFilterMs = Date.now() - t1;

      var flattenedInInboxNotCompleted = flattenedInInbox.filter(function(t) {
        return !Boolean(safe(function() { return t.completed(); }));
      });

      return JSON.stringify({
        inboxTasksCount: inboxTasks.length,
        inboxInInboxCount: inboxInInbox.length,
        flattenedInInboxCount: flattenedInInbox.length,
        flattenedInInboxNotCompletedCount: flattenedInInboxNotCompleted.length,
        inboxTasksMs: inboxTasksMs,
        flattenedFilterMs: flattenedFilterMs
      });
    })();
    """
}
