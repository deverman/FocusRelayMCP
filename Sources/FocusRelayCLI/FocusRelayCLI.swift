import ArgumentParser
import Foundation
import FocusRelayServer
import OmniFocusAutomation
import OmniFocusCore
import FocusRelayOutput
import FocusRelayVersion

@main
struct FocusRelayCLI: AsyncParsableCommand {
    private static var subcommands: [ParsableCommand.Type] {
        var commands: [ParsableCommand.Type] = [
            Serve.self,
            ListTasks.self,
            GetTask.self,
            ListProjects.self,
            ListTags.self,
            ListFolders.self,
            EditTasks.self,
            EditProjects.self,
            TaskCounts.self,
            ProjectCounts.self,
            BridgeHealthCheck.self
        ]

        #if DEBUG
        commands += [
            BenchmarkTaskCounts.self,
            BenchmarkListTasks.self,
            BenchmarkProjectCounts.self,
            BenchmarkGateCheck.self
        ]
        #endif

        return commands
    }

    static let configuration = CommandConfiguration(
        commandName: "focusrelay",
        abstract: "Query OmniFocus data from the command line or run the MCP server.",
        version: FocusRelayBuildVersion.current,
        subcommands: subcommands
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
        let fieldList = try FieldList.parseOutputFields(fields, for: "list_tasks")
        let selectedFields = fieldList.isEmpty ? ["id", "name"] : fieldList

        let result = try await service.listTasks(filter: taskFilter, page: pageRequest, fields: selectedFields)
        let fieldSet = Set(selectedFields)
        let items = result.items.map { makeTaskOutput(from: $0, fields: fieldSet) }
        let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount, unresolvedIDs: result.unresolvedIDs)
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
        let fieldList = try FieldList.parseOutputFields(fields, for: "get_task")
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

    @Option(help: "Search project names by trimmed, case-insensitive literal substring.")
    var search: String?

    @Option(help: "Comma-separated candidate names (max \(BatchNameResolution.maximumSearches)) resolved in one call. Results are grouped per name.")
    var searches: String?

    @Option(name: .customLong("match-limit-per-search"), help: "Maximum matches per requested name (1-\(BatchNameResolution.maximumMatchLimit)).")
    var matchLimitPerSearch: Int?

    @Flag(name: .customLong("include-task-counts"), help: "Include task counts for each project.")
    var includeTaskCounts: Bool = false

    @Flag(name: .customLong("root-only"), help: "Only projects at the library root (not inside any folder).")
    var rootOnly: Bool = false

    @Flag(name: .customLong("review-perspective"), help: "Apply Review due-date defaults while honoring --status (active, onHold, or all reviewable projects).")
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
        let fieldList = try FieldList.parseOutputFields(fields, for: "list_projects")
        let selectedFields = FocusRelayServer.resolvedProjectFields(
            requestedFields: fieldList,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts
        )
        let searchList = FieldList.parse(searches)
        if !searchList.isEmpty {
            let normalized = try BatchNameResolution.normalize(searchList, tool: "list_projects") ?? []
            try BatchNameResolution.validateExclusivity(
                tool: "list_projects",
                hasScalarSearch: search != nil,
                hasCursor: pageRequest.cursor != nil,
                includeTaskCounts: includeTaskCounts
            )
            let matchLimit = try BatchNameResolution.validateMatchLimit(matchLimitPerSearch, tool: "list_projects")
            let batchFields = fieldList.isEmpty ? ["id", "name", "status"] : fieldList
            let groups = try await service.resolveProjectNames(
                searches: normalized,
                matchLimitPerSearch: matchLimit,
                statusFilter: statusFilter,
                fields: batchFields
            )
            let batchFieldSet = Set(batchFields)
            let batchOutput = BatchSearchOutput(searchResults: groups.map { group in
                NameSearchGroupOutput(
                    search: group.search,
                    items: group.items.map { makeProjectOutput(from: $0, fields: batchFieldSet, includeTaskCounts: false) },
                    returnedCount: group.returnedCount,
                    truncated: group.truncated
                )
            })
            print(try encodeJSON(batchOutput))
            return
        }

        let reviewBeforeDate = try ISO8601DateParser.parseOptional(reviewDueBefore, argumentName: "--review-due-before")
        let reviewAfterDate = try ISO8601DateParser.parseOptional(reviewDueAfter, argumentName: "--review-due-after")
        let completedBeforeDate = try ISO8601DateParser.parseOptional(completedBefore, argumentName: "--completed-before")
        let completedAfterDate = try ISO8601DateParser.parseOptional(completedAfter, argumentName: "--completed-after")

