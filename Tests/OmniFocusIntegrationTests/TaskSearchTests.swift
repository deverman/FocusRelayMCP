import Foundation
import JavaScriptCore
import Testing
@testable import OmniFocusAutomation

@Test
func pluginTaskSearchMatchesNameAndNoteCaseInsensitively() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let librarySource = try String(contentsOf: sourceURL, encoding: .utf8)
    let module = try extractTaskSearchModule(from: librarySource)

    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }
    let result = context.evaluateScript(
        """
        function safe(fn) { try { return fn(); } catch (_) { return null; } }
        \(module)
        JSON.stringify({
          normalized: normalizeTaskSearchQuery("  ALpHa  "),
          blank: normalizeTaskSearchQuery("   "),
          nameMatch: taskMatchesSearch({ name: "Alpha task", note: "" }, "alpha"),
          noteMatch: taskMatchesSearch({ name: "Other", note: "Contains ALPHA here" }, "alpha"),
          miss: taskMatchesSearch({ name: "Other", note: "Nothing" }, "alpha")
        });
        """
    )?.toString()

    #expect(exceptionMessage == nil)
    let json = try #require(result)
    let decoded = try JSONDecoder().decode(SearchModuleResult.self, from: Data(json.utf8))
    #expect(decoded.normalized == "alpha")
    #expect(decoded.blank == nil)
    #expect(decoded.nameMatch)
    #expect(decoded.noteMatch)
    #expect(!decoded.miss)
}

@Test
func jxaListAndCountSearchHaveMatchingSemantics() throws {
    let request = """
    {"filter":{"inboxView":"everything","availableOnly":false,"search":"  ALPHA  ","includeTotalCount":true},"page":{"limit":50},"fields":["id","name","note"]}
    """
    let bootstrap = """
    const Task = { Status: {
      Available: "Available", Next: "Next", DueSoon: "DueSoon", Overdue: "Overdue",
      Blocked: "Blocked", Completed: "Completed", Dropped: "Dropped"
    }};
    const Project = { Status: {
      Active: "Active", OnHold: "OnHold", Dropped: "Dropped", Done: "Done"
    }};
    function task(id, name, note) {
      return {
        id: { primaryKey: id }, name: name, note: note, taskStatus: Task.Status.Available,
        parent: null, containingProject: null, tags: [], flagged: false,
        dueDate: null, deferDate: null, plannedDate: null, completionDate: null,
        estimatedMinutes: null
      };
    }
    const flattenedTasks = [
      task("name", "Alpha task", ""),
      task("note", "Other", "Contains ALPHA in its note"),
      task("miss", "Other", "Nothing relevant")
    ];
    const flattenedProjects = [];
    const inbox = [];
    """

    let listJSON = try evaluate(
        bootstrap + listTasksOmniAutomationScript(requestJSON: request)
    )
    let countJSON = try evaluate(
        bootstrap + taskCountsOmniAutomationScript(requestJSON: request)
    )

    let page = try JSONDecoder().decode(SearchTaskPage.self, from: Data(listJSON.utf8))
    let counts = try JSONDecoder().decode(SearchTaskCounts.self, from: Data(countJSON.utf8))

    #expect(page.items.map(\.id) == ["name", "note"])
    #expect(page.totalCount == 2)
    #expect(counts.total == 2)
    #expect(counts.available == 2)
}

private func extractTaskSearchModule(from source: String) throws -> String {
    let startMarker = "// TASK SEARCH MODULE - Shared name/note matching semantics"
    let endMarker = "// END TASK SEARCH MODULE"
    guard let start = source.range(of: startMarker),
          let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
        throw TaskSearchTestError.missingModule
    }
    return String(source[start.lowerBound..<end.upperBound])
}

private func evaluate(_ script: String) throws -> String {
    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }
    let result = context.evaluateScript(script)?.toString()
    guard let result, exceptionMessage == nil else {
        throw TaskSearchTestError.javaScript(exceptionMessage ?? "No result")
    }
    return result
}

private struct SearchModuleResult: Decodable {
    let normalized: String
    let blank: String?
    let nameMatch: Bool
    let noteMatch: Bool
    let miss: Bool
}

private struct SearchTaskPage: Decodable {
    let items: [SearchTask]
    let totalCount: Int
}

private struct SearchTask: Decodable {
    let id: String
}

private struct SearchTaskCounts: Decodable {
    let total: Int
    let available: Int
}

private enum TaskSearchTestError: Error {
    case missingModule
    case javaScript(String)
}
