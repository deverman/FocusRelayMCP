import Foundation
import Logging
import MCP
import OmniFocusAutomation
import OmniFocusCore

@main
struct FocusRelayMCPMain {
    static func main() async throws {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }

        let logger = Logger(label: "focus.relay.mcp")
        let server = Server(
            name: "FocusRelayMCP",
            version: "0.1.0",
            capabilities: .init(tools: .init(listChanged: true))
        )

        let service: OmniFocusService = OmniFocusBridgeService()

        await server.withMethodHandler(ListTools.self) { _ in
            let tools = [
                Tool(
                    name: "list_tasks",
                    description: "Query OmniFocus tasks with powerful filtering. IMPORTANT: Default fields only return 'id' and 'name'. To see completion dates, due dates, or other fields, you MUST explicitly request them in the 'fields' parameter.\n\nCRITICAL FILTERING HINTS:\n- To find tasks completed TODAY: Use completed=true AND staleThreshold='1days' AND request fields=['completionDate', 'completed', 'name']\n- To find available tasks: Use availableOnly=true\n- For time-of-day: Morning=06:00-12:00, Afternoon=12:00-18:00, Evening=18:00-22:00 (convert to ISO8601 UTC)\n\nTime formats are ISO8601 (YYYY-MM-DDTHH:MM:SSZ). All datetimes must be in UTC.",
                    inputSchema: toolSchema(
                        properties: [
                            "filter": .object([
                                "type": .string("object"),
                                "description": .string("Task filters including time periods. For 'morning tasks', use deferAfter=06:00 and deferBefore=12:00 in local timezone converted to UTC."),
                                "properties": .object([
                                    "completed": propertySchema(
                                        type: "boolean",
                                        description: "Filter by completion status. CRITICAL: When true, combine with staleThreshold='1days' to get today's completions, and ALWAYS request 'completionDate' in fields"
                                    ),
                                    "flagged": propertySchema(type: "boolean", description: "Filter flagged tasks only"),
                                    "availableOnly": propertySchema(type: "boolean", description: "Only show tasks that are currently available (not blocked by defer dates)"),
                                    "inboxView": propertySchema(type: "string", description: "View mode: 'available', 'remaining', or 'everything'"),
                                    "project": propertySchema(type: "string", description: "Filter by project ID or name"),
                                    "tags": .object([
                                        "type": .string("array"),
                                        "description": .string("Filter by tag IDs or names"),
                                        "items": .object(["type": .string("string")]),
                                        "examples": .array([.array([.string("work"), .string("urgent")]), .array([.string("personal")])])
                                    ]),
                                    "dueBefore": propertySchema(
                                        type: "string",
                                        description: "ISO8601 datetime. Tasks due before this time. For morning tasks due today, use today's date at 12:00:00Z",
                                        examples: [.string("2026-01-30T12:00:00Z"), .string("2026-01-30T23:59:59Z")]
                                    ),
                                    "dueAfter": propertySchema(
                                        type: "string",
                                        description: "ISO8601 datetime. Tasks due after this time",
                                        examples: [.string("2026-01-30T00:00:00Z")]
                                    ),
                                    "deferBefore": propertySchema(
                                        type: "string",
                                        description: "ISO8601 datetime. Tasks deferred until before this time. For morning tasks, use today's date at 12:00:00Z",
                                        examples: [.string("2026-01-30T12:00:00Z"), .string("2026-01-30T18:00:00Z")]
                                    ),
                                    "deferAfter": propertySchema(
                                        type: "string",
                                        description: "ISO8601 datetime. Tasks deferred until after this time (become available). For morning tasks starting at 6am, use today's date at 06:00:00Z",
                                        examples: [.string("2026-01-30T06:00:00Z"), .string("2026-01-30T12:00:00Z")]
                                    ),
                                    "staleThreshold": .object([
                                        "type": .string("string"),
                                        "description": .string("Convenience filter for relative date filtering. For completed tasks, finds tasks completed within the threshold. For incomplete tasks, finds tasks deferred before (threshold days ago). Examples: '1days' for today, '7days' for this week, '365days' for stale tasks"),
                                        "enum": .array([.string("1days"), .string("7days"), .string("30days"), .string("90days"), .string("180days"), .string("270days"), .string("365days")]),
                                        "examples": .array([.string("1days"), .string("7days"), .string("365days")])
                                    ]),
                                    "search": propertySchema(type: "string", description: "Search tasks by name or note content"),
                                    "inboxOnly": propertySchema(type: "boolean", description: "Only show inbox tasks"),
                                    "projectView": propertySchema(type: "string", description: "Project view filter: 'active', 'onHold', etc.")
                                ])
                            ]),
                            "page": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "limit": .object(["type": .string("integer")]),
                                    "cursor": .object(["type": .string("string")])
                                ])
                            ]),
                            "fields": .object([
                                "type": .string("array"),
                                "description": .string("CRITICAL: Specify which fields to return. DEFAULT ONLY includes 'id' and 'name'. Common fields: 'completionDate' (when task was completed), 'dueDate', 'deferDate', 'completed', 'projectName', 'tagNames', 'available', 'flagged'. ALWAYS include fields you need to answer the user's question."),
                                "items": .object(["type": .string("string")]),
                                "examples": .array([
                                    .array([.string("id"), .string("name"), .string("completionDate"), .string("completed"), .string("projectName")]),
                                    .array([.string("id"), .string("name"), .string("dueDate"), .string("deferDate"), .string("available")]),
                                    .array([.string("id"), .string("name"), .string("tagNames"), .string("projectName")])
                                ])
                            ])
                        ]
                    ),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "get_task",
                    description: "Get a single task by ID",
                    inputSchema: toolSchema(
                        properties: [
                            "id": .object(["type": .string("string")]),
                            "fields": .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("string")])
                            ])
                        ],
                        required: ["id"]
                    ),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "list_projects",
                    description: "List OmniFocus projects with pagination and filtering. Projects have a status (active, onHold, dropped, done) and can optionally include task counts. Use statusFilter to show only projects with a specific status, and includeTaskCounts to get the number of tasks associated with each project.",
                    inputSchema: toolSchema(
                        properties: [
                            "page": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "limit": .object(["type": .string("integer")]),
                                    "cursor": .object(["type": .string("string")])
                                ])
                            ]),
                            "statusFilter": .object([
                                "type": .string("string"),
                                "description": .string("Filter projects by status: 'active' (default), 'onHold', 'dropped', 'done', or 'all'"),
                                "enum": .array([.string("active"), .string("onHold"), .string("dropped"), .string("done"), .string("all")]),
                                "default": .string("active")
                            ]),
                            "includeTaskCounts": .object([
                                "type": .string("boolean"),
                                "description": .string("Include task counts for each project (available, remaining, completed, dropped, total)"),
                                "default": .bool(false)
                            ]),
                            "fields": .object([
                                "type": .string("array"),
                                "items": .object(["type": .string("string")])
                            ])
                        ]
                    ),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "list_tags",
                    description: "List OmniFocus tags with pagination and filtering. Tags have a status (active, onHold, dropped) and can optionally include task counts. Use statusFilter to show only tags with a specific status, and includeTaskCounts to get the number of tasks associated with each tag.",
                    inputSchema: toolSchema(
                        properties: [
                            "page": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "limit": .object(["type": .string("integer")]),
                                    "cursor": .object(["type": .string("string")])
                                ])
                            ]),
                            "statusFilter": .object([
                                "type": .string("string"),
                                "description": .string("Filter tags by status: 'active' (default), 'onHold', 'dropped', or 'all'"),
                                "enum": .array([.string("active"), .string("onHold"), .string("dropped"), .string("all")]),
                                "default": .string("active")
                            ]),
                            "includeTaskCounts": .object([
                                "type": .string("boolean"),
                                "description": .string("Include task counts for each tag (available, remaining, total)"),
                                "default": .bool(false)
                            ])
                        ]
                    ),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "get_task_counts",
                    description: "Get task counts for a filter",
                    inputSchema: toolSchema(
                        properties: [
                            "filter": .object(["type": .string("object")])
                        ]
                    ),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "get_project_counts",
                    description: "Get project/action counts for a view filter",
                    inputSchema: toolSchema(
                        properties: [
                            "filter": .object(["type": .string("object")])
                        ]
                    ),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "debug_inbox_probe",
                    description: "Debug inbox query behavior (counts and samples)",
                    inputSchema: toolSchema(properties: [:]),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "debug_inbox_probe_alt",
                    description: "Debug inbox query behavior using alternate queries and timings",
                    inputSchema: toolSchema(properties: [:]),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "bridge_health_check",
                    description: "Check OmniFocus bridge plug-in availability and responsiveness",
                    inputSchema: toolSchema(properties: [:]),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                )
            ]

            return .init(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let toolStart = Date()
                defer {
                    let elapsed = Date().timeIntervalSince(toolStart)
                    logger.info("Tool \(params.name) completed in \(String(format: "%.3f", elapsed))s")
                }

                switch params.name {
                case "list_tasks":
                    // Debug: Log raw arguments
                    logger.info("list_tasks called with arguments: \(String(describing: params.arguments))")
                    let filter: TaskFilter
                    do {
                        filter = try decodeArgument(TaskFilter.self, from: params.arguments, key: "filter") ?? TaskFilter()
                    } catch {
                        logger.error("Failed to decode filter: \(String(describing: error))")
                        return .init(content: [.text("Error decoding filter: \(error)")], isError: true)
                    }
                    let hasPage = params.arguments?["page"] != nil
                    let page = hasPage ? (try decodeArgument(PageRequest.self, from: params.arguments, key: "page") ?? PageRequest(limit: 50)) : PageRequest(limit: 50)
                    let requestedFields = decodeStringArray(params.arguments?["fields"]) ?? []
                    let fields = requestedFields.isEmpty ? ["id", "name"] : requestedFields
                    let result = try await service.listTasks(filter: filter, page: page, fields: fields)
                    let fieldSet = Set(fields)
                    let items = result.items.map { makeTaskOutput(from: $0, fields: fieldSet) }
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, totalCount: result.totalCount)
                    return .init(content: [.text(try encodeJSON(output))])
                case "get_task":
                    let id = try decodeArgument(String.self, from: params.arguments, key: "id") ?? ""
                    if id.isEmpty {
                        return .init(content: [.text("Missing id")], isError: true)
                    }
                    let requestedFields = decodeStringArray(params.arguments?["fields"]) ?? []
                    let fields = requestedFields.isEmpty ? ["id", "name"] : requestedFields
                    let result = try await service.getTask(id: id, fields: fields)
                    let fieldSet = Set(fields)
                    let output = makeTaskOutput(from: result, fields: fieldSet)
                    return .init(content: [.text(try encodeJSON(output))])
                case "list_projects":
                    let hasPage = params.arguments?["page"] != nil
                    let page = hasPage ? (try decodeArgument(PageRequest.self, from: params.arguments, key: "page") ?? PageRequest(limit: 150)) : PageRequest(limit: 150)
                    let statusFilter = try decodeArgument(String.self, from: params.arguments, key: "statusFilter") ?? "active"
                    let includeTaskCounts = try decodeArgument(Bool.self, from: params.arguments, key: "includeTaskCounts") ?? false
                    let requestedFields = decodeStringArray(params.arguments?["fields"]) ?? []
                    let fields = requestedFields.isEmpty ? ["id", "name"] : requestedFields
                    let result = try await service.listProjects(page: page, statusFilter: statusFilter, includeTaskCounts: includeTaskCounts, fields: fields)
                    let fieldSet = Set(fields)
                    let items = result.items.map { makeProjectOutput(from: $0, fields: fieldSet, includeTaskCounts: includeTaskCounts) }
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, totalCount: result.totalCount)
                    return .init(content: [.text(try encodeJSON(output))])
                case "list_tags":
                    let hasPage = params.arguments?["page"] != nil
                    let page = hasPage ? (try decodeArgument(PageRequest.self, from: params.arguments, key: "page") ?? PageRequest(limit: 150)) : PageRequest(limit: 150)
                    let statusFilter = try decodeArgument(String.self, from: params.arguments, key: "statusFilter") ?? "active"
                    let includeTaskCounts = try decodeArgument(Bool.self, from: params.arguments, key: "includeTaskCounts") ?? false
                    let result = try await service.listTags(page: page, statusFilter: statusFilter, includeTaskCounts: includeTaskCounts)
                    let fieldSet = Set(["id", "name", "status", "availableTasks", "remainingTasks", "totalTasks"])
                    let items = result.items.map { makeTagOutput(from: $0, fields: fieldSet, includeTaskCounts: includeTaskCounts) }
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, totalCount: result.totalCount)
                    return .init(content: [.text(try encodeJSON(output))])
                case "get_task_counts":
                    let filter = try decodeArgument(TaskFilter.self, from: params.arguments, key: "filter") ?? TaskFilter()
                    let counts = try await service.getTaskCounts(filter: filter)
                    return .init(content: [.text(try encodeJSON(counts))])
                case "get_project_counts":
                    let filter = try decodeArgument(TaskFilter.self, from: params.arguments, key: "filter") ?? TaskFilter()
                    let counts = try await service.getProjectCounts(filter: filter)
                    return .init(content: [.text(try encodeJSON(counts))])
                case "debug_inbox_probe":
                    if let automation = service as? OmniAutomationService {
                        let result = try await automation.debugInboxProbe()
                        return .init(content: [.text(try encodeJSON(result))])
                    }
                    return .init(content: [.text("debug_inbox_probe is only available in JXA mode")], isError: true)
                case "debug_inbox_probe_alt":
                    if let automation = service as? OmniAutomationService {
                        let result = try await automation.debugInboxProbeAlt()
                        return .init(content: [.text(try encodeJSON(result))])
                    }
                    return .init(content: [.text("debug_inbox_probe_alt is only available in JXA mode")], isError: true)
                case "bridge_health_check":
                    let bridge = OmniFocusBridgeService()
                    let result = try bridge.healthCheck()
                    return .init(content: [.text(try encodeJSON(result))])
                default:
                    return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
                }
            } catch {
                logger.error("Tool call failed: \(error.localizedDescription)")
                return .init(content: [.text("Error: \(error.localizedDescription)")], isError: true)
            }
        }

        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        while true {
            try await Task.sleep(nanoseconds: 60 * 60 * 24 * 1_000_000_000)
        }
    }
}

