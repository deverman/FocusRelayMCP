import Foundation
import JavaScriptCore
import Testing
@testable import OmniFocusAutomation
import OmniFocusCore

private struct ProjectTaskCountResult: Decodable {
    let availableTasks: Int
    let remainingTasks: Int
    let completedTasks: Int
    let droppedTasks: Int
    let totalTasks: Int
}

@Test
func projectTaskCountsUseEveryNativeAvailableStatus() throws {
    let result = try evaluateProjectTaskCounts(
        projectStatus: "Active",
        taskSetup: """
        [
          task(Task.Status.Available),
          task(Task.Status.Next),
          task(Task.Status.DueSoon),
          task(Task.Status.Overdue),
          task(Task.Status.Blocked),
          task(Task.Status.Completed),
          task(Task.Status.Dropped)
        ]
        """
    )

    #expect(result.availableTasks == 4)
    #expect(result.remainingTasks == 5)
    #expect(result.completedTasks == 1)
    #expect(result.droppedTasks == 1)
    #expect(result.totalTasks == 7)
}

@Test(arguments: ["OnHold", "Dropped", "Done"])
func nonActiveProjectsHaveNoAvailableTasks(projectStatus: String) throws {
    let result = try evaluateProjectTaskCounts(
        projectStatus: projectStatus,
        taskSetup: "[task(Task.Status.Available), task(Task.Status.Overdue)]"
    )

    #expect(result.availableTasks == 0)
    #expect(result.remainingTasks == 2)
}

@Test(arguments: ["Completed", "Dropped"])
func completedOrDroppedParentsHideChildrenFromAvailableAndRemaining(parentStatus: String) throws {
    let result = try evaluateProjectTaskCounts(
        projectStatus: "Active",
        taskSetup: """
        (() => {
          const parent = task(Task.Status.\(parentStatus));
          return [parent, task(Task.Status.Available, parent)];
        })()
        """
    )

    #expect(result.availableTasks == 0)
    #expect(result.remainingTasks == 0)
    #expect(result.completedTasks == (parentStatus == "Completed" ? 1 : 0))
    #expect(result.droppedTasks == (parentStatus == "Dropped" ? 1 : 0))
    #expect(result.totalTasks == 2)
}

@Test
func jxaProjectCountsMatchTheSharedStatusContract() throws {
    let request = """
    {"page":{"limit":10},"statusFilter":"all","includeTaskCounts":true,"fields":["id","name"]}
    """
    let automationScript = listProjectsOmniAutomationScript(requestJSON: request)
    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }
    let bootstrap = """
    const Task = { Status: {
      Available: "Available", Next: "Next", DueSoon: "DueSoon", Overdue: "Overdue",
      Blocked: "Blocked", Completed: "Completed", Dropped: "Dropped"
    }};
    const Project = { Status: {
      Active: "Active", OnHold: "OnHold", Dropped: "Dropped", Done: "Done"
    }};
    function task(status, parent) {
      return { taskStatus: status, parent: parent || null };
    }
    const completedParent = task(Task.Status.Completed);
    const flattenedProjects = [
      {
        id: { primaryKey: "active" }, name: "Active", status: Project.Status.Active,
        flattenedTasks: [
          task(Task.Status.DueSoon), task(Task.Status.Overdue), task(Task.Status.Blocked),
          completedParent, task(Task.Status.Available, completedParent)
        ]
      },
      {
        id: { primaryKey: "on-hold" }, name: "On Hold", status: Project.Status.OnHold,
        flattenedTasks: [task(Task.Status.Available)]
      }
    ];
    """
    guard let json = context.evaluateScript(bootstrap + automationScript)?.toString(), exceptionMessage == nil else {
        throw ProjectTaskCountTestError.javaScript(exceptionMessage ?? "No result")
    }
    let page = try JSONDecoder().decode(ProjectTaskCountPage.self, from: Data(json.utf8))
    let active = try #require(page.items.first { $0.id == "active" })
    let onHold = try #require(page.items.first { $0.id == "on-hold" })

    #expect(active.availableTasks == 2)
    #expect(active.remainingTasks == 3)
    #expect(active.completedTasks == 1)
    #expect(active.totalTasks == 5)
    #expect(onHold.availableTasks == 0)
    #expect(onHold.remainingTasks == 1)
}

