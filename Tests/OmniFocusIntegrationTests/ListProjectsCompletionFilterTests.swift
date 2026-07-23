import Foundation
import JavaScriptCore
import Testing

/// Regression coverage for #97: completion windows must not be emptied by default statusFilter=active.
@Test
func projectCompletionQuerySkipsDefaultActiveStatusFilter() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let librarySource = try String(contentsOf: sourceURL, encoding: .utf8)
    let startMarker = "// PROJECT COMPLETION QUERY MODULE - list_projects completion vs statusFilter"
    let endMarker = "// END PROJECT COMPLETION QUERY MODULE"
    guard let start = librarySource.range(of: startMarker),
          let end = librarySource.range(of: endMarker, range: start.upperBound..<librarySource.endIndex) else {
        Issue.record("Missing PROJECT COMPLETION QUERY MODULE in BridgeLibrary.js")
        return
    }
    let module = String(librarySource[start.lowerBound..<end.upperBound])

    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }

    let script = """
    \(module)
    const projects = [
      { id: "active", status: "Active", completionDate: null },
      { id: "done-in-window", status: "Done", completionDate: new Date("2026-01-15T12:00:00Z") },
      { id: "done-out-of-window", status: "Done", completionDate: new Date("2025-01-01T12:00:00Z") },
      { id: "dropped", status: "Dropped", completionDate: new Date("2026-01-15T12:00:00Z") }
    ];
    const filter = {
      completed: true,
      completedAfter: "2026-01-01T00:00:00Z",
      completedBefore: "2026-02-01T00:00:00Z"
    };
    const statusFilter = "active";
    const isCompletionQuery = isProjectCompletionQuery(filter);
    const applyStatus = shouldApplyListProjectsStatusFilter(statusFilter, false, isCompletionQuery);
    let filtered = projects;
    if (applyStatus) {
      filtered = filtered.filter(p => p.status === "Active");
    }
    // Mirror list_projects completion pass (Done + inclusive window).
    const after = new Date(filter.completedAfter).getTime();
    const before = new Date(filter.completedBefore).getTime();
    filtered = filtered.filter(p => {
      if (p.status !== "Done") return false;
      if (!p.completionDate) return false;
      const ts = p.completionDate.getTime();
      if (ts < after) return false;
      if (ts > before) return false;
      return true;
    });
    JSON.stringify({
      isCompletionQuery: isCompletionQuery,
      applyStatus: applyStatus,
      ids: filtered.map(p => p.id)
    });
    """

    guard let json = context.evaluateScript(script)?.toString(), exceptionMessage == nil else {
        Issue.record("JS evaluation failed: \(exceptionMessage ?? "no result")")
        return
    }
    struct Result: Decodable {
        let isCompletionQuery: Bool
        let applyStatus: Bool
        let ids: [String]
    }
    let decoded = try JSONDecoder().decode(Result.self, from: Data(json.utf8))
    #expect(decoded.isCompletionQuery)
    #expect(!decoded.applyStatus)
    #expect(decoded.ids == ["done-in-window"])
}

@Test
func projectCompletionQueryHelpersIgnoreNonCompletionFilters() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let librarySource = try String(contentsOf: sourceURL, encoding: .utf8)
    let startMarker = "// PROJECT COMPLETION QUERY MODULE - list_projects completion vs statusFilter"
    let endMarker = "// END PROJECT COMPLETION QUERY MODULE"
    guard let start = librarySource.range(of: startMarker),
          let end = librarySource.range(of: endMarker, range: start.upperBound..<librarySource.endIndex) else {
        Issue.record("Missing PROJECT COMPLETION QUERY MODULE in BridgeLibrary.js")
        return
    }
    let module = String(librarySource[start.lowerBound..<end.upperBound])

    let context = JSContext()!
    let script = """
    \(module)
    JSON.stringify({
      plainActive: isProjectCompletionQuery({ statusFilter: "active" }),
      completedFalse: isProjectCompletionQuery({ completed: false }),
      afterOnly: isProjectCompletionQuery({ completedAfter: "2026-01-01T00:00:00Z" }),
      applyActive: shouldApplyListProjectsStatusFilter("active", false, false),
      applyAll: shouldApplyListProjectsStatusFilter("all", false, false),
      applyReview: shouldApplyListProjectsStatusFilter("active", true, false)
    });
    """
    let json = try #require(context.evaluateScript(script)?.toString())
    struct Result: Decodable {
        let plainActive: Bool
        let completedFalse: Bool
        let afterOnly: Bool
        let applyActive: Bool
        let applyAll: Bool
        let applyReview: Bool
    }
    let decoded = try JSONDecoder().decode(Result.self, from: Data(json.utf8))
    #expect(!decoded.plainActive)
    #expect(!decoded.completedFalse)
    #expect(decoded.afterOnly)
    #expect(decoded.applyActive)
    #expect(!decoded.applyAll)
    #expect(decoded.applyReview)
}

@Test
func reviewPerspectiveHonorsStatusFilterBeforeCountAndPagination() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let librarySource = try String(contentsOf: sourceURL, encoding: .utf8)
    let startMarker = "// PROJECT COMPLETION QUERY MODULE - list_projects completion vs statusFilter"
    let endMarker = "// END PROJECT COMPLETION QUERY MODULE"
    let start = try #require(librarySource.range(of: startMarker))
    let end = try #require(
        librarySource.range(of: endMarker, range: start.upperBound..<librarySource.endIndex)
    )
    let module = String(librarySource[start.lowerBound..<end.upperBound])

    let context = JSContext()!
    let script = """
    const Project = { Status: {
      Active: "Active",
      OnHold: "OnHold",
      Dropped: "Dropped",
      Done: "Done"
    }};
    \(module)
    const projects = [
      { id: "active-1", status: Project.Status.Active },
      { id: "hold-1", status: Project.Status.OnHold },
      { id: "active-2", status: Project.Status.Active },
      { id: "dropped-1", status: Project.Status.Dropped },
      { id: "done-1", status: Project.Status.Done }
    ];
    function reviewPage(statusFilter, limit) {
      const filtered = projects.filter(project => {
        const reviewable =
          project.status !== Project.Status.Dropped &&
          project.status !== Project.Status.Done;
        return reviewable && projectMatchesListStatus(project.status, statusFilter);
      });
      return {
        ids: filtered.slice(0, limit).map(project => project.id),
        totalCount: filtered.length,
        nextCursor: filtered.length > limit ? String(limit) : null
      };
    }
    JSON.stringify({
      active: reviewPage("active", 1),
      onHold: reviewPage("onhold", 10),
      all: reviewPage("all", 10)
    });
    """
    let json = try #require(context.evaluateScript(script)?.toString())
    struct Result: Decodable {
        struct Page: Decodable {
            let ids: [String]
            let totalCount: Int
            let nextCursor: String?
        }
        let active: Page
        let onHold: Page
        let all: Page
    }
    let decoded = try JSONDecoder().decode(Result.self, from: Data(json.utf8))

    #expect(decoded.active.ids == ["active-1"])
    #expect(decoded.active.totalCount == 2)
    #expect(decoded.active.nextCursor == "1")
    #expect(decoded.onHold.ids == ["hold-1"])
    #expect(decoded.onHold.totalCount == 1)
    #expect(decoded.onHold.nextCursor == nil)
    #expect(decoded.all.ids == ["active-1", "hold-1", "active-2"])
    #expect(decoded.all.totalCount == 3)
    #expect(Set(decoded.active.ids).isDisjoint(with: decoded.onHold.ids))
}
