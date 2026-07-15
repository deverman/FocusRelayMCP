import Foundation
import JavaScriptCore
import Testing
@testable import OmniFocusAutomation
import OmniFocusCore

@Test
func pluginEffectiveFlagModuleUsesNativeStateAndIdentifiesProjectRoots() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let librarySource = try String(contentsOf: sourceURL, encoding: .utf8)
    let module = try extractEffectiveFlagModule(from: librarySource)

    let result = try evaluateEffectiveFlagScript(
        """
        function safe(fn) { try { return fn(); } catch (_) { return null; } }
        \(module)
        const project = { id: { primaryKey: "project" } };
        JSON.stringify({
          direct: isTaskEffectivelyFlagged({ flagged: true, effectiveFlagged: true }),
          inherited: isTaskEffectivelyFlagged({ flagged: false, effectiveFlagged: true }),
          unflagged: isTaskEffectivelyFlagged({ flagged: false, effectiveFlagged: false }),
          root: isProjectRootTask({ id: { primaryKey: "project" }, containingProject: project }),
          action: isProjectRootTask({ id: { primaryKey: "action" }, containingProject: project }),
          inbox: isProjectRootTask({ id: { primaryKey: "inbox" }, containingProject: null })
        });
        """
    )

    let decoded = try JSONDecoder().decode(EffectiveFlagModuleResult.self, from: Data(result.utf8))
    #expect(decoded.direct)
    #expect(decoded.inherited)
    #expect(!decoded.unflagged)
    #expect(decoded.root)
    #expect(!decoded.action)
    #expect(!decoded.inbox)
}

@Test
func jxaListAndCountUseEffectiveFlagsAndExcludeProjectRoots() throws {
    let request = """
    {"filter":{"flagged":true,"includeTotalCount":true},"page":{"limit":50},"fields":["id","flagged","effectiveFlagged"]}
    """
    let bootstrap = """
    const Task = { Status: {
      Available: "Available", Next: "Next", DueSoon: "DueSoon", Overdue: "Overdue",
      Blocked: "Blocked", Completed: "Completed", Dropped: "Dropped"
    }};
    const Project = { Status: {
      Active: "Active", OnHold: "OnHold", Dropped: "Dropped", Done: "Done"
    }};
    const project = {
      id: { primaryKey: "project-root" }, name: "Flagged project",
      status: Project.Status.Active, tags: []
    };
    function task(id, locallyFlagged, effectivelyFlagged, containingProject) {
      return {
        id: { primaryKey: id }, name: id, note: "", taskStatus: Task.Status.Available,
        parent: null, containingProject: containingProject || null, tags: [],
        flagged: locallyFlagged, effectiveFlagged: effectivelyFlagged,
        dueDate: null, deferDate: null, plannedDate: null, completionDate: null,
        estimatedMinutes: null, inInbox: containingProject == null
      };
    }
    const projectRoot = task("project-root", true, true, project);
    project.task = projectRoot;
    project.flattenedTasks = [];
    const flattenedTasks = [
      projectRoot,
      task("direct", true, true, project),
      task("parent-inherited", false, true, project),
      task("project-inherited", false, true, project),
      task("unflagged", false, false, project)
    ];
    const flattenedProjects = [project];
    const inbox = [];
    """

    let listJSON = try evaluateEffectiveFlagScript(
        bootstrap + listTasksOmniAutomationScript(requestJSON: request)
    )
    let countJSON = try evaluateEffectiveFlagScript(
        bootstrap + taskCountsOmniAutomationScript(requestJSON: request)
    )

    let page = try JSONDecoder().decode(EffectiveFlagTaskPage.self, from: Data(listJSON.utf8))
    let counts = try JSONDecoder().decode(EffectiveFlagTaskCounts.self, from: Data(countJSON.utf8))

    #expect(page.items.map(\.id) == ["direct", "parent-inherited", "project-inherited"])
    #expect(page.items.map(\.flagged) == [true, false, false])
    #expect(page.items.allSatisfy { $0.effectiveFlagged == true })
    #expect(page.totalCount == 3)
    #expect(counts.total == 3)
    #expect(counts.available == 3)
    #expect(counts.flagged == 3)
}

