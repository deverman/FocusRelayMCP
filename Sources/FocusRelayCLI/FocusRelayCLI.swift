import ArgumentParser
import Foundation
import FocusRelayServer
import OmniFocusAutomation
import OmniFocusCore
import FocusRelayOutput

@main
struct FocusRelayCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focusrelay",
        abstract: "Query OmniFocus data from the command line or run the MCP server.",
        subcommands: [
            Serve.self,
            ListTasks.self,
            GetTask.self,
            ListProjects.self,
            ListTags.self,
            UpdateTasks.self,
            SetTasksCompletion.self,
            MoveTasks.self,
            UpdateProjects.self,
            SetProjectsStatus.self,
            TaskCounts.self,
            ProjectCounts.self,
            DebugInboxProbe.self,
            DebugInboxProbeAlt.self,
            BridgeHealthCheck.self,
            BenchmarkTaskCounts.self,
            BenchmarkListTasks.self,
            BenchmarkProjectCounts.self,
            BenchmarkGateCheck.self
        ]
    )
}

struct Serve: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Run the MCP server.",
        aliases: ["mcp", "server"]
    )

    func run() async throws {
        try await FocusRelayServer.run()
    }
}

struct ListTasks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-tasks",
        abstract: "List OmniFocus tasks.",
        aliases: ["list_tasks"]
    )

    @OptionGroup var filter: TaskFilterOptions
    @OptionGroup var page: PageOptions

    @Option(help: "Comma-separated field names to return.")
    var fields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let taskFilter = try filter.makeTaskFilter()
        let pageRequest = page.makePageRequest(defaultLimit: 50)
        let fieldList = FieldList.parse(fields)
        let selectedFields = fieldList.isEmpty ? ["id", "name"] : fieldList

        let result = try await service.listTasks(filter: taskFilter, page: pageRequest, fields: selectedFields)
        let fieldSet = Set(selectedFields)
        let items = result.items.map { makeTaskOutput(from: $0, fields: fieldSet) }
        let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount)
        print(try encodeJSON(output))
    }
}

struct GetTask: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get-task",
        abstract: "Get a single task by ID.",
        aliases: ["get_task"]
    )

    @Argument(help: "Task identifier.")
    var id: String

    @Option(help: "Comma-separated field names to return.")
    var fields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let fieldList = FieldList.parse(fields)
        let selectedFields = fieldList.isEmpty ? ["id", "name"] : fieldList

        let result = try await service.getTask(id: id, fields: selectedFields)
        let output = makeTaskOutput(from: result, fields: Set(selectedFields))
        print(try encodeJSON(output))
    }
}

struct ListProjects: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-projects",
        abstract: "List OmniFocus projects.",
        aliases: ["list_projects"]
    )

    @OptionGroup var page: PageOptions

    @Option(name: .customLong("status"), help: "Project status filter: active, onHold, dropped, done, all.")
    var statusFilter: String = "active"

    @Flag(name: .customLong("include-task-counts"), help: "Include task counts for each project.")
    var includeTaskCounts: Bool = false

    @Flag(name: .customLong("review-perspective"), help: "Apply review perspective defaults.")
    var reviewPerspective: Bool = false

    @Option(name: .customLong("review-due-before"), help: "ISO8601 datetime. Next review due before this time.")
    var reviewDueBefore: String?

    @Option(name: .customLong("review-due-after"), help: "ISO8601 datetime. Next review due after this time.")
    var reviewDueAfter: String?

    @Option(name: .customLong("completed"), help: "Filter by completion status (true/false).")
    var completed: Bool?

    @Option(name: .customLong("completed-before"), help: "ISO8601 datetime. Projects completed before this time.")
    var completedBefore: String?

    @Option(name: .customLong("completed-after"), help: "ISO8601 datetime. Projects completed after this time.")
    var completedAfter: String?

    @Option(help: "Comma-separated field names to return.")
    var fields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let pageRequest = page.makePageRequest(defaultLimit: 150)
        let fieldList = FieldList.parse(fields)
        let selectedFields = fieldList.isEmpty ? ["id", "name"] : fieldList
        let reviewBeforeDate = try ISO8601DateParser.parseOptional(reviewDueBefore, argumentName: "--review-due-before")
        let reviewAfterDate = try ISO8601DateParser.parseOptional(reviewDueAfter, argumentName: "--review-due-after")
        let completedBeforeDate = try ISO8601DateParser.parseOptional(completedBefore, argumentName: "--completed-before")
        let completedAfterDate = try ISO8601DateParser.parseOptional(completedAfter, argumentName: "--completed-after")

        let result = try await service.listProjects(
            page: pageRequest,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            reviewDueBefore: reviewBeforeDate,
            reviewDueAfter: reviewAfterDate,
            reviewPerspective: reviewPerspective,
            completed: completed,
            completedBefore: completedBeforeDate,
            completedAfter: completedAfterDate,
            fields: selectedFields
        )
        let fieldSet = Set(selectedFields)
        let items = result.items.map { makeProjectOutput(from: $0, fields: fieldSet, includeTaskCounts: includeTaskCounts) }
        let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount)
        print(try encodeJSON(output))
    }
}