private func toolSchema(properties: [String: Value], required: [String] = []) -> Value {
    var schema: [String: Value] = [
        "type": "object",
        "properties": .object(properties)
    ]

    if !required.isEmpty {
        schema["required"] = .array(required.map { .string($0) })
    }

    return .object(schema)
}

private func propertySchema(type: String, description: String = "", examples: [Value]? = nil) -> Value {
    var schema: [String: Value] = ["type": .string(type)]
    if !description.isEmpty {
        schema["description"] = .string(description)
    }
    if let examples = examples {
        schema["examples"] = .array(examples)
    }
    return .object(schema)
}

private func decodeArgument<T: Decodable>(_ type: T.Type, from args: [String: Value]?, key: String) throws -> T? {
    guard let value = args?[key] else { return nil }
    let data = try JSONEncoder().encode(value)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: data)
}

private func decodeStringArray(_ value: Value?) -> [String]? {
    guard let value else { return nil }
    let data = try? JSONEncoder().encode(value)
    guard let data else { return nil }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try? JSONDecoder().decode([String].self, from: data)
}

private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}

private struct TaskOutput: Encodable {
    let id: String?
    let name: String?
    let note: String?
    let projectID: String?
    let projectName: String?
    let tagIDs: [String]?
    let tagNames: [String]?
    let dueDate: Date?
    let deferDate: Date?
    let completionDate: Date?
    let completed: Bool?
    let flagged: Bool?
    let estimatedMinutes: Int?
    let available: Bool?
}