        let result = try await service.listProjects(
            page: pageRequest,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            search: search,
            rootOnly: rootOnly,
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

    @Option(help: "Case-insensitive substring to match against tag names.")
    var search: String?

    @Option(help: "Comma-separated candidate names (max \(BatchNameResolution.maximumSearches)) resolved in one call. Results are grouped per name.")
    var searches: String?

    @Option(name: .customLong("match-limit-per-search"), help: "Maximum matches per requested name (1-\(BatchNameResolution.maximumMatchLimit)).")
    var matchLimitPerSearch: Int?

    @Option(help: "Comma-separated field names to return.")
    var fields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let pageRequest = page.makePageRequest(defaultLimit: 150)
        let requestedFields = fields?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        try OutputFieldCatalog.validate(requestedFields, for: "list_tags")
        let tagSearchList = FieldList.parse(searches)
        if !tagSearchList.isEmpty {
            let normalized = try BatchNameResolution.normalize(tagSearchList, tool: "list_tags") ?? []
            try BatchNameResolution.validateExclusivity(
                tool: "list_tags",
                hasScalarSearch: search != nil,
                hasCursor: pageRequest.cursor != nil,
                includeTaskCounts: includeTaskCounts
            )
            let matchLimit = try BatchNameResolution.validateMatchLimit(matchLimitPerSearch, tool: "list_tags")
            let batchFields = requestedFields.isEmpty ? ["id", "name", "path"] : requestedFields
            let groups = try await service.resolveTagNames(
                searches: normalized,
                matchLimitPerSearch: matchLimit,
                statusFilter: statusFilter,
                fields: batchFields
            )
            let batchFieldSet = Set(batchFields)
            let batchOutput = BatchSearchOutput(searchResults: groups.map { group in
                NameSearchGroupOutput(
                    search: group.search,
                    items: group.items.map { makeTagOutput(from: $0, fields: batchFieldSet, includeTaskCounts: false) },
                    returnedCount: group.returnedCount,
                    truncated: group.truncated
                )
            })
            print(try encodeJSON(batchOutput))
            return
        }

        let resolvedFields = FocusRelayServer.resolvedTagFields(
            requestedFields: requestedFields,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts
        )

        let result = try await service.listTags(
            page: pageRequest,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            search: search,
            fields: resolvedFields
        )
        let fieldSet = Set(resolvedFields)
        let items = result.items.map { makeTagOutput(from: $0, fields: fieldSet, includeTaskCounts: includeTaskCounts) }
        let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount)
        print(try encodeJSON(output))
    }
}

struct ListFolders: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-folders",
        abstract: "List OmniFocus folders for project move destination discovery.",
        aliases: ["list_folders"]
    )

    @OptionGroup var page: PageOptions

    @Option(help: "Comma-separated field names to return.")
    var fields: String?

    func run() async throws {
        let service = OmniFocusBridgeService()
        let pageRequest = page.makePageRequest(defaultLimit: 150)
        let fieldList = try FieldList.parseOutputFields(fields, for: "list_folders")
        let selectedFields = fieldList.isEmpty ? ["id", "name"] : fieldList

        let result = try await service.listFolders(page: pageRequest, fields: selectedFields)
        let fieldSet = Set(selectedFields)
        let items = result.items.map { makeFolderOutput(from: $0, fields: fieldSet) }
        let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount)
        print(try encodeJSON(output))
    }
}