struct ListTags: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-tags",
        abstract: "List OmniFocus tags.",
        aliases: ["list_tags"]
    )

    @OptionGroup var page: PageOptions

    @Option(name: .customLong("status"), help: "Tag status filter: active, onHold, dropped, all.")
    var statusFilter: String = "active"

    @Flag(name: .customLong("include-task-counts"), help: "Include task counts for each tag.")
    var includeTaskCounts: Bool = false

    func run() async throws {
        let service = OmniFocusBridgeService()
        let pageRequest = page.makePageRequest(defaultLimit: 150)

        let result = try await service.listTags(page: pageRequest, statusFilter: statusFilter, includeTaskCounts: includeTaskCounts)
        let fieldSet: Set<String> = ["id", "name", "status", "availableTasks", "remainingTasks", "totalTasks"]
        let items = result.items.map { makeTagOutput(from: $0, fields: fieldSet, includeTaskCounts: includeTaskCounts) }
        let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount)
        print(try encodeJSON(output))
    }
}

struct UpdateTasks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-tasks",
        abstract: "Apply one shared task patch to multiple task IDs.",
        aliases: ["update_tasks"]
    )

    @Argument(help: "Task IDs to update.")
    var ids: [String] = []

    @OptionGroup var patch: TaskPatchOptions

    @Flag(name: .customLong("preview-only"), help: "Validate and resolve targets without mutating.")
    var previewOnly: Bool = false

    @Flag(help: "Verify the final state after mutation.")
    var verify: Bool = false

    @Option(name: .customLong("return-fields"), help: "Comma-separated task fields to include in per-item results.")
    var returnFields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let request = MutationRequest(
            targetType: .task,
            targetIDs: ids,
            operation: MutationOperation(
                kind: .updateTasks,
                taskPatch: try patch.makeTaskPatchMutation()
            ),
            previewOnly: previewOnly,
            verify: verify,
            returnFields: FieldList.parse(returnFields)
        )

        let result = try await service.performMutation(request)
        print(try encodeJSON(result))
    }
}

struct SetTasksCompletion: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-tasks-completion",
        abstract: "Apply one shared task completion state to multiple task IDs.",
        aliases: ["set_tasks_completion"]
    )

    @Argument(help: "Task IDs to update.")
    var ids: [String] = []

    @Option(help: "Lifecycle state to apply: active or completed.")
    var state: MutationCompletionState

    @Flag(name: .customLong("preview-only"), help: "Validate and resolve targets without mutating.")
    var previewOnly: Bool = false

    @Flag(help: "Verify the final state after mutation.")
    var verify: Bool = false

    @Option(name: .customLong("return-fields"), help: "Comma-separated task fields to include in per-item results.")
    var returnFields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let request = MutationRequest(
            targetType: .task,
            targetIDs: ids,
            operation: MutationOperation(
                kind: .setTasksCompletion,
                completion: CompletionMutation(state: state)
            ),
            previewOnly: previewOnly,
            verify: verify,
            returnFields: FieldList.parse(returnFields)
        )

        let result = try await service.performMutation(request)
        print(try encodeJSON(result))
    }
}

struct MoveTasks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move-tasks",
        abstract: "Move or reparent multiple tasks to one shared destination.",
        aliases: ["move_tasks"]
    )

    @Argument(help: "Task IDs to move.")
    var ids: [String] = []

    @Option(help: "Destination kind: inbox, project, or parent_task.")
    var destinationKind: MutationMoveDestinationKind

    @Option(help: "Destination ID for project or parent_task moves.")
    var destinationID: String?

    @Option(help: "Placement within the destination: beginning or ending.")
    var position: String = "ending"

    @Flag(name: .customLong("preview-only"), help: "Validate and resolve targets without mutating.")
    var previewOnly: Bool = false

    @Flag(help: "Verify the final state after mutation.")
    var verify: Bool = false

    @Option(name: .customLong("return-fields"), help: "Comma-separated task fields to include in per-item results.")
    var returnFields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let request = MutationRequest(
            targetType: .task,
            targetIDs: ids,
            operation: MutationOperation(
                kind: .moveTasks,
                move: MoveMutation(
                    destinationKind: destinationKind,
                    destinationID: destinationID,
                    position: position
                )
            ),
            previewOnly: previewOnly,
            verify: verify,
            returnFields: FieldList.parse(returnFields)
        )

        let result = try await service.performMutation(request)
        print(try encodeJSON(result))
    }
}