@Test
func bridgeProjectAvailableCountsMatchProjectScopedTaskQueriesLive() throws {
    guard ProcessInfo.processInfo.environment["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else { return }

    let client = BridgeClient()
    let projects = try client.listProjects(
        page: PageRequest(limit: 10),
        statusFilter: "active",
        includeTaskCounts: true,
        reviewDueBefore: nil,
        reviewDueAfter: nil,
        reviewPerspective: false,
        completed: nil,
        completedBefore: nil,
        completedAfter: nil,
        fields: ["id", "name"]
    )

    for project in projects.items {
        let tasks = try client.listTasks(
            filter: TaskFilter(availableOnly: true, project: project.id, includeTotalCount: true),
            page: PageRequest(limit: 1),
            fields: ["id"]
        )
        #expect(project.availableTasks == tasks.totalCount, "Available count mismatch for project \(project.name)")
    }
}

@Test
func bridgeAndJXAProjectTaskCountsMatchLive() async throws {
    guard ProcessInfo.processInfo.environment["FOCUS_RELAY_PARITY_TESTS"] == "1" else { return }

    let bridge = OmniFocusBridgeService()
    let jxa = OmniAutomationService()
    let page = PageRequest(limit: 200)
    let fields = ["id", "name"]
    let bridgeProjects = try await bridge.listProjects(
        page: page, statusFilter: "active", includeTaskCounts: true,
        reviewDueBefore: nil, reviewDueAfter: nil, reviewPerspective: false,
        completed: nil, completedBefore: nil, completedAfter: nil, fields: fields
    )
    let jxaProjects = try await jxa.listProjects(
        page: page, statusFilter: "active", includeTaskCounts: true,
        reviewDueBefore: nil, reviewDueAfter: nil, reviewPerspective: false,
        completed: nil, completedBefore: nil, completedAfter: nil, fields: fields
    )
    let bridgeCounts = Dictionary(uniqueKeysWithValues: bridgeProjects.items.map {
        ($0.id, [$0.availableTasks, $0.remainingTasks, $0.completedTasks, $0.droppedTasks, $0.totalTasks])
    })
    let jxaCounts = Dictionary(uniqueKeysWithValues: jxaProjects.items.map {
        ($0.id, [$0.availableTasks, $0.remainingTasks, $0.completedTasks, $0.droppedTasks, $0.totalTasks])
    })

    #expect(bridgeCounts == jxaCounts)
}

private func evaluateProjectTaskCounts(
    projectStatus: String,
    taskSetup: String
) throws -> ProjectTaskCountResult {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let librarySource = try String(contentsOf: sourceURL, encoding: .utf8)
    let startMarker = "// STATUS MODULE - Single Source of Truth for OmniFocus Status"
    let endMarker = "// END STATUS MODULE"
    guard let start = librarySource.range(of: startMarker),
          let end = librarySource.range(of: endMarker, range: start.upperBound..<librarySource.endIndex) else {
        throw ProjectTaskCountTestError.missingStatusModule
    }
    let statusModule = String(librarySource[start.lowerBound..<end.upperBound])

    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }
    let script = """
    const Task = { Status: {
      Available: "Available", Next: "Next", DueSoon: "DueSoon", Overdue: "Overdue",
      Blocked: "Blocked", Completed: "Completed", Dropped: "Dropped"
    }};
    const Project = { Status: {
      Active: "Active", OnHold: "OnHold", Dropped: "Dropped", Done: "Done"
    }};
    function safe(fn) { try { return fn(); } catch (_) { return null; } }
    \(statusModule)
    function task(status, parent) {
      return { taskStatus: status, parent: parent || null, containingProject: null };
    }
    const project = { status: Project.Status.\(projectStatus) };
    JSON.stringify(summarizeProjectTaskCounts(project, \(taskSetup)));
    """

    guard let json = context.evaluateScript(script)?.toString(), exceptionMessage == nil else {
        throw ProjectTaskCountTestError.javaScript(exceptionMessage ?? "No result")
    }
    return try JSONDecoder().decode(ProjectTaskCountResult.self, from: Data(json.utf8))
}

private enum ProjectTaskCountTestError: Error {
    case missingStatusModule
    case javaScript(String)
}

private struct ProjectTaskCountPage: Decodable {
    let items: [ProjectTaskCountItem]
}

private struct ProjectTaskCountItem: Decodable {
    let id: String
    let availableTasks: Int
    let remainingTasks: Int
    let completedTasks: Int
    let totalTasks: Int
}