private struct PageOutput<T: Encodable>: Encodable {
    let items: [T]
    let nextCursor: String?
    let totalCount: Int?
}

private struct ProjectOutput: Encodable {
    let id: String?
    let name: String?
    let note: String?
    let status: String?
    let flagged: Bool?
    let availableTasks: Int?
    let remainingTasks: Int?
    let completedTasks: Int?
    let droppedTasks: Int?
    let totalTasks: Int?
    let hasChildren: Bool?
    let nextTask: ProjectTaskSummary?
    let containsSingletonActions: Bool?
    let isStalled: Bool?
}

private struct TagOutput: Encodable {
    let id: String
    let name: String
    let status: String?
    let availableTasks: Int?
    let remainingTasks: Int?
    let totalTasks: Int?
}

private func makeTaskOutput(from task: TaskItem, fields: Set<String>) -> TaskOutput {
    TaskOutput(
        id: fields.contains("id") ? task.id : nil,
        name: fields.contains("name") ? task.name : nil,
        note: fields.contains("note") ? task.note : nil,
        projectID: fields.contains("projectID") ? task.projectID : nil,
        projectName: fields.contains("projectName") ? task.projectName : nil,
        tagIDs: fields.contains("tagIDs") ? task.tagIDs : nil,
        tagNames: fields.contains("tagNames") ? task.tagNames : nil,
        dueDate: fields.contains("dueDate") ? task.dueDate : nil,
        deferDate: fields.contains("deferDate") ? task.deferDate : nil,
        completionDate: fields.contains("completionDate") ? task.completionDate : nil,
        completed: fields.contains("completed") ? task.completed : nil,
        flagged: fields.contains("flagged") ? task.flagged : nil,
        estimatedMinutes: fields.contains("estimatedMinutes") ? task.estimatedMinutes : nil,
        available: fields.contains("available") ? task.available : nil
    )
}