struct UpdateProjects: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-projects",
        abstract: "Apply one shared project patch to multiple project IDs.",
        aliases: ["update_projects"]
    )

    @Argument(help: "Project IDs to update.")
    var ids: [String] = []

    @OptionGroup var patch: ProjectPatchOptions

    @Flag(name: .customLong("preview-only"), help: "Validate and resolve targets without mutating.")
    var previewOnly: Bool = false

    @Flag(help: "Verify the final state after mutation.")
    var verify: Bool = false

    @Option(name: .customLong("return-fields"), help: "Comma-separated project fields to include in per-item results.")
    var returnFields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let request = MutationRequest(
            targetType: .project,
            targetIDs: ids,
            operation: MutationOperation(
                kind: .updateProjects,
                projectPatch: try patch.makeProjectPatchMutation()
            ),
            previewOnly: previewOnly,
            verify: verify,
            returnFields: FieldList.parse(returnFields)
        )

        let result = try await service.performMutation(request)
        print(try encodeJSON(result))
    }
}

struct SetProjectsStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-projects-status",
        abstract: "Apply one shared project status to multiple project IDs.",
        aliases: ["set_projects_status"]
    )

    @Argument(help: "Project IDs to update.")
    var ids: [String] = []

    @Option(help: "Project status to apply: active, on_hold, or dropped.")
    var status: MutationProjectStatus

    @Flag(name: .customLong("preview-only"), help: "Validate and resolve targets without mutating.")
    var previewOnly: Bool = false

    @Flag(help: "Verify the final state after mutation.")
    var verify: Bool = false

    @Option(name: .customLong("return-fields"), help: "Comma-separated project fields to include in per-item results.")
    var returnFields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let request = MutationRequest(
            targetType: .project,
            targetIDs: ids,
            operation: MutationOperation(
                kind: .setProjectsStatus,
                projectStatus: ProjectStatusMutation(status: status)
            ),
            previewOnly: previewOnly,
            verify: verify,
            returnFields: FieldList.parse(returnFields)
        )

        let result = try await service.performMutation(request)
        print(try encodeJSON(result))
    }
}

struct TaskCounts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "task-counts",
        abstract: "Get task counts for a filter.",
        aliases: ["get_task_counts"]
    )

    @OptionGroup var filter: TaskFilterOptions

    func run() async throws {
        let service = OmniFocusBridgeService()
        let taskFilter = try filter.makeTaskFilter()
        let counts = try await service.getTaskCounts(filter: taskFilter)
        print(try encodeJSON(counts))
    }
}

struct ProjectCounts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "project-counts",
        abstract: "Get project/action counts for a filter.",
        aliases: ["get_project_counts"]
    )

    @OptionGroup var filter: TaskFilterOptions

    func run() async throws {
        let service = OmniFocusBridgeService()
        let taskFilter = try filter.makeTaskFilter()
        let counts = try await service.getProjectCounts(filter: taskFilter)
        print(try encodeJSON(counts))
    }
}

struct DebugInboxProbe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "debug-inbox-probe",
        abstract: "Debug inbox query behavior (counts and samples).",
        aliases: ["debug_inbox_probe"]
    )

    func run() async throws {
        let service = OmniAutomationService()
        let result = try await service.debugInboxProbe()
        print(try encodeJSON(result))
    }
}

struct DebugInboxProbeAlt: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "debug-inbox-probe-alt",
        abstract: "Debug inbox query behavior using alternate queries and timings.",
        aliases: ["debug_inbox_probe_alt"]
    )

    func run() async throws {
        let service = OmniAutomationService()
        let result = try await service.debugInboxProbeAlt()
        print(try encodeJSON(result))
    }
}

struct BridgeHealthCheck: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bridge-health-check",
        abstract: "Check OmniFocus bridge plug-in availability and responsiveness.",
        aliases: ["bridge_health_check"]
    )

    func run() async throws {
        let service = OmniFocusBridgeService()
        let result = try service.healthCheck()
        print(try encodeJSON(result))
    }
}
