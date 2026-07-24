import Foundation
import JavaScriptCore
@testable import OmniFocusAutomation
import Testing

@Test
func projectNameSearchIsLiteralCaseInsensitiveAndPrecedesPagination() throws {
    let module = try projectQueryHelperModule()
    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }

    let script = """
    const Project = { Status: {
      Active: "Active",
      OnHold: "OnHold",
      Dropped: "Dropped",
      Done: "Done"
    }};
    function safe(fn) { try { return fn(); } catch (_) { return null; } }
    \(module)
    const projects = [
      { id: "a", name: "Drop test", status: Project.Status.Active },
      { id: "b", name: "Unrelated", status: Project.Status.Active },
      { id: "c", name: "DROP TEST archive", status: Project.Status.Dropped },
      { id: "d", name: "drop only", status: Project.Status.Active },
      { id: "e", name: "test only", status: Project.Status.Active },
      { id: "f", name: "Pre-drop test-post", status: Project.Status.OnHold }
    ];
    function search(query, statusFilter, limit) {
      const normalized = normalizedProjectNameSearch(query);
      const filtered = projects.filter(project =>
        projectMatchesListStatus(project.status, statusFilter) &&
        projectMatchesNameSearch(project, normalized)
      );
      return {
        ids: filtered.slice(0, limit).map(project => project.id),
        totalCount: filtered.length,
        nextCursor: filtered.length > limit ? String(limit) : null
      };
    }
    JSON.stringify({
      all: search("  drop test  ", "all", 2),
      active: search("DROP TEST", "active", 10),
      partial: search("test-po", "all", 10)
    });
    """
    let json = try #require(context.evaluateScript(script)?.toString())
    #expect(exceptionMessage == nil)

    struct Result: Decodable {
        struct Page: Decodable {
            let ids: [String]
            let totalCount: Int
            let nextCursor: String?
        }
        let all: Page
        let active: Page
        let partial: Page
    }
    let decoded = try JSONDecoder().decode(Result.self, from: Data(json.utf8))

    #expect(decoded.all.ids == ["a", "c"])
    #expect(decoded.all.totalCount == 3)
    #expect(decoded.all.nextCursor == "2")
    #expect(decoded.active.ids == ["a"])
    #expect(decoded.active.totalCount == 1)
    #expect(decoded.partial.ids == ["f"])
}

@Test
func projectSearchNormalizationRejectsWhitespaceOnlyInput() throws {
    #expect(try OmniFocusBridgeService.normalizeProjectSearch("  Drop test \n") == "Drop test")
    #expect(try OmniFocusBridgeService.normalizeProjectSearch(nil) == nil)
    #expect(throws: AutomationError.self) {
        try OmniFocusBridgeService.normalizeProjectSearch(" \t\n ")
    }
}

private func projectQueryHelperModule() throws -> String {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let startMarker = "// PROJECT COMPLETION QUERY MODULE - list_projects completion vs statusFilter"
    let endMarker = "// END PROJECT COMPLETION QUERY MODULE"
    let start = try #require(source.range(of: startMarker))
    let end = try #require(
        source.range(of: endMarker, range: start.upperBound..<source.endIndex)
    )
    return String(source[start.lowerBound..<end.upperBound])
}