private func makeProjectOutput(from project: ProjectItem, fields: Set<String>, includeTaskCounts: Bool) -> ProjectOutput {
    ProjectOutput(
        id: fields.contains("id") ? project.id : nil,
        name: fields.contains("name") ? project.name : nil,
        note: fields.contains("note") ? project.note : nil,
        status: fields.contains("status") ? project.status : nil,
        flagged: fields.contains("flagged") ? project.flagged : nil,
        availableTasks: includeTaskCounts ? project.availableTasks : nil,
        remainingTasks: includeTaskCounts ? project.remainingTasks : nil,
        completedTasks: includeTaskCounts ? project.completedTasks : nil,
        droppedTasks: includeTaskCounts ? project.droppedTasks : nil,
        totalTasks: includeTaskCounts ? project.totalTasks : nil,
        hasChildren: fields.contains("hasChildren") ? project.hasChildren : nil,
        nextTask: fields.contains("nextTask") ? project.nextTask : nil,
        containsSingletonActions: fields.contains("containsSingletonActions") ? project.containsSingletonActions : nil,
        isStalled: fields.contains("isStalled") ? project.isStalled : nil
    )
}

private func makeTagOutput(from tag: TagItem, fields: Set<String>, includeTaskCounts: Bool) -> TagOutput {
    TagOutput(
        id: tag.id,
        name: tag.name,
        status: fields.contains("status") ? tag.status : nil,
        availableTasks: includeTaskCounts ? tag.availableTasks : nil,
        remainingTasks: includeTaskCounts ? tag.remainingTasks : nil,
        totalTasks: includeTaskCounts ? tag.totalTasks : nil
    )
}
