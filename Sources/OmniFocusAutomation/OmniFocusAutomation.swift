import Foundation
#if DEBUG
import OSAKit
#endif
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

#if DEBUG
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
    private let requestEncoder: JSONEncoder

    public init(runner: ScriptRunner = ScriptRunner()) {
        self.runner = runner
        self.decoder = BridgeDateDecoding.makeJSONDecoder()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.requestEncoder = encoder
    }

    public func listTasks(filter: TaskFilter, page: PageRequest, fields: [String]?) async throws -> Page<TaskItem> {
        var effectiveFilter = filter
        if effectiveFilter.inboxOnly == true && effectiveFilter.completed == nil {
            effectiveFilter.completed = false
        }

        let request = ListTasksRequest(filter: effectiveFilter, page: page, fields: fields)
        let requestData = try requestEncoder.encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw AutomationError.executionFailed("Failed to encode request JSON")
        }

        let script = listTasksEvaluateScript(requestJSON: requestJSON)
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
        return Page(items: items, nextCursor: payloadPage.nextCursor, returnedCount: payloadPage.returnedCount, totalCount: payloadPage.totalCount)
    }

    public func getTask(id: String, fields: [String]?) async throws -> TaskItem {
        _ = runner
        throw AutomationError.notImplemented
    }

    public func listProjects(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool,
        reviewDueBefore: Date?,
        reviewDueAfter: Date?,
        reviewPerspective: Bool,
        completed: Bool?,
        completedBefore: Date?,
        completedAfter: Date?,
        fields: [String]?
    ) async throws -> Page<ProjectItem> {
        let request = ListProjectsRequest(
            page: page,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            reviewDueBefore: reviewDueBefore,
            reviewDueAfter: reviewDueAfter,
            reviewPerspective: reviewPerspective,
            completed: completed,
            completedBefore: completedBefore,
            completedAfter: completedAfter,
            fields: fields
        )
        let requestData = try requestEncoder.encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw AutomationError.executionFailed("Failed to encode request JSON")
        }

        let script = listProjectsScript(requestJSON: requestJSON)
        let output = try runner.runJavaScript(script)
        let data = Data(output.utf8)
        let payloadPage = try decoder.decode(Page<ProjectItemPayload>.self, from: data)
        let items = payloadPage.items.map { payload in
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
                completionDate: payload.completionDate
            )
        }
        return Page(items: items, nextCursor: payloadPage.nextCursor, returnedCount: payloadPage.returnedCount, totalCount: payloadPage.totalCount)
    }

    public func listTags(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool) async throws -> Page<TagItem> {
        _ = runner
        throw AutomationError.notImplemented
    }

    public func listFolders(page: PageRequest, fields: [String]?) async throws -> Page<FolderItem> {
        try BridgeClient().listFolders(page: page, fields: fields)
    }

    public func getTaskCounts(filter: TaskFilter) async throws -> TaskCounts {
        let request = TaskCountsRequest(filter: filter)
        let requestData = try requestEncoder.encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw AutomationError.executionFailed("Failed to encode request JSON")
        }

        let script = taskCountsEvaluateScript(requestJSON: requestJSON)
        let output = try runner.runJavaScript(script)
        let data = Data(output.utf8)
        return try decoder.decode(TaskCounts.self, from: data)
    }

    public func getProjectCounts(filter: TaskFilter) async throws -> ProjectCounts {
        let request = ProjectCountsRequest(filter: filter)
        let requestData = try requestEncoder.encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw AutomationError.executionFailed("Failed to encode request JSON")
        }

        let script = projectCountsEvaluateScript(requestJSON: requestJSON)
        let output = try runner.runJavaScript(script)
        let data = Data(output.utf8)
        return try decoder.decode(ProjectCounts.self, from: data)
    }

    public func performMutation(_ request: MutationRequest) async throws -> MutationResponse {
        try request.validate()

        if request.operation.kind == .updateTasks ||
            request.operation.kind == .setTasksCompletion ||
            request.operation.kind == .moveTasks ||
            request.operation.kind == .updateProjects ||
            request.operation.kind == .setProjectsStatus ||
            request.operation.kind == .setProjectsCompletion ||
            request.operation.kind == .moveProjects {
            // Keep the real mutation paths in the bridge transport so CLI and MCP
            // share one execution implementation for v1 task and project mutations.
            return try await OmniFocusBridgeService().performMutation(request)
        }

        let requestData = try requestEncoder.encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw AutomationError.executionFailed("Failed to encode mutation request JSON")
        }

        let script = mutationPreviewEvaluateScript(requestJSON: requestJSON)
        let output = try runner.runJavaScript(script)
        let data = Data(output.utf8)
        return try decoder.decode(MutationResponse.self, from: data)
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
    let reviewDueBefore: Date?
    let reviewDueAfter: Date?
    let reviewPerspective: Bool
    let completed: Bool?
    let completedBefore: Date?
    let completedAfter: Date?
    let fields: [String]?
}

private struct TaskCountsRequest: Codable {
    let filter: TaskFilter
}

private struct ProjectCountsRequest: Codable {
    let filter: TaskFilter
}

private func mutationPreviewEvaluateScript(requestJSON: String) -> String {
    let automationScript = mutationPreviewOmniAutomationScript(requestJSON: requestJSON)
    return """
    (function() {
      var app = Application('OmniFocus');
      var script = \(jsStringLiteral(automationScript));
      var result = app.evaluateJavascript(script);
      if (Array.isArray(result)) {
        if (result.length === 0 || result[0] === null || typeof result[0] === "undefined") {
          return "";
        }
        return String(result[0]);
      }
      if (result === null || typeof result === "undefined") {
        return "";
      }
      return String(result);
    })();
    """
}

