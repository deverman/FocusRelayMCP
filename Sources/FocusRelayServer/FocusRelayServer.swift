import Foundation
import Logging
import MCP
import OmniFocusAutomation
import OmniFocusCore
import FocusRelayOutput

public enum FocusRelayServer {
    enum LogOutputTarget {
        case standardOutput
        case standardError
    }

    static var mcpLogOutputTarget: LogOutputTarget {
        .standardError
    }

    public static func run() async throws {
        LoggingSystem.bootstrap { label in
            var handler: StreamLogHandler
            switch mcpLogOutputTarget {
            case .standardOutput:
                handler = StreamLogHandler.standardOutput(label: label)
            case .standardError:
                handler = StreamLogHandler.standardError(label: label)
            }
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
                    description: "Query OmniFocus tasks with powerful filtering including completion dates, due dates, and availability.\n\nFILTERING BY COMPLETION DATE (for 'what did I complete today?' questions):\n- Use completedAfter/completedBefore with ISO8601 dates: {\"completedAfter\": \"2026-01-31T00:00:00Z\", \"completedBefore\": \"2026-02-01T00:00:00Z\"}\n- IMPORTANT: Always include 'completionDate' in the fields parameter to see when tasks were completed\n- Results are automatically sorted by completionDate descending (most recent first) to match OmniFocus Completed perspective\n\nFILTERING BY AVAILABILITY (for 'what should I do?' questions):\n- Use availableOnly=true to see only actionable tasks\n- Use deferAfter/deferBefore for time-of-day filtering (Morning=06:00-12:00, etc.)\n\nTime formats: ISO8601 UTC (YYYY-MM-DDTHH:MM:SSZ). Default fields: only 'id' and 'name'.",
                    inputSchema: toolSchema(
                        properties: [
                            "filter": .object([
                                "type": .string("object"),
                                "description": .string("Task filters including time periods. For 'morning tasks', use deferAfter=06:00 and deferBefore=12:00 in local timezone converted to UTC."),
                                "properties": .object([
                                    "completed": propertySchema(
                                        type: "boolean",
                                        description: "Filter by completion status. Use with completedAfter/completedBefore to filter completed tasks by date (e.g., completed=true + completedAfter='2026-02-10T00:00:00Z' = today's completions)"
                                    ),
                                    "completedAfter": propertySchema(
                                        type: "string",
                                        description: "Filter tasks completed AFTER this date/time (inclusive). Use ISO8601 UTC format. Example: To get today's completions, use today's date at 00:00:00Z. Can be used with or without completed=true.",
                                        examples: [.string("2026-01-31T00:00:00Z")]
                                    ),
                                    "completedBefore": propertySchema(
                                        type: "string",
                                        description: "Filter tasks completed BEFORE this date/time (exclusive). Use ISO8601 UTC format. Example: To get today's completions, use tomorrow's date at 00:00:00Z as the upper bound.",
                                        examples: [.string("2026-02-01T00:00:00Z")]
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
                                "description": .string("CRITICAL: Specify which fields to return. DEFAULT ONLY includes 'id' and 'name'.\n\nIMPORTANT FIELD NAMES (case-sensitive):\n- 'completionDate' - when task was completed (NOT 'completedDate')\n- 'dueDate' - when task is due\n- 'deferDate' - when task becomes available\n- 'completed' - true/false completion status\n- 'projectName' - name of the project\n- 'tagNames' - list of tags\n- 'available' - whether task is actionable now\n- 'flagged' - whether task is flagged\n\nALWAYS include the fields you need to answer the user's question."),
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
                    description: "List OmniFocus projects with pagination and filtering. Projects have a status (active, onHold, dropped, done) and can optionally include task counts. Use statusFilter to show only projects with a specific status, and includeTaskCounts to get the number of tasks associated with each project.\n\nCOMPLETED PROJECTS (matches OmniFocus Completed perspective):\n- Use completedAfter/completedBefore with ISO8601 dates to find completed projects in time windows\n- Excludes dropped projects (only status=done projects with completion dates)\n- Results sorted by completionDate descending (most recent first)\n- IMPORTANT: Include 'completionDate' in fields to see when projects were completed\n\nREVIEW PERSPECTIVE:\n- Use reviewPerspective=true to return projects pending review (excludes dropped/done and applies nextReviewDate <= now when reviewDueBefore is omitted).\n- Optionally set reviewDueBefore/reviewDueAfter (ISO8601 UTC) to bound nextReviewDate.",
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
                            "completed": .object([
                                "type": .string("boolean"),
                                "description": .string("Filter by completion status. When true with completedAfter/completedBefore, finds completed projects in time window (excludes dropped)"),
                                "default": .bool(false)
                            ]),
                            "completedAfter": .object([
                                "type": .string("string"),
                                "description": .string("ISO8601 datetime. Projects completed after this time (inclusive). Use with completed=true to find completed projects in time windows."),
                                "examples": .array([.string("2026-01-01T00:00:00Z")])
                            ]),
                            "completedBefore": .object([
                                "type": .string("string"),
                                "description": .string("ISO8601 datetime. Projects completed before this time (exclusive). Use with completed=true to find completed projects in time windows."),
                                "examples": .array([.string("2026-02-01T00:00:00Z")])
                            ]),
                            "includeTaskCounts": .object([
                                "type": .string("boolean"),
                                "description": .string("Include task counts for each project (available, remaining, completed, dropped, total)"),
                                "default": .bool(false)
                            ]),
                            "reviewPerspective": .object([
                                "type": .string("boolean"),
                                "description": .string("If true, apply OmniFocus Review perspective defaults: exclude dropped/done and require nextReviewDate <= now when reviewDueBefore is omitted"),
                                "default": .bool(false)
                            ]),
                            "reviewDueBefore": propertySchema(
                                type: "string",
                                description: "ISO8601 datetime. Only include projects whose nextReviewDate is before or equal to this time. If reviewPerspective=true and omitted, defaults to now.",
                                examples: [.string("2026-02-04T12:00:00Z")]
                            ),
                            "reviewDueAfter": propertySchema(
                                type: "string",
                                description: "ISO8601 datetime. Only include projects whose nextReviewDate is after or equal to this time.",
                                examples: [.string("2026-02-04T00:00:00Z")]
                            ),
                            "fields": .object([
                                "type": .string("array"),
                                "description": .string("Specify which fields to return. IMPORTANT review fields: 'lastReviewDate', 'nextReviewDate', 'reviewInterval' (object with steps/unit)."),
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
                    description: "Get project/action counts for a view filter.\n\nCOMPLETED PROJECTS COUNT:\n- Use completedAfter/completedBefore to count completed projects in time windows\n- Returns: projects (count of completed projects), actions (count of completed tasks in those projects)\n- Excludes dropped projects (only status=done)\n- Use this to answer 'How many projects did I complete this month?' without listing all items",
                    inputSchema: toolSchema(
                        properties: [
                            "filter": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "completed": .object([
                                        "type": .string("boolean"),
                                        "description": .string("Filter by completion status")
                                    ]),
                                    "completedAfter": .object([
                                        "type": .string("string"),
                                        "description": .string("ISO8601 datetime. Count projects completed after this time")
                                    ]),
                                    "completedBefore": .object([
                                        "type": .string("string"),
                                        "description": .string("ISO8601 datetime. Count projects completed before this time")
                                    ]),
                                    "projectView": .object([
                                        "type": .string("string"),
                                        "description": .string("Project view filter: 'active', 'onHold', 'dropped', 'done', 'all'"),
                                        "enum": .array([.string("active"), .string("onHold"), .string("dropped"), .string("done"), .string("all")])
                                    ])
                                ])
                            ])
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
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount)
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
                    let reviewDueBefore = try decodeArgument(Date.self, from: params.arguments, key: "reviewDueBefore")
                    let reviewDueAfter = try decodeArgument(Date.self, from: params.arguments, key: "reviewDueAfter")
                    let reviewPerspective = try decodeArgument(Bool.self, from: params.arguments, key: "reviewPerspective") ?? false
                    let completed = try decodeArgument(Bool.self, from: params.arguments, key: "completed")
                    let completedBefore = try decodeArgument(Date.self, from: params.arguments, key: "completedBefore")
                    let completedAfter = try decodeArgument(Date.self, from: params.arguments, key: "completedAfter")
                    let requestedFields = decodeStringArray(params.arguments?["fields"]) ?? []
                    let fields = requestedFields.isEmpty ? ["id", "name"] : requestedFields
                    let result = try await service.listProjects(
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
                    let fieldSet = Set(fields)
                    let items = result.items.map { makeProjectOutput(from: $0, fields: fieldSet, includeTaskCounts: includeTaskCounts) }
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount)
                    return .init(content: [.text(try encodeJSON(output))])
                case "list_tags":
                    let hasPage = params.arguments?["page"] != nil
                    let page = hasPage ? (try decodeArgument(PageRequest.self, from: params.arguments, key: "page") ?? PageRequest(limit: 150)) : PageRequest(limit: 150)
                    let statusFilter = try decodeArgument(String.self, from: params.arguments, key: "statusFilter") ?? "active"
                    let includeTaskCounts = try decodeArgument(Bool.self, from: params.arguments, key: "includeTaskCounts") ?? false
                    let result = try await service.listTags(page: page, statusFilter: statusFilter, includeTaskCounts: includeTaskCounts)
                    let fieldSet = Set(["id", "name", "status", "availableTasks", "remainingTasks", "totalTasks"])
                    let items = result.items.map { makeTagOutput(from: $0, fields: fieldSet, includeTaskCounts: includeTaskCounts) }
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount)
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