@Test(.enabled(if: LiveTestEnvironment.bridgeEnabled, "Set FOCUS_RELAY_BRIDGE_TESTS=1 to run against the installed bridge."))
func bridgeFlaggedTasksMatchNativeEffectiveFlagActionsLive() throws {
    guard ProcessInfo.processInfo.environment["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else { return }

    let filter = TaskFilter(flagged: true, includeTotalCount: true)
    let client = BridgeClient()
    let page = try client.listTasks(
        filter: filter,
        page: PageRequest(limit: 200),
        fields: ["id", "flagged", "effectiveFlagged"]
    )
    let counts = try client.getTaskCounts(filter: filter)
    let nativeIDs = try nativeAvailableEffectiveFlagActionIDs()

    #expect(Set(page.items.map(\.id)) == Set(nativeIDs))
    #expect(page.items.allSatisfy { $0.effectiveFlagged })
    #expect(page.totalCount == nativeIDs.count)
    #expect(counts.total == nativeIDs.count)
    #expect(counts.available == nativeIDs.count)
    #expect(counts.flagged == nativeIDs.count)
}

private func extractEffectiveFlagModule(from source: String) throws -> String {
    let startMarker = "// EFFECTIVE FLAG MODULE - Native Flagged perspective semantics"
    let endMarker = "// END EFFECTIVE FLAG MODULE"
    guard let start = source.range(of: startMarker),
          let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
        throw EffectiveFlagTestError.missingModule
    }
    return String(source[start.lowerBound..<end.upperBound])
}

private func evaluateEffectiveFlagScript(_ script: String) throws -> String {
    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }
    let result = context.evaluateScript(script)?.toString()
    guard let result, exceptionMessage == nil else {
        throw EffectiveFlagTestError.javaScript(exceptionMessage ?? "No result")
    }
    return result
}

private func nativeAvailableEffectiveFlagActionIDs() throws -> [String] {
    let automation = """
    JSON.stringify((function() {
      var available = [Task.Status.Available, Task.Status.Next, Task.Status.DueSoon, Task.Status.Overdue];
      return flattenedTasks.filter(function(task) {
        if (available.indexOf(task.taskStatus) === -1 || !Boolean(task.effectiveFlagged)) { return false; }
        var project = task.containingProject;
        return !project || String(task.id.primaryKey) !== String(project.id.primaryKey);
      }).map(function(task) { return String(task.id.primaryKey); });
    })())
    """
    let literalData = try JSONEncoder().encode(automation)
    let literal = try #require(String(data: literalData, encoding: .utf8))
    let outerScript = """
    (function() {
      var app = Application('OmniFocus');
      var result = app.evaluateJavascript(\(literal));
      if (Array.isArray(result)) {
        if (result.length === 0 || result[0] === null || typeof result[0] === 'undefined') { return '[]'; }
        return String(result[0]);
      }
      return result === null || typeof result === 'undefined' ? '[]' : String(result);
    })();
    """
    let json = try ScriptRunner().runJavaScript(outerScript)
    return try JSONDecoder().decode([String].self, from: Data(json.utf8))
}

private struct EffectiveFlagModuleResult: Decodable {
    let direct: Bool
    let inherited: Bool
    let unflagged: Bool
    let root: Bool
    let action: Bool
    let inbox: Bool
}

private struct EffectiveFlagTaskPage: Decodable {
    let items: [EffectiveFlagTask]
    let totalCount: Int
}

private struct EffectiveFlagTask: Decodable {
    let id: String
    let flagged: Bool
    let effectiveFlagged: Bool?
}

private struct EffectiveFlagTaskCounts: Decodable {
    let total: Int
    let available: Int
    let flagged: Int
}

private enum EffectiveFlagTestError: Error {
    case missingModule
    case javaScript(String)
}