private func mutationPreviewOmniAutomationScript(requestJSON: String) -> String {
    return """
    (function() {
      var request = \(requestJSON);

      function toArray(collection) {
        if (!collection) { return []; }
        if (Array.isArray(collection)) { return collection; }
        if (typeof collection.apply === "function") {
          var items = [];
          collection.apply(function(item) { items.push(item); });
          return items;
        }
        try { return Array.from(collection); } catch (e) { return []; }
      }

      function objectID(item) {
        try { return String(item.id.primaryKey); } catch (e) { return ""; }
      }

      if (!request.previewOnly) {
        throw new Error("Mutation execution is not implemented yet. Use previewOnly=true.");
      }

      var targetType = request.targetType;
      var pool = targetType === "project" ? toArray(flattenedProjects) : toArray(flattenedTasks);
      var byID = {};
      for (var i = 0; i < pool.length; i += 1) {
        byID[objectID(pool[i])] = true;
      }

      var ids = Array.isArray(request.targetIDs) ? request.targetIDs : [];
      var results = ids.map(function(id) {
        if (byID[String(id)]) {
          return { id: String(id), status: "previewed", message: "Validated target for preview." };
        }
        return { id: String(id), status: "failed", message: "Target ID not found." };
      });

      var successCount = results.filter(function(item) { return item.status === "previewed"; }).length;
      var failureCount = results.length - successCount;

      return JSON.stringify({
        targetType: targetType,
        operationKind: request.operation.kind,
        previewOnly: true,
        verify: Boolean(request.verify),
        requestedCount: ids.length,
        successCount: successCount,
        failureCount: failureCount,
        results: results,
        warnings: []
      });
    })();
    """
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

private func listTasksEvaluateScript(requestJSON: String) -> String {
    let automationScript = listTasksOmniAutomationScript(requestJSON: requestJSON)
    return """
    (function() {
      var app = Application('OmniFocus');
      var script = \(jsStringLiteral(automationScript));
      var result = app.evaluateJavascript(script);
      if (Array.isArray(result)) {
        if (result.length === 0 || result[0] === null || typeof result[0] === "undefined") {
          return "";
        }
        return String(result[0]);
      }
      if (result === null || typeof result === "undefined") {
        return "";
      }
      return String(result);
    })();
    """
}

func listTasksOmniAutomationScript(requestJSON: String) -> String {
    return """
    (function() {
      var request = \(requestJSON);
      var filter = request.filter || {};
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

      function normalizeTaskSearchQuery(value) {
        if (typeof value !== "string") { return null; }
        var normalized = value.trim().toLowerCase();
        return normalized.length > 0 ? normalized : null;
      }

      function taskMatchesSearch(task, normalizedQuery) {
        if (!normalizedQuery) { return true; }
        var name = String(safe(function() { return task.name; }) || "").toLowerCase();
        if (name.indexOf(normalizedQuery) !== -1) { return true; }
        var note = String(safe(function() { return task.note; }) || "").toLowerCase();
        return note.indexOf(normalizedQuery) !== -1;
      }

      function toTaskArray(collection) {
        if (!collection) { return []; }
        if (Array.isArray(collection)) { return collection; }
        if (typeof collection.apply === "function") {
          var items = [];
          collection.apply(function(item) { items.push(item); });
          return items;
        }
        try {
          return Array.from(collection);
        } catch (e) {
          return [];
        }
      }

      function inboxTasksArray() {
        var inboxCollection = safe(function() { return inbox; });
        return toTaskArray(inboxCollection);
      }

      function taskStatusName(task) {
        var status = safe(function() { return task.taskStatus; });
        var statusText = String(status);
        if (statusText.indexOf("Completed") !== -1) { return "completed"; }
        if (statusText.indexOf("Dropped") !== -1) { return "dropped"; }
        if (statusText.indexOf("Available") !== -1) { return "available"; }
        if (statusText.indexOf("DueSoon") !== -1) { return "dueSoon"; }
        if (statusText.indexOf("Next") !== -1) { return "next"; }
        if (statusText.indexOf("Overdue") !== -1) { return "overdue"; }
        if (statusText.indexOf("Blocked") !== -1) { return "blocked"; }
        if (status === Task.Status.Completed) { return "completed"; }
        if (status === Task.Status.Dropped) { return "dropped"; }
        if (status === Task.Status.Available) { return "available"; }
        if (status === Task.Status.DueSoon) { return "dueSoon"; }
        if (status === Task.Status.Next) { return "next"; }
        if (status === Task.Status.Overdue) { return "overdue"; }
        if (status === Task.Status.Blocked) { return "blocked"; }
        return "unknown";
      }

      function projectStatusName(project) {
        var status = safe(function() { return project.status; });
        var statusText = String(status);
        if (statusText.indexOf("OnHold") !== -1) { return "onHold"; }
        if (statusText.indexOf("Dropped") !== -1) { return "dropped"; }
        if (statusText.indexOf("Done") !== -1) { return "done"; }
        if (statusText.indexOf("Active") !== -1) { return "active"; }
        if (status === Project.Status.OnHold) { return "onHold"; }
        if (status === Project.Status.Dropped) { return "dropped"; }
        if (status === Project.Status.Done) { return "done"; }
        if (status === Project.Status.Active) { return "active"; }
        return "unknown";
      }

      function isCompletedStatus(task) {
        return taskStatusName(task) === "completed";
      }

      function isDroppedStatus(task) {
        return taskStatusName(task) === "dropped";
      }

      function parentChainAllowsRemaining(task) {
        var parent = safe(function() { return task.parent; });
        var depth = 0;
        while (parent && depth < 100) {
          if (isCompletedStatus(parent) || isDroppedStatus(parent)) { return false; }
          parent = safe(function() { return parent.parent; });
          depth += 1;
        }
        return true;
      }

      function isRemainingStatus(task) {
        var statusName = taskStatusName(task);
        return statusName !== "completed" && statusName !== "dropped" && parentChainAllowsRemaining(task);
      }

      function isAvailableStatus(task) {
        var statusName = taskStatusName(task);
        return statusName === "available" ||
          statusName === "dueSoon" ||
          statusName === "next" ||
          statusName === "overdue";
      }

      function projectMatchesView(project, view, allowOnHoldInEverything) {
        if (!project) { return false; }
        if (!view || view === "all") { return true; }

        var normalizedView = String(view).toLowerCase();
        if (normalizedView === "everything") { return true; }
        var allowOnHold = allowOnHoldInEverything && normalizedView === "everything";
        var statusName = projectStatusName(project);

        if (statusName === "active") { return normalizedView === "active"; }
        if (statusName === "onHold") {
          return allowOnHold || normalizedView === "onhold" || normalizedView === "on_hold";
        }
        if (statusName === "dropped") { return normalizedView === "dropped"; }
        if (statusName === "done") {
          return normalizedView === "done" || normalizedView === "completed";
        }
        return false;
      }

      function isTaskAvailable(task) {
        if (!parentChainAllowsRemaining(task)) { return false; }

        var project = safe(function() { return task.containingProject; });
        if (project) {
          var projectStatus = projectStatusName(project);
          if (projectStatus !== "active") { return false; }
        }

        return isAvailableStatus(task);
      }

      function parseFilterDate(dateString) {
        if (!dateString || typeof dateString !== "string") { return null; }
        var parsed = new Date(dateString);
        if (isNaN(parsed.getTime())) { return null; }
        return parsed;
      }

      function getTaskDateTimestamp(task, getter) {
        var value = safe(function() { return getter(task); });
        if (!value || typeof value.getTime !== "function") { return null; }
        var timestamp = value.getTime();
        if (isNaN(timestamp)) { return null; }
        return timestamp;
      }

      function projectIdentifier(project) {
        return String(safe(function() { return project.id.primaryKey; }) || "");
      }

      function projectName(project) {
        return String(safe(function() { return project.name; }) || "");
      }

      function resolveProject(projectFilter, projects) {
        if (!projectFilter || typeof projectFilter !== "string") { return null; }
        for (var i = 0; i < projects.length; i += 1) {
          var project = projects[i];
          if (projectIdentifier(project) === projectFilter || projectName(project) === projectFilter) {
            return project;
          }
        }
        return null;
      }

      function tagMatchesFilter(task, filterTags, untaggedOnly) {
        var tags = safe(function() { return task.tags; }) || [];
        if (untaggedOnly) {
          return tags.length === 0;
        }

        return tagCollectionMatchesFilter(tags, filterTags);
      }

      function tagCollectionMatchesFilter(tags, filterTags) {
        for (var i = 0; i < tags.length; i += 1) {
          var tag = tags[i];
          var tagID = String(safe(function() { return tag.id.primaryKey; }) || "");
          var tagName = String(safe(function() { return tag.name; }) || "");
          for (var j = 0; j < filterTags.length; j += 1) {
            var filterTag = filterTags[j];
            if (tagID === filterTag || tagName === filterTag) {
              return true;
            }
          }
        }

        return false;
      }

      function taskIdentifier(task) {
        return String(safe(function() { return task.id.primaryKey; }) || "");
      }

      function isTaskEffectivelyFlagged(task) {
        return Boolean(safe(function() { return task.effectiveFlagged; }));
      }

      function isProjectRootTask(task) {
        var project = safe(function() { return task.containingProject; });
        if (!project) { return false; }
        var taskID = taskIdentifier(task);
        var projectID = String(safe(function() { return project.id.primaryKey; }) || "");
        return taskID.length > 0 && taskID === projectID;
      }

      function appendTaggedProjectRootTasks(tasks, projects, filterTags) {
        if (!Array.isArray(filterTags) || filterTags.length === 0) { return tasks; }

        var expandedTasks = tasks.slice();
        var seenTaskIDs = {};
        expandedTasks.forEach(function(task) {
          var id = taskIdentifier(task);
          if (id.length > 0) { seenTaskIDs[id] = true; }
        });

        projects.forEach(function(project) {
          var rootTask = safe(function() { return project.task; });
          if (!rootTask) { return; }

          var id = taskIdentifier(rootTask);
          if (id.length === 0 || seenTaskIDs[id]) { return; }

          var rootTags = safe(function() { return rootTask.tags; }) || [];
          var projectTags = safe(function() { return project.tags; }) || [];
          if (!tagCollectionMatchesFilter(rootTags, filterTags) && !tagCollectionMatchesFilter(projectTags, filterTags)) { return; }

          expandedTasks.push(rootTask);
          seenTaskIDs[id] = true;
        });

        return expandedTasks;
      }

      function taskToPayload(task) {
        var project = hasField("projectID") || hasField("projectName") ? safe(function() { return task.containingProject; }) : null;
        var tags = (hasField("tagIDs") || hasField("tagNames")) ? (safe(function() { return task.tags; }) || []) : [];
        var dueDate = hasField("dueDate") ? safe(function() { return task.dueDate; }) : null;
        var plannedDate = hasField("plannedDate") ? safe(function() { return task.plannedDate; }) : null;
        var deferDate = hasField("deferDate") ? safe(function() { return task.deferDate; }) : null;
        var completionDate = hasField("completionDate") ? safe(function() { return task.completionDate; }) : null;

        return {
          id: hasField("id") ? String(safe(function() { return task.id.primaryKey; }) || "") : null,
          name: hasField("name") ? String(safe(function() { return task.name; }) || "") : null,
          note: hasField("note") ? safe(function() { return task.note; }) : null,
          projectID: hasField("projectID") && project ? projectIdentifier(project) : null,
          projectName: hasField("projectName") && project ? projectName(project) : null,
          tagIDs: hasField("tagIDs") ? tags.map(function(tag) { return String(safe(function() { return tag.id.primaryKey; }) || ""); }) : null,
          tagNames: hasField("tagNames") ? tags.map(function(tag) { return String(safe(function() { return tag.name; }) || ""); }) : null,
          dueDate: hasField("dueDate") && dueDate ? dueDate.toISOString() : null,
          plannedDate: hasField("plannedDate") && plannedDate ? plannedDate.toISOString() : null,
          deferDate: hasField("deferDate") && deferDate ? deferDate.toISOString() : null,
          completionDate: hasField("completionDate") && completionDate ? completionDate.toISOString() : null,
          completed: hasField("completed") ? isCompletedStatus(task) : null,
          flagged: hasField("flagged") ? Boolean(safe(function() { return task.flagged; })) : null,
          effectiveFlagged: hasField("effectiveFlagged") ? isTaskEffectivelyFlagged(task) : null,
          estimatedMinutes: hasField("estimatedMinutes") ? safe(function() { return task.estimatedMinutes; }) : null,
          available: hasField("available") ? isTaskAvailable(task) : null
        };
      }

      var allProjects = toTaskArray(safe(function() { return flattenedProjects; }));
      var allTasks = toTaskArray(safe(function() { return flattenedTasks; })).filter(function(task) { return !isProjectRootTask(task); });
      var inboxView = (typeof filter.inboxView === "string") ? filter.inboxView.toLowerCase() : "available";
      var isEverything = inboxView === "everything";
      var isRemaining = inboxView === "remaining";
      var projectView = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : null;
      var availableOnly = (typeof filter.availableOnly === "boolean")
        ? filter.availableOnly
        : (filter.completed === true ? false : !isRemaining && !isEverything);

      var baseTasks = [];
      var projectRootCandidates = [];
      if (filter.inboxOnly === true) {
        baseTasks = inboxTasksArray();
      } else {
        var project = resolveProject(filter.project, allProjects);
        if (filter.project && !project) {
          baseTasks = [];
        } else if (project) {
          baseTasks = toTaskArray(safe(function() { return project.flattenedTasks; }));
          projectRootCandidates = [project];
        } else {
          baseTasks = allTasks;
          projectRootCandidates = allProjects;
        }
      }
      baseTasks = appendTaggedProjectRootTasks(baseTasks, projectRootCandidates, filter.tags);

      var filterState = {
        completed: filter.completed,
        flagged: filter.flagged,
        availableOnly: availableOnly,
        projectFilter: filter.project,
        projectView: projectView,
        dueBefore: filter.dueBefore ? parseFilterDate(filter.dueBefore) : null,
        dueAfter: filter.dueAfter ? parseFilterDate(filter.dueAfter) : null,
        plannedBefore: filter.plannedBefore ? parseFilterDate(filter.plannedBefore) : null,
        plannedAfter: filter.plannedAfter ? parseFilterDate(filter.plannedAfter) : null,
        deferBefore: filter.deferBefore ? parseFilterDate(filter.deferBefore) : null,
        deferAfter: filter.deferAfter ? parseFilterDate(filter.deferAfter) : null,
        completedBefore: filter.completedBefore ? parseFilterDate(filter.completedBefore) : null,
        completedAfter: filter.completedAfter ? parseFilterDate(filter.completedAfter) : null,
        tags: Array.isArray(filter.tags) ? filter.tags : null,
        untaggedOnly: Array.isArray(filter.tags) && filter.tags.length === 0,
        maxEstimatedMinutes: filter.maxEstimatedMinutes,
        minEstimatedMinutes: filter.minEstimatedMinutes,
        searchQuery: normalizeTaskSearchQuery(filter.search)
      };

      function matchesFilters(task) {
        var project = safe(function() { return task.containingProject; });

        if (filterState.completed !== undefined) {
          if (isCompletedStatus(task) !== filterState.completed) { return false; }
        } else if (!isEverything) {
          if (!isRemainingStatus(task)) { return false; }
        }

        if (filterState.flagged !== undefined) {
          if (isTaskEffectivelyFlagged(task) !== filterState.flagged) { return false; }
        }

        if (!taskMatchesSearch(task, filterState.searchQuery)) { return false; }

        if (filterState.availableOnly && !isTaskAvailable(task)) { return false; }

        if (filterState.projectFilter) {
          if (!project) { return false; }
          if (projectIdentifier(project) !== filterState.projectFilter && projectName(project) !== filterState.projectFilter) {
            return false;
          }
        }

        if (filterState.projectView) {
          if (!projectMatchesView(project, filterState.projectView, true)) { return false; }
        }

        if (filterState.dueBefore) {
          var dueBefore = getTaskDateTimestamp(task, function(item) { return item.dueDate; });
          if (dueBefore === null || dueBefore > filterState.dueBefore.getTime()) { return false; }
        }
        if (filterState.dueAfter) {
          var dueAfter = getTaskDateTimestamp(task, function(item) { return item.dueDate; });
          if (dueAfter === null || dueAfter < filterState.dueAfter.getTime()) { return false; }
        }
        if (filterState.deferBefore) {
          var deferBefore = getTaskDateTimestamp(task, function(item) { return item.deferDate; });
          if (deferBefore === null || deferBefore > filterState.deferBefore.getTime()) { return false; }
        }
        if (filterState.deferAfter) {
          var deferAfter = getTaskDateTimestamp(task, function(item) { return item.deferDate; });
          if (deferAfter === null || deferAfter < filterState.deferAfter.getTime()) { return false; }
        }
        if (filterState.plannedBefore) {
          var plannedBefore = getTaskDateTimestamp(task, function(item) { return item.plannedDate; });
          if (plannedBefore === null || plannedBefore > filterState.plannedBefore.getTime()) { return false; }
        }
        if (filterState.plannedAfter) {
          var plannedAfter = getTaskDateTimestamp(task, function(item) { return item.plannedDate; });
          if (plannedAfter === null || plannedAfter < filterState.plannedAfter.getTime()) { return false; }
        }
        if (filterState.completedBefore) {
          var completedBefore = getTaskDateTimestamp(task, function(item) { return item.completionDate; });
          if (completedBefore === null || completedBefore > filterState.completedBefore.getTime()) { return false; }
        }
        if (filterState.completedAfter) {
          var completedAfter = getTaskDateTimestamp(task, function(item) { return item.completionDate; });
          if (completedAfter === null || completedAfter < filterState.completedAfter.getTime()) { return false; }
        }
        if (filterState.maxEstimatedMinutes !== undefined) {
          var maxMinutes = safe(function() { return task.estimatedMinutes; });
          if (maxMinutes === null || maxMinutes === undefined || maxMinutes > filterState.maxEstimatedMinutes) { return false; }
        }
        if (filterState.minEstimatedMinutes !== undefined) {
          var minMinutes = safe(function() { return task.estimatedMinutes; });
          if (minMinutes === null || minMinutes === undefined || minMinutes < filterState.minEstimatedMinutes) { return false; }
        }

        if (filterState.tags && !tagMatchesFilter(task, filterState.tags, filterState.untaggedOnly)) {
          return false;
        }

        return true;
      }

      var filteredTasks = [];
      for (var i = 0; i < baseTasks.length; i += 1) {
        var task = baseTasks[i];
        if (matchesFilters(task)) {
          filteredTasks.push(task);
        }
      }

      if (filterState.completed === true || filterState.completedAfter || filterState.completedBefore) {
        filteredTasks.sort(function(a, b) {
          var dateA = getTaskDateTimestamp(a, function(item) { return item.completionDate; }) || 0;
          var dateB = getTaskDateTimestamp(b, function(item) { return item.completionDate; }) || 0;
          return dateB - dateA;
        });
      }

      var pageTasks = filteredTasks.slice(offset, offset + limit);
      var items = pageTasks.map(taskToPayload);
      var returnedCount = items.length;
      var nextCursor = (offset + returnedCount < filteredTasks.length) ? String(offset + returnedCount) : null;
      var payload = { items: items, nextCursor: nextCursor, returnedCount: returnedCount };
      if (filter.includeTotalCount === true) {
        payload.totalCount = filteredTasks.length;
      }

      return JSON.stringify(payload);
    })();
    """
}

private func listProjectsScript(requestJSON: String) -> String {
    let automationScript = listProjectsOmniAutomationScript(requestJSON: requestJSON)
    return """
    (function() {
      var app = Application('OmniFocus');
      var result = app.evaluateJavascript(\(jsStringLiteral(automationScript)));
      if (Array.isArray(result)) {
        if (result.length === 0 || result[0] === null || typeof result[0] === "undefined") { return ""; }
        return String(result[0]);
      }
      if (result === null || typeof result === "undefined") { return ""; }
      return String(result);
    })();
    """
}

func listProjectsOmniAutomationScript(requestJSON: String) -> String {
    return """
    (function() {
      const request = \(requestJSON);
      const fields = Array.isArray(request.fields) ? request.fields : [];
      const hasField = name => fields.length === 0 || fields.indexOf(name) !== -1;
      const safe = fn => { try { return fn(); } catch (_) { return null; } };
      const toArray = collection => {
        if (!collection) return [];
        if (Array.isArray(collection)) return collection;
        if (typeof collection.apply === "function") {
          const items = [];
          collection.apply(item => items.push(item));
          return items;
        }
        try { return Array.from(collection); } catch (_) { return []; }
      };
      const parseDate = value => {
        if (!value || typeof value !== "string") return null;
        const date = new Date(value);
        return isNaN(date.getTime()) ? null : date;
      };
      const dateTimestamp = (project, getter) => {
        const value = safe(() => getter(project));
        if (!value || typeof value.getTime !== "function") return null;
        const timestamp = value.getTime();
        return isNaN(timestamp) ? null : timestamp;
      };
      const taskStatus = task => safe(() => task.taskStatus);
      const isCompleted = status => status === Task.Status.Completed || String(status).includes("Completed");
      const isDropped = status => status === Task.Status.Dropped || String(status).includes("Dropped");
      const parentChainAllowsRemaining = task => {
        let parent = safe(() => task.parent);
        let depth = 0;
        while (parent && depth < 100) {
          const status = taskStatus(parent);
          if (isCompleted(status) || isDropped(status)) return false;
          parent = safe(() => parent.parent);
          depth += 1;
        }
        return true;
      };
      const isAvailableStatus = status => status === Task.Status.Available ||
        status === Task.Status.Next || status === Task.Status.DueSoon || status === Task.Status.Overdue;
      const projectIsActive = project => {
        const status = safe(() => project.status);
        return status === Project.Status.Active || String(status).includes("Active");
      };
      const projectStatusName = project => {
        const status = safe(() => project.status);
        if (status === Project.Status.OnHold || String(status).includes("OnHold")) return "onHold";
        if (status === Project.Status.Dropped || String(status).includes("Dropped")) return "dropped";
        if (status === Project.Status.Done || String(status).includes("Done")) return "done";
        return "active";
      };
      const summarizeTaskCounts = (project, tasks) => {
        const counts = { availableTasks: 0, remainingTasks: 0, completedTasks: 0, droppedTasks: 0, totalTasks: tasks.length };
        tasks.forEach(task => {
          const status = taskStatus(task);
          if (isCompleted(status)) counts.completedTasks += 1;
          else if (isDropped(status)) counts.droppedTasks += 1;
          else if (parentChainAllowsRemaining(task)) counts.remainingTasks += 1;
          if (projectIsActive(project) && parentChainAllowsRemaining(task) && isAvailableStatus(status)) {
            counts.availableTasks += 1;
          }
        });
        return counts;
      };

      const statusFilter = typeof request.statusFilter === "string" ? request.statusFilter.toLowerCase() : "active";
      const reviewPerspective = request.reviewPerspective === true;
      const reviewDueBefore = parseDate(request.reviewDueBefore);
      const reviewDueAfter = parseDate(request.reviewDueAfter);
      const reviewCutoff = reviewDueBefore || (reviewPerspective ? new Date() : null);
      const completedAfter = parseDate(request.completedAfter);
      const completedBefore = parseDate(request.completedBefore);
      const completedOnly = request.completed === true;

      let projects = toArray(flattenedProjects);
      if (reviewPerspective) {
        projects = projects.filter(project => {
          const status = projectStatusName(project);
          return status !== "dropped" && status !== "done";
        });
      } else if (statusFilter !== "all") {
        projects = projects.filter(project => {
          const status = projectStatusName(project).toLowerCase();
          if (statusFilter === "onhold" || statusFilter === "on_hold") return status === "onhold";
          if (statusFilter === "completed") return status === "done";
          return status === statusFilter;
        });
      }
      if (reviewCutoff || reviewDueAfter) {
        projects = projects.filter(project => {
          const timestamp = dateTimestamp(project, value => value.nextReviewDate);
          if (timestamp === null) return false;
          if (reviewCutoff && timestamp > reviewCutoff.getTime()) return false;
          if (reviewDueAfter && timestamp < reviewDueAfter.getTime()) return false;
          return true;
        });
      }
      if (completedOnly || completedAfter || completedBefore) {
        projects = projects.filter(project => {
          if (projectStatusName(project) !== "done") return false;
          const timestamp = dateTimestamp(project, value => value.completionDate);
          if (timestamp === null) return false;
          if (completedAfter && timestamp < completedAfter.getTime()) return false;
          if (completedBefore && timestamp > completedBefore.getTime()) return false;
          return true;
        });
        projects.sort((lhs, rhs) =>
          (dateTimestamp(rhs, value => value.completionDate) || 0) -
          (dateTimestamp(lhs, value => value.completionDate) || 0)
        );
      }

      const limit = request.page && request.page.limit ? request.page.limit : 50;
      let offset = 0;
      if (request.page && request.page.cursor) {
        const parsed = parseInt(request.page.cursor, 10);
        if (!isNaN(parsed) && parsed >= 0) offset = parsed;
      }
      const slice = projects.slice(offset, offset + limit);
      const items = slice.map(project => {
        const lastReviewDate = hasField("lastReviewDate") ? safe(() => project.lastReviewDate) : null;
        const nextReviewDate = hasField("nextReviewDate") ? safe(() => project.nextReviewDate) : null;
        const reviewInterval = hasField("reviewInterval") ? safe(() => project.reviewInterval) : null;
        const completionDate = hasField("completionDate") ? safe(() => project.completionDate) : null;
        const item = {
          id: hasField("id") ? String(safe(() => project.id.primaryKey) || "") : null,
          name: hasField("name") ? String(safe(() => project.name) || "") : null,
          note: hasField("note") ? safe(() => project.note) : null,
          status: hasField("status") ? projectStatusName(project) : null,
          flagged: hasField("flagged") ? Boolean(safe(() => project.flagged)) : null,
          lastReviewDate: lastReviewDate ? lastReviewDate.toISOString() : null,
          nextReviewDate: nextReviewDate ? nextReviewDate.toISOString() : null,
          reviewInterval: reviewInterval ? { steps: reviewInterval.steps, unit: String(reviewInterval.unit) } : null,
          completionDate: completionDate ? completionDate.toISOString() : null
        };
        const tasks = toArray(safe(() => project.flattenedTasks));
        if (request.includeTaskCounts === true) Object.assign(item, summarizeTaskCounts(project, tasks));
        if (hasField("hasChildren")) item.hasChildren = tasks.length > 0;
        if (hasField("containsSingletonActions")) item.containsSingletonActions = Boolean(safe(() => project.containsSingletonActions));
        if (hasField("nextTask")) {
          const nextTask = safe(() => project.nextTask);
          item.nextTask = nextTask ? { id: String(nextTask.id.primaryKey), name: String(nextTask.name) } : null;
        }
        if (hasField("isStalled")) {
          item.isStalled = tasks.length > 0 && !safe(() => project.nextTask) && !Boolean(safe(() => project.containsSingletonActions));
        }
        return item;
      });
      const nextCursor = offset + limit < projects.length ? String(offset + limit) : null;
      return JSON.stringify({ items: items, nextCursor: nextCursor, returnedCount: items.length, totalCount: projects.length });
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

private func taskCountsEvaluateScript(requestJSON: String) -> String {
    let automationScript = taskCountsOmniAutomationScript(requestJSON: requestJSON)
    return """
    (function() {
      var app = Application('OmniFocus');
      var script = \(jsStringLiteral(automationScript));
      var result = app.evaluateJavascript(script);
      if (Array.isArray(result)) {
        if (result.length === 0 || result[0] === null || typeof result[0] === "undefined") {
          return "";
        }
        return String(result[0]);
      }
      if (result === null || typeof result === "undefined") {
        return "";
      }
      return String(result);
    })();
    """
}

private func projectCountsEvaluateScript(requestJSON: String) -> String {
    let automationScript = projectCountsOmniAutomationScript(requestJSON: requestJSON)
    return """
    (function() {
      var app = Application('OmniFocus');
      var script = \(jsStringLiteral(automationScript));
      var result = app.evaluateJavascript(script);
      if (Array.isArray(result)) {
        if (result.length === 0 || result[0] === null || typeof result[0] === "undefined") {
          return "";
        }
        return String(result[0]);
      }
      if (result === null || typeof result === "undefined") {
        return "";
      }
      return String(result);
    })();
    """
}

func taskCountsOmniAutomationScript(requestJSON: String) -> String {
    return """
    (function() {
      var request = \(requestJSON);
      var filter = request.filter || {};

      function safe(fn) {
        try { return fn(); } catch (e) { return null; }
      }

      function normalizeTaskSearchQuery(value) {
        if (typeof value !== "string") { return null; }
        var normalized = value.trim().toLowerCase();
        return normalized.length > 0 ? normalized : null;
      }

      function taskMatchesSearch(task, normalizedQuery) {
        if (!normalizedQuery) { return true; }
        var name = String(safe(function() { return task.name; }) || "").toLowerCase();
        if (name.indexOf(normalizedQuery) !== -1) { return true; }
        var note = String(safe(function() { return task.note; }) || "").toLowerCase();
        return note.indexOf(normalizedQuery) !== -1;
      }

      function toTaskArray(collection) {
        if (!collection) { return []; }
        if (Array.isArray(collection)) { return collection; }
        if (typeof collection.apply === "function") {
          var items = [];
          collection.apply(function(item) { items.push(item); });
          return items;
        }
        try {
          return Array.from(collection);
        } catch (e) {
          return [];
        }
      }

      function inboxTasksArray() {
        var inboxCollection = safe(function() { return inbox; });
        return toTaskArray(inboxCollection);
      }

      function taskStatusName(task) {
        var status = safe(function() { return task.taskStatus; });
        var statusText = String(status);
        if (statusText.indexOf("Completed") !== -1) { return "completed"; }
        if (statusText.indexOf("Dropped") !== -1) { return "dropped"; }
        if (statusText.indexOf("Available") !== -1) { return "available"; }
        if (statusText.indexOf("DueSoon") !== -1) { return "dueSoon"; }
        if (statusText.indexOf("Next") !== -1) { return "next"; }
        if (statusText.indexOf("Overdue") !== -1) { return "overdue"; }
        if (statusText.indexOf("Blocked") !== -1) { return "blocked"; }
        if (status === Task.Status.Completed) { return "completed"; }
        if (status === Task.Status.Dropped) { return "dropped"; }
        if (status === Task.Status.Available) { return "available"; }
        if (status === Task.Status.DueSoon) { return "dueSoon"; }
        if (status === Task.Status.Next) { return "next"; }
        if (status === Task.Status.Overdue) { return "overdue"; }
        if (status === Task.Status.Blocked) { return "blocked"; }
        return "unknown";
      }

      function projectStatusName(project) {
        var status = safe(function() { return project.status; });
        var statusText = String(status);
        if (statusText.indexOf("OnHold") !== -1) { return "onHold"; }
        if (statusText.indexOf("Dropped") !== -1) { return "dropped"; }
        if (statusText.indexOf("Done") !== -1) { return "done"; }
        if (statusText.indexOf("Active") !== -1) { return "active"; }
        if (status === Project.Status.OnHold) { return "onHold"; }
        if (status === Project.Status.Dropped) { return "dropped"; }
        if (status === Project.Status.Done) { return "done"; }
        if (status === Project.Status.Active) { return "active"; }
        return "unknown";
      }

      function isCompletedStatus(task) {
        return taskStatusName(task) === "completed";
      }

      function isDroppedStatus(task) {
        return taskStatusName(task) === "dropped";
      }

      function parentChainAllowsRemaining(task) {
        var parent = safe(function() { return task.parent; });
        var depth = 0;
        while (parent && depth < 100) {
          if (isCompletedStatus(parent) || isDroppedStatus(parent)) { return false; }
          parent = safe(function() { return parent.parent; });
          depth += 1;
        }
        return true;
      }

      function isRemainingStatus(task) {
        var statusName = taskStatusName(task);
        return statusName !== "completed" && statusName !== "dropped" && parentChainAllowsRemaining(task);
      }

      function isAvailableStatus(task) {
        var statusName = taskStatusName(task);
        return statusName === "available" ||
          statusName === "dueSoon" ||
          statusName === "next" ||
          statusName === "overdue";
      }

      function projectMatchesView(project, view, allowOnHoldInEverything) {
        if (!project) { return false; }
        if (!view || view === "all") { return true; }

        var normalizedView = String(view).toLowerCase();
        if (normalizedView === "everything") { return true; }
        var allowOnHold = allowOnHoldInEverything && normalizedView === "everything";
        var statusName = projectStatusName(project);

        if (statusName === "active") { return normalizedView === "active"; }
        if (statusName === "onHold") {
          return allowOnHold || normalizedView === "onhold" || normalizedView === "on_hold";
        }
        if (statusName === "dropped") { return normalizedView === "dropped"; }
        if (statusName === "done") {
          return normalizedView === "done" || normalizedView === "completed";
        }
        return false;
      }

      function isTaskAvailable(task) {
        if (!parentChainAllowsRemaining(task)) { return false; }

        var project = safe(function() { return task.containingProject; });
        if (project) {
          var projectStatus = projectStatusName(project);
          if (projectStatus !== "active") { return false; }
        }

        return isAvailableStatus(task);
      }

      function parseFilterDate(dateString) {
        if (!dateString || typeof dateString !== "string") { return null; }
        var parsed = new Date(dateString);
        if (isNaN(parsed.getTime())) { return null; }
        return parsed;
      }

      function getTaskDateTimestamp(task, getter) {
        var value = safe(function() { return getter(task); });
        if (!value || typeof value.getTime !== "function") { return null; }
        var timestamp = value.getTime();
        if (isNaN(timestamp)) { return null; }
        return timestamp;
      }

      function projectIdentifier(project) {
        return String(safe(function() { return project.id.primaryKey; }) || "");
      }

      function projectName(project) {
        return String(safe(function() { return project.name; }) || "");
      }

      function resolveProject(projectFilter, projects) {
        if (!projectFilter || typeof projectFilter !== "string") { return null; }
        for (var i = 0; i < projects.length; i += 1) {
          var project = projects[i];
          if (projectIdentifier(project) === projectFilter || projectName(project) === projectFilter) {
            return project;
          }
        }
        return null;
      }

      function tagMatchesFilter(task, filterTags, untaggedOnly) {
        var tags = safe(function() { return task.tags; }) || [];
        if (untaggedOnly) {
          return tags.length === 0;
        }

        return tagCollectionMatchesFilter(tags, filterTags);
      }

      function tagCollectionMatchesFilter(tags, filterTags) {
        for (var i = 0; i < tags.length; i += 1) {
          var tag = tags[i];
          var tagID = String(safe(function() { return tag.id.primaryKey; }) || "");
          var tagName = String(safe(function() { return tag.name; }) || "");
          for (var j = 0; j < filterTags.length; j += 1) {
            var filterTag = filterTags[j];
            if (tagID === filterTag || tagName === filterTag) {
              return true;
            }
          }
        }

        return false;
      }

      function taskIdentifier(task) {
        return String(safe(function() { return task.id.primaryKey; }) || "");
      }

      function isTaskEffectivelyFlagged(task) {
        return Boolean(safe(function() { return task.effectiveFlagged; }));
      }

      function isProjectRootTask(task) {
        var project = safe(function() { return task.containingProject; });
        if (!project) { return false; }
        var taskID = taskIdentifier(task);
        var projectID = String(safe(function() { return project.id.primaryKey; }) || "");
        return taskID.length > 0 && taskID === projectID;
      }

      function appendTaggedProjectRootTasks(tasks, projects, filterTags) {
        if (!Array.isArray(filterTags) || filterTags.length === 0) { return tasks; }

        var expandedTasks = tasks.slice();
        var seenTaskIDs = {};
        expandedTasks.forEach(function(task) {
          var id = taskIdentifier(task);
          if (id.length > 0) { seenTaskIDs[id] = true; }
        });

        projects.forEach(function(project) {
          var rootTask = safe(function() { return project.task; });
          if (!rootTask) { return; }

          var id = taskIdentifier(rootTask);
          if (id.length === 0 || seenTaskIDs[id]) { return; }

          var rootTags = safe(function() { return rootTask.tags; }) || [];
          var projectTags = safe(function() { return project.tags; }) || [];
          if (!tagCollectionMatchesFilter(rootTags, filterTags) && !tagCollectionMatchesFilter(projectTags, filterTags)) { return; }

          expandedTasks.push(rootTask);
          seenTaskIDs[id] = true;
        });

        return expandedTasks;
      }

      var allProjects = toTaskArray(safe(function() { return flattenedProjects; }));
      var allTasks = toTaskArray(safe(function() { return flattenedTasks; })).filter(function(task) { return !isProjectRootTask(task); });
      var inboxView = (typeof filter.inboxView === "string") ? filter.inboxView.toLowerCase() : "available";
      var isEverything = inboxView === "everything";
      var isRemaining = inboxView === "remaining";
      var projectView = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : null;
      var availableOnly = (typeof filter.availableOnly === "boolean")
        ? filter.availableOnly
        : (filter.completed === true ? false : !isRemaining && !isEverything);

      var baseTasks = [];
      var projectRootCandidates = [];
      if (filter.inboxOnly === true) {
        baseTasks = inboxTasksArray();
      } else {
        var project = resolveProject(filter.project, allProjects);
        if (filter.project && !project) {
          baseTasks = [];
        } else if (project) {
          baseTasks = toTaskArray(safe(function() { return project.flattenedTasks; }));
          projectRootCandidates = [project];
        } else {
          baseTasks = allTasks;
          projectRootCandidates = allProjects;
        }
      }
      baseTasks = appendTaggedProjectRootTasks(baseTasks, projectRootCandidates, filter.tags);

      var filterState = {
        completed: filter.completed,
        flagged: filter.flagged,
        availableOnly: availableOnly,
        projectFilter: filter.project,
        projectView: projectView,
        dueBefore: filter.dueBefore ? parseFilterDate(filter.dueBefore) : null,
        dueAfter: filter.dueAfter ? parseFilterDate(filter.dueAfter) : null,
        plannedBefore: filter.plannedBefore ? parseFilterDate(filter.plannedBefore) : null,
        plannedAfter: filter.plannedAfter ? parseFilterDate(filter.plannedAfter) : null,
        deferBefore: filter.deferBefore ? parseFilterDate(filter.deferBefore) : null,
        deferAfter: filter.deferAfter ? parseFilterDate(filter.deferAfter) : null,
        completedBefore: filter.completedBefore ? parseFilterDate(filter.completedBefore) : null,
        completedAfter: filter.completedAfter ? parseFilterDate(filter.completedAfter) : null,
        tags: Array.isArray(filter.tags) ? filter.tags : null,
        untaggedOnly: Array.isArray(filter.tags) && filter.tags.length === 0,
        maxEstimatedMinutes: filter.maxEstimatedMinutes,
        minEstimatedMinutes: filter.minEstimatedMinutes,
        searchQuery: normalizeTaskSearchQuery(filter.search)
      };

      function matchesFilters(task) {
        var project = safe(function() { return task.containingProject; });

        if (filterState.completed !== undefined) {
          if (isCompletedStatus(task) !== filterState.completed) { return false; }
        } else if (!isEverything) {
          if (!isRemainingStatus(task)) { return false; }
        }

        if (filterState.flagged !== undefined) {
          if (isTaskEffectivelyFlagged(task) !== filterState.flagged) { return false; }
        }

        if (!taskMatchesSearch(task, filterState.searchQuery)) { return false; }

        if (filterState.availableOnly && !isTaskAvailable(task)) { return false; }

        if (filterState.projectFilter) {
          if (!project) { return false; }
          if (projectIdentifier(project) !== filterState.projectFilter && projectName(project) !== filterState.projectFilter) {
            return false;
          }
        }

        if (filterState.projectView) {
          if (!projectMatchesView(project, filterState.projectView, true)) { return false; }
        }

        if (filterState.dueBefore) {
          var dueBefore = getTaskDateTimestamp(task, function(item) { return item.dueDate; });
          if (dueBefore === null || dueBefore > filterState.dueBefore.getTime()) { return false; }
        }
        if (filterState.dueAfter) {
          var dueAfter = getTaskDateTimestamp(task, function(item) { return item.dueDate; });
          if (dueAfter === null || dueAfter < filterState.dueAfter.getTime()) { return false; }
        }
        if (filterState.deferBefore) {
          var deferBefore = getTaskDateTimestamp(task, function(item) { return item.deferDate; });
          if (deferBefore === null || deferBefore > filterState.deferBefore.getTime()) { return false; }
        }
        if (filterState.deferAfter) {
          var deferAfter = getTaskDateTimestamp(task, function(item) { return item.deferDate; });
          if (deferAfter === null || deferAfter < filterState.deferAfter.getTime()) { return false; }
        }
        if (filterState.plannedBefore) {
          var plannedBefore = getTaskDateTimestamp(task, function(item) { return item.plannedDate; });
          if (plannedBefore === null || plannedBefore > filterState.plannedBefore.getTime()) { return false; }
        }
        if (filterState.plannedAfter) {
          var plannedAfter = getTaskDateTimestamp(task, function(item) { return item.plannedDate; });
          if (plannedAfter === null || plannedAfter < filterState.plannedAfter.getTime()) { return false; }
        }
        if (filterState.completedBefore) {
          var completedBefore = getTaskDateTimestamp(task, function(item) { return item.completionDate; });
          if (completedBefore === null || completedBefore > filterState.completedBefore.getTime()) { return false; }
        }
        if (filterState.completedAfter) {
          var completedAfter = getTaskDateTimestamp(task, function(item) { return item.completionDate; });
          if (completedAfter === null || completedAfter < filterState.completedAfter.getTime()) { return false; }
        }

        if (filterState.maxEstimatedMinutes !== undefined) {
          var maxMinutes = safe(function() { return task.estimatedMinutes; });
          if (maxMinutes === null || maxMinutes === undefined || maxMinutes > filterState.maxEstimatedMinutes) { return false; }
        }
        if (filterState.minEstimatedMinutes !== undefined) {
          var minMinutes = safe(function() { return task.estimatedMinutes; });
          if (minMinutes === null || minMinutes === undefined || minMinutes < filterState.minEstimatedMinutes) { return false; }
        }

        if (filterState.tags && !tagMatchesFilter(task, filterState.tags, filterState.untaggedOnly)) {
          return false;
        }

        return true;
      }

      var counts = { total: 0, completed: 0, available: 0, flagged: 0 };
      for (var i = 0; i < baseTasks.length; i += 1) {
        var task = baseTasks[i];
        if (!matchesFilters(task)) { continue; }
        counts.total += 1;
        if (isCompletedStatus(task)) { counts.completed += 1; }
        if (isTaskAvailable(task)) { counts.available += 1; }
        if (isTaskEffectivelyFlagged(task)) { counts.flagged += 1; }
      }

      return JSON.stringify(counts);
    })();
    """
}

private func projectCountsOmniAutomationScript(requestJSON: String) -> String {
    return """
    (function() {
      var request = \(requestJSON);
      var filter = request.filter || {};

      function safe(fn) {
        try { return fn(); } catch (e) { return null; }
      }

      function toTaskArray(collection) {
        if (!collection) { return []; }
        if (Array.isArray(collection)) { return collection; }
        if (typeof collection.apply === "function") {
          var items = [];
          collection.apply(function(item) { items.push(item); });
          return items;
        }
        try {
          return Array.from(collection);
        } catch (e) {
          return [];
        }
      }

      function taskStatusName(task) {
        var status = safe(function() { return task.taskStatus; });
        var statusText = String(status);
        if (statusText.indexOf("Completed") !== -1) { return "completed"; }
        if (statusText.indexOf("Dropped") !== -1) { return "dropped"; }
        if (statusText.indexOf("Available") !== -1) { return "available"; }
        if (statusText.indexOf("DueSoon") !== -1) { return "dueSoon"; }
        if (statusText.indexOf("Next") !== -1) { return "next"; }
        if (statusText.indexOf("Overdue") !== -1) { return "overdue"; }
        if (statusText.indexOf("Blocked") !== -1) { return "blocked"; }
        if (status === Task.Status.Completed) { return "completed"; }
        if (status === Task.Status.Dropped) { return "dropped"; }
        if (status === Task.Status.Available) { return "available"; }
        if (status === Task.Status.DueSoon) { return "dueSoon"; }
        if (status === Task.Status.Next) { return "next"; }
        if (status === Task.Status.Overdue) { return "overdue"; }
        if (status === Task.Status.Blocked) { return "blocked"; }
        return "unknown";
      }

      function projectStatusName(project) {
        var status = safe(function() { return project.status; });
        var statusText = String(status);
        if (statusText.indexOf("OnHold") !== -1) { return "onHold"; }
        if (statusText.indexOf("Dropped") !== -1) { return "dropped"; }
        if (statusText.indexOf("Done") !== -1) { return "done"; }
        if (statusText.indexOf("Active") !== -1) { return "active"; }
        if (status === Project.Status.OnHold) { return "onHold"; }
        if (status === Project.Status.Dropped) { return "dropped"; }
        if (status === Project.Status.Done) { return "done"; }
        if (status === Project.Status.Active) { return "active"; }
        return "unknown";
      }

      function isCompletedStatus(task) {
        return taskStatusName(task) === "completed";
      }

      function isDroppedStatus(task) {
        return taskStatusName(task) === "dropped";
      }

      function parentChainAllowsRemaining(task) {
        var parent = safe(function() { return task.parent; });
        var depth = 0;
        while (parent && depth < 100) {
          if (isCompletedStatus(parent) || isDroppedStatus(parent)) { return false; }
          parent = safe(function() { return parent.parent; });
          depth += 1;
        }
        return true;
      }

      function isRemainingStatus(task) {
        var statusName = taskStatusName(task);
        return statusName !== "completed" && statusName !== "dropped" && parentChainAllowsRemaining(task);
      }

      function isAvailableStatus(task) {
        var statusName = taskStatusName(task);
        return statusName === "available" ||
          statusName === "dueSoon" ||
          statusName === "next" ||
          statusName === "overdue";
      }

      function projectMatchesView(project, view, allowOnHoldInEverything) {
        if (!project) { return false; }
        if (!view || view === "all") { return true; }

        var normalizedView = String(view).toLowerCase();
        if (normalizedView === "everything") { return true; }
        var allowOnHold = allowOnHoldInEverything && normalizedView === "everything";
        var statusName = projectStatusName(project);

        if (statusName === "active") { return normalizedView === "active"; }
        if (statusName === "onHold") {
          return allowOnHold || normalizedView === "onhold" || normalizedView === "on_hold";
        }
        if (statusName === "dropped") { return normalizedView === "dropped"; }
        if (statusName === "done") {
          return normalizedView === "done" || normalizedView === "completed";
        }
        return false;
      }

      function isTaskAvailable(task) {
        if (!parentChainAllowsRemaining(task)) { return false; }

        var project = safe(function() { return task.containingProject; });
        if (project) {
          var projectStatus = projectStatusName(project);
          if (projectStatus !== "active") { return false; }
        }

        return isAvailableStatus(task);
      }

      function parseFilterDate(dateString) {
        if (!dateString || typeof dateString !== "string") { return null; }
        var parsed = new Date(dateString);
        if (isNaN(parsed.getTime())) { return null; }
        return parsed;
      }

      function getTaskDateTimestamp(task, getter) {
        var value = safe(function() { return getter(task); });
        if (!value || typeof value.getTime !== "function") { return null; }
        var timestamp = value.getTime();
        if (isNaN(timestamp)) { return null; }
        return timestamp;
      }

      function getProjectDateTimestamp(project, getter) {
        var value = safe(function() { return getter(project); });
        if (!value || typeof value.getTime !== "function") { return null; }
        var timestamp = value.getTime();
        if (isNaN(timestamp)) { return null; }
        return timestamp;
      }

      function projectIdentifier(project) {
        return String(safe(function() { return project.id.primaryKey; }) || "");
      }

      function projectName(project) {
        return String(safe(function() { return project.name; }) || "");
      }

      function resolveProject(projectFilter, projects) {
        if (!projectFilter || typeof projectFilter !== "string") { return null; }
        for (var i = 0; i < projects.length; i += 1) {
          var project = projects[i];
          if (projectIdentifier(project) === projectFilter || projectName(project) === projectFilter) {
            return project;
          }
        }
        return null;
      }

      function tagMatchesFilter(task, filterTags, untaggedOnly) {
        var tags = safe(function() { return task.tags; }) || [];
        if (untaggedOnly) {
          return tags.length === 0;
        }

        return tagCollectionMatchesFilter(tags, filterTags);
      }

      function tagCollectionMatchesFilter(tags, filterTags) {
        for (var i = 0; i < tags.length; i += 1) {
          var tag = tags[i];
          var tagID = String(safe(function() { return tag.id.primaryKey; }) || "");
          var tagName = String(safe(function() { return tag.name; }) || "");
          for (var j = 0; j < filterTags.length; j += 1) {
            var filterTag = filterTags[j];
            if (tagID === filterTag || tagName === filterTag) {
              return true;
            }
          }
        }

        return false;
      }

      function taskIdentifier(task) {
        return String(safe(function() { return task.id.primaryKey; }) || "");
      }

      function isTaskEffectivelyFlagged(task) {
        return Boolean(safe(function() { return task.effectiveFlagged; }));
      }

      function isProjectRootTask(task) {
        var project = safe(function() { return task.containingProject; });
        if (!project) { return false; }
        var taskID = taskIdentifier(task);
        var projectID = String(safe(function() { return project.id.primaryKey; }) || "");
        return taskID.length > 0 && taskID === projectID;
      }

      function appendTaggedProjectRootTasks(tasks, projects, filterTags) {
        if (!Array.isArray(filterTags) || filterTags.length === 0) { return tasks; }

        var expandedTasks = tasks.slice();
        var seenTaskIDs = {};
        expandedTasks.forEach(function(task) {
          var id = taskIdentifier(task);
          if (id.length > 0) { seenTaskIDs[id] = true; }
        });

        projects.forEach(function(project) {
          var rootTask = safe(function() { return project.task; });
          if (!rootTask) { return; }

          var id = taskIdentifier(rootTask);
          if (id.length === 0 || seenTaskIDs[id]) { return; }

          var rootTags = safe(function() { return rootTask.tags; }) || [];
          var projectTags = safe(function() { return project.tags; }) || [];
          if (!tagCollectionMatchesFilter(rootTags, filterTags) && !tagCollectionMatchesFilter(projectTags, filterTags)) { return; }

          expandedTasks.push(rootTask);
          seenTaskIDs[id] = true;
        });

        return expandedTasks;
      }

      var allProjects = toTaskArray(safe(function() { return flattenedProjects; }));
      var allTasks = toTaskArray(safe(function() { return flattenedTasks; })).filter(function(task) { return !isProjectRootTask(task); });
      var completedAfter = filter.completedAfter ? parseFilterDate(filter.completedAfter) : null;
      var completedBefore = filter.completedBefore ? parseFilterDate(filter.completedBefore) : null;
      var completedOnly = filter.completed === true;

      if (completedOnly || completedAfter || completedBefore) {
        var completedProjects = [];
        for (var i = 0; i < allProjects.length; i += 1) {
          var completedProject = allProjects[i];
          if (projectStatusName(completedProject) !== "done") { continue; }
          var projectCompletionDate = getProjectDateTimestamp(completedProject, function(item) { return item.completionDate; });
          if (projectCompletionDate === null) { continue; }
          if (completedAfter && projectCompletionDate < completedAfter.getTime()) { continue; }
          if (completedBefore && projectCompletionDate > completedBefore.getTime()) { continue; }
          completedProjects.push(completedProject);
        }

        var completedProjectIDs = {};
        for (var projectIndex = 0; projectIndex < completedProjects.length; projectIndex += 1) {
          var completedProjectID = projectIdentifier(completedProjects[projectIndex]);
          if (completedProjectID) {
            completedProjectIDs[completedProjectID] = true;
          }
        }

        var completedTaskCount = 0;
        for (var taskIndex = 0; taskIndex < allTasks.length; taskIndex += 1) {
          var completedTask = allTasks[taskIndex];
          var containingProject = safe(function() { return completedTask.containingProject; });
          if (!containingProject) { continue; }
          var containingProjectID = projectIdentifier(containingProject);
          if (!completedProjectIDs[containingProjectID]) { continue; }
          if (!isCompletedStatus(completedTask)) { continue; }

          var taskCompletionDate = getTaskDateTimestamp(completedTask, function(item) { return item.completionDate; });
          if (taskCompletionDate === null) { continue; }
          if (completedAfter && taskCompletionDate < completedAfter.getTime()) { continue; }
          if (completedBefore && taskCompletionDate > completedBefore.getTime()) { continue; }
          completedTaskCount += 1;
        }

        return JSON.stringify({
          projects: completedProjects.length,
          actions: completedTaskCount
        });
      }

      var rawProjectView = (typeof filter.projectView === "string") ? filter.projectView.toLowerCase() : "remaining";
      var projectStatusView = (
        rawProjectView === "active" ||
        rawProjectView === "onhold" ||
        rawProjectView === "on_hold" ||
        rawProjectView === "dropped" ||
        rawProjectView === "done" ||
        rawProjectView === "completed" ||
        rawProjectView === "everything" ||
        rawProjectView === "all"
      ) ? rawProjectView : null;

      var derivedCompleted = (typeof filter.completed === "boolean")
        ? filter.completed
        : (rawProjectView === "everything" ? undefined : false);
      var derivedAvailableOnly = (typeof filter.availableOnly === "boolean")
        ? filter.availableOnly
        : (rawProjectView === "available");

      var resolvedProject = resolveProject(filter.project, allProjects);
      var baseTasks = [];
      var projectRootCandidates = [];
      if (filter.project && !resolvedProject) {
        baseTasks = [];
      } else if (resolvedProject) {
        baseTasks = toTaskArray(safe(function() { return resolvedProject.flattenedTasks; }));
        projectRootCandidates = [resolvedProject];
      } else {
        baseTasks = allTasks;
        projectRootCandidates = allProjects;
      }
      baseTasks = appendTaggedProjectRootTasks(baseTasks, projectRootCandidates, filter.tags);

      var filterState = {
        completed: derivedCompleted,
        flagged: filter.flagged,
        availableOnly: derivedAvailableOnly,
        projectFilter: filter.project,
        projectView: projectStatusView,
        dueBefore: filter.dueBefore ? parseFilterDate(filter.dueBefore) : null,
        dueAfter: filter.dueAfter ? parseFilterDate(filter.dueAfter) : null,
        plannedBefore: filter.plannedBefore ? parseFilterDate(filter.plannedBefore) : null,
        plannedAfter: filter.plannedAfter ? parseFilterDate(filter.plannedAfter) : null,
        deferBefore: filter.deferBefore ? parseFilterDate(filter.deferBefore) : null,
        deferAfter: filter.deferAfter ? parseFilterDate(filter.deferAfter) : null,
        completedBefore: filter.completedBefore ? parseFilterDate(filter.completedBefore) : null,
        completedAfter: filter.completedAfter ? parseFilterDate(filter.completedAfter) : null,
        tags: Array.isArray(filter.tags) ? filter.tags : null,
        untaggedOnly: Array.isArray(filter.tags) && filter.tags.length === 0,
        maxEstimatedMinutes: filter.maxEstimatedMinutes,
        minEstimatedMinutes: filter.minEstimatedMinutes
      };

      function matchesFilters(task) {
        var project = safe(function() { return task.containingProject; });
        if (!project) { return false; }

        if (filterState.completed !== undefined) {
          if (isCompletedStatus(task) !== filterState.completed) { return false; }
        } else if (rawProjectView !== "everything") {
          if (!isRemainingStatus(task)) { return false; }
        }

        if (filterState.flagged !== undefined) {
          if (isTaskEffectivelyFlagged(task) !== filterState.flagged) { return false; }
        }


        if (filterState.availableOnly && !isTaskAvailable(task)) { return false; }

        if (filterState.projectFilter) {
          if (projectIdentifier(project) !== filterState.projectFilter && projectName(project) !== filterState.projectFilter) {
            return false;
          }
        }

        if (filterState.projectView) {
          if (!projectMatchesView(project, filterState.projectView, true)) { return false; }
        }

        if (filterState.dueBefore) {
          var dueBefore = getTaskDateTimestamp(task, function(item) { return item.dueDate; });
          if (dueBefore === null || dueBefore > filterState.dueBefore.getTime()) { return false; }
        }
        if (filterState.dueAfter) {
          var dueAfter = getTaskDateTimestamp(task, function(item) { return item.dueDate; });
          if (dueAfter === null || dueAfter < filterState.dueAfter.getTime()) { return false; }
        }
        if (filterState.deferBefore) {
          var deferBefore = getTaskDateTimestamp(task, function(item) { return item.deferDate; });
          if (deferBefore === null || deferBefore > filterState.deferBefore.getTime()) { return false; }
        }
        if (filterState.deferAfter) {
          var deferAfter = getTaskDateTimestamp(task, function(item) { return item.deferDate; });
          if (deferAfter === null || deferAfter < filterState.deferAfter.getTime()) { return false; }
        }
        if (filterState.plannedBefore) {
          var plannedBefore = getTaskDateTimestamp(task, function(item) { return item.plannedDate; });
          if (plannedBefore === null || plannedBefore > filterState.plannedBefore.getTime()) { return false; }
        }
        if (filterState.plannedAfter) {
          var plannedAfter = getTaskDateTimestamp(task, function(item) { return item.plannedDate; });
          if (plannedAfter === null || plannedAfter < filterState.plannedAfter.getTime()) { return false; }
        }
        if (filterState.completedBefore) {
          var completedBeforeTimestamp = getTaskDateTimestamp(task, function(item) { return item.completionDate; });
          if (completedBeforeTimestamp === null || completedBeforeTimestamp > filterState.completedBefore.getTime()) { return false; }
        }
        if (filterState.completedAfter) {
          var completedAfterTimestamp = getTaskDateTimestamp(task, function(item) { return item.completionDate; });
          if (completedAfterTimestamp === null || completedAfterTimestamp < filterState.completedAfter.getTime()) { return false; }
        }
        if (filterState.maxEstimatedMinutes !== undefined) {
          var maxMinutes = safe(function() { return task.estimatedMinutes; });
          if (maxMinutes === null || maxMinutes === undefined || maxMinutes > filterState.maxEstimatedMinutes) { return false; }
        }
        if (filterState.minEstimatedMinutes !== undefined) {
          var minMinutes = safe(function() { return task.estimatedMinutes; });
          if (minMinutes === null || minMinutes === undefined || minMinutes < filterState.minEstimatedMinutes) { return false; }
        }
        if (filterState.tags && !tagMatchesFilter(task, filterState.tags, filterState.untaggedOnly)) {
          return false;
        }

        return true;
      }

      var projectIDs = {};
      var actionCount = 0;
      for (var baseIndex = 0; baseIndex < baseTasks.length; baseIndex += 1) {
        var task = baseTasks[baseIndex];
        if (!matchesFilters(task)) { continue; }
        var taskProject = safe(function() { return task.containingProject; });
        if (!taskProject) { continue; }
        var taskProjectID = projectIdentifier(taskProject);
        if (taskProjectID) {
          projectIDs[taskProjectID] = true;
        }
        actionCount += 1;
      }

      return JSON.stringify({
        projects: Object.keys(projectIDs).length,
        actions: actionCount
      });
    })();
    """
}

private func jsStringLiteral(_ value: String) -> String {
    let data = try? JSONEncoder().encode(value)
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
}
#endif