struct EditTasks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit-tasks",
        abstract: "Update, drop/restore, complete/reopen, or move existing tasks by ID.",
        aliases: ["edit_tasks"]
    )

    @Argument(help: "Task IDs to edit.")
    var ids: [String] = []

    @Option(help: "Operation: update, set_status, set_completion, or move.")
    var operation: TaskEditOperation

    @OptionGroup var patch: TaskPatchOptions

    @Option(help: "Completion state for set_completion: active or completed.")
    var state: MutationCompletionState?

    @Option(help: "Task status for set_status: active or dropped.")
    var status: MutationTaskStatus?

    @Option(name: .customLong("recurrence-scope"), help: "Repeating drop scope: occurrence or series.")
    var recurrenceScope: MutationRecurrenceScope?

    @Option(help: "Destination kind for move: inbox, project, or parent_task.")
    var destinationKind: MutationMoveDestinationKind?

    @Option(help: "Destination ID for project or parent_task moves.")
    var destinationID: String?

    @Option(help: "Move placement: beginning or ending.")
    var position: String?

    @Flag(name: .customLong("preview-only"), help: "Validate and resolve targets without mutating.")
    var previewOnly: Bool = false

    @Flag(help: "Verify the final state after mutation.")
    var verify: Bool = false

    @Option(name: .customLong("return-fields"), help: "Comma-separated task fields to include in per-item results.")
    var returnFields: String?

    func makeRequest() throws -> MutationRequest {
        let taskPatch = try patch.makeTaskPatchMutation()
        if recurrenceScope != nil, status == nil {
            throw ValidationError("--recurrence-scope requires --status dropped.")
        }
        let hasMovePayload = destinationKind != nil || destinationID != nil || position != nil
        let move: MoveMutation?
        if hasMovePayload {
            guard let destinationKind else {
                throw ValidationError("Task moves require --destination-kind.")
            }
            move = MoveMutation(destinationKind: destinationKind, destinationID: destinationID, position: position)
        } else {
            move = nil
        }

        return try MutationRequest.editTasks(
            targetIDs: ids,
            operation: operation,
            taskPatch: taskPatch.isEmpty ? nil : taskPatch,
            taskStatus: status.map { TaskStatusMutation(status: $0, recurrenceScope: recurrenceScope) },
            completion: state.map(CompletionMutation.init(state:)),
            move: move,
            previewOnly: previewOnly,
            verify: verify,
            returnFields: FieldList.parse(returnFields)
        )
    }

    func run() async throws {
        let service = OmniFocusBridgeService()
        let request = try makeRequest()
        let result = try await service.performMutation(request)
        print(try encodeJSON(result))
    }
}

struct EditProjects: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "edit-projects",
        abstract: "Update, change status/completion, or move existing projects by ID.",
        aliases: ["edit_projects"]
    )

    @Argument(help: "Project IDs to edit.")
    var ids: [String] = []

    @Option(help: "Operation: update, set_status, set_completion, or move.")
    var operation: ProjectEditOperation

    @OptionGroup var patch: ProjectPatchOptions

    @Option(help: "Project status for set_status: active, on_hold, or dropped.")
    var status: MutationProjectStatus?

    @Option(help: "Completion state for set_completion: active or completed.")
    var state: MutationCompletionState?

    @Option(help: "Destination kind for move: folder.")
    var destinationKind: MutationMoveDestinationKind?

    @Option(help: "Destination folder ID. Omit for a root-library move.")
    var destinationID: String?

    @Option(help: "Move placement: beginning or ending.")
    var position: String?

    @Flag(name: .customLong("preview-only"), help: "Validate and resolve targets without mutating.")
    var previewOnly: Bool = false

    @Flag(help: "Verify the final state after mutation.")
    var verify: Bool = false

    @Option(name: .customLong("return-fields"), help: "Comma-separated project fields to include in per-item results.")
    var returnFields: String?

    func makeRequest() throws -> MutationRequest {
        let projectPatch = try patch.makeProjectPatchMutation()
        let hasMovePayload = destinationKind != nil || destinationID != nil || position != nil
        let move: MoveMutation?
        if hasMovePayload {
            guard let destinationKind else {
                throw ValidationError("Project moves require --destination-kind folder.")
            }
            move = MoveMutation(destinationKind: destinationKind, destinationID: destinationID, position: position)
        } else {
            move = nil
        }

        return try MutationRequest.editProjects(
            targetIDs: ids,
            operation: operation,
            projectPatch: projectPatch.isEmpty ? nil : projectPatch,
            projectStatus: status.map(ProjectStatusMutation.init(status:)),
            completion: state.map(CompletionMutation.init(state:)),
            move: move,
            previewOnly: previewOnly,
            verify: verify,
            returnFields: FieldList.parse(returnFields)
        )
    }

    func run() async throws {
        let service = OmniFocusBridgeService()
        let request = try makeRequest()
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

struct BridgeHealthCheck: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bridge-health-check",
        abstract: "Check OmniFocus bridge plug-in availability and responsiveness.",
        aliases: ["bridge_health_check"]
    )

    func run() async throws {
        let service = OmniFocusBridgeService()
        let result = try await service.healthCheck()
        print(try encodeJSON(result))
    }
}
