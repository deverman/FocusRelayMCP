import Foundation
import Logging
import MCP
import OmniFocusAutomation
import OmniFocusCore
import FocusRelayOutput
import FocusRelayVersion

public enum FocusRelayServer {
    public static var version: String {
        FocusRelayBuildVersion.current
    }

    enum LogOutputTarget {
        case standardOutput
        case standardError
    }

    static var mcpLogOutputTarget: LogOutputTarget {
        .standardError
    }

    static let publicToolNames = [
        "list_tasks",
        "get_task",
        "list_projects",
        "list_tags",
        "list_folders",
        "edit_tasks",
        "edit_projects",
        "get_task_counts",
        "get_project_counts"
    ]

    static let mutationToolNames: Set<String> = [
        "edit_tasks",
        "edit_projects"
    ]

    static let mutationToolAnnotations = Tool.Annotations(
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: false
    )

    static func makeTaskEditSchema(properties: [String: Value]) -> Value {
        discriminatedToolSchema(
            properties: properties,
            operationPayloads: [
                "update": "taskPatch",
                "set_completion": "completion",
                "move": "move"
            ]
        )
    }

    static func makeProjectEditSchema(properties: [String: Value]) -> Value {
        discriminatedToolSchema(
            properties: properties,
            operationPayloads: [
                "update": "projectPatch",
                "set_status": "projectStatus",
                "set_completion": "completion",
                "move": "move"
            ]
        )
    }

    static let listProjectsToolDescription = """
    List OmniFocus projects with pagination and filtering. Projects have a status (active, onHold, dropped, done) and can optionally include child-task counts.

    PROJECT MAINTENANCE AND HEALTH:
    - For completion, cleanup, or stalled-project recommendations, start with statusFilter='active'. Use 'all' only when historical done/dropped projects are relevant.
    - Always inspect project status before interpreting task counts. A project with remainingTasks=0 is not automatically a completion candidate.
    - totalTasks=0 means the project is empty or unplanned, not completed.
    - An active project whose child tasks are all completed may be a completion candidate. If all child tasks are dropped, treat it as a drop/review candidate instead.
    - availableTasks=0 does not mean a project is stalled. Request and use 'isStalled', and do not classify on-hold projects as stalled.
    - Do not infer that a project is stale from task counts alone.
    - Default fields are 'id' and 'name'. When statusFilter='all' or includeTaskCounts=true, the defaults also include 'status'.

    COMPLETED PROJECTS (matches OmniFocus Completed perspective):
    - Use completed=true and/or completedAfter/completedBefore (ISO8601, inclusive) to find completed projects in time windows.
    - Completion filters imply Done projects: default statusFilter='active' is ignored for these queries so results are not empty.
    - Excludes dropped projects (only status=done projects with completion dates).
    - Results are sorted by completionDate descending (most recent first).
    - Include 'completionDate' in fields to see when projects were completed.

    REVIEW PERSPECTIVE:
    - Use reviewPerspective=true to return projects pending review (excludes dropped/done and applies nextReviewDate <= now when reviewDueBefore is omitted).
    - Optionally set reviewDueBefore/reviewDueAfter (ISO8601 UTC) to bound nextReviewDate.
    """

    public static func resolvedProjectFields(
        requestedFields: [String],
        statusFilter: String,
        includeTaskCounts: Bool
    ) -> [String] {
        guard requestedFields.isEmpty else { return requestedFields }
        if statusFilter.caseInsensitiveCompare("all") == .orderedSame || includeTaskCounts {
            return ["id", "name", "status"]
        }
        return ["id", "name"]
    }

    static let taskFilterPropertyNames: Set<String> = [
        "completed",
        "flagged",
        "availableOnly",
        "inboxView",
        "project",
        "tags",
        "dueBefore",
        "dueAfter",
        "deferBefore",
        "deferAfter",
        "plannedBefore",
        "plannedAfter",
        "completedBefore",
        "completedAfter",
        "search",
        "inboxOnly",
        "projectView",
        "maxEstimatedMinutes",
        "minEstimatedMinutes",
        "includeTotalCount"
    ]

    static func makeTaskFilterSchema() -> Value {
        let dateExample = Value.string("2026-01-30T12:00:00Z")
        let properties: [String: Value] = [
            "completed": propertySchema(
                type: "boolean",
                description: "Match completed (true) or remaining (false) tasks. Omit to use the selected view's default."
            ),
            "flagged": propertySchema(
                type: "boolean",
                description: "Match OmniFocus's effective flagged state, including flags inherited from a parent task or project."
            ),
            "availableOnly": propertySchema(
                type: "boolean",
                description: "When true, require OmniFocus's native available task status, including active project and parent status."
            ),
            "inboxView": .object([
                "type": .string("string"),
                "description": .string("Task status view. This does not scope results to the inbox; set inboxOnly=true for that."),
                "enum": .array([.string("available"), .string("remaining"), .string("everything")])
            ]),
            "project": propertySchema(
                type: "string",
                description: "Match one containing project by exact ID or exact name."
            ),
            "tags": .object([
                "type": .string("array"),
                "description": .string("Match tag IDs or exact tag names. An empty array selects untagged tasks."),
                "items": .object(["type": .string("string")]),
                "examples": .array([.array([.string("work"), .string("urgent")]), .array([.string("personal")])])
            ]),
            "dueBefore": dateFilterSchema("Match tasks due on or before this ISO8601 timestamp.", example: dateExample),
            "dueAfter": dateFilterSchema("Match tasks due on or after this ISO8601 timestamp.", example: dateExample),
            "deferBefore": dateFilterSchema("Match tasks deferred until on or before this ISO8601 timestamp.", example: dateExample),
            "deferAfter": dateFilterSchema("Match tasks deferred until on or after this ISO8601 timestamp.", example: dateExample),
            "plannedBefore": dateFilterSchema("Match tasks planned on or before this ISO8601 timestamp.", example: dateExample),
            "plannedAfter": dateFilterSchema("Match tasks planned on or after this ISO8601 timestamp.", example: dateExample),
            "completedBefore": dateFilterSchema("Match tasks completed on or before this ISO8601 timestamp.", example: dateExample),
            "completedAfter": dateFilterSchema("Match tasks completed on or after this ISO8601 timestamp.", example: dateExample),
            "search": propertySchema(
                type: "string",
                description: "Search task names and notes."
            ),
            "inboxOnly": propertySchema(
                type: "boolean",
                description: "When true, scope the query to inbox tasks."
            ),
            "projectView": .object([
                "type": .string("string"),
                "description": .string("Match tasks by containing project status. Use all to include every project status."),
                "enum": .array([.string("active"), .string("onHold"), .string("dropped"), .string("done"), .string("all")])
            ]),
            "maxEstimatedMinutes": .object([
                "type": .string("integer"),
                "minimum": .int(0),
                "description": .string("Match tasks whose estimate is at most this many minutes.")
            ]),
            "minEstimatedMinutes": .object([
                "type": .string("integer"),
                "minimum": .int(0),
                "description": .string("Match tasks whose estimate is at least this many minutes.")
            ]),
            "includeTotalCount": propertySchema(
                type: "boolean",
                description: "For list_tasks, include the full filtered count before pagination. get_task_counts always returns dedicated counts, so this value is unnecessary there.",
                defaultValue: .bool(false)
            )
        ]

        precondition(
            Set(properties.keys) == taskFilterPropertyNames,
            "The shared MCP task filter schema must cover the intentional TaskFilter surface."
        )

        return .object([
            "type": .string("object"),
            "description": .string("Shared task filter accepted by list_tasks and get_task_counts. Date bounds are inclusive ISO8601 timestamps."),
            "properties": .object(properties)
        ])
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
            version: version,
            capabilities: .init(tools: .init(listChanged: true))
        )

        let bridgeService = OmniFocusBridgeService()
        bridgeService.setWarningsHandler { warnings, op in
            logger.warning("Bridge warnings for \(op): \(warnings.joined(separator: " | "))")
        }
        let service: OmniFocusService = bridgeService

        await server.withMethodHandler(ListTools.self) { _ in
            let tools = [
                Tool(
                    name: "list_tasks",
                    description: "Query OmniFocus tasks with powerful filtering including completion dates, due dates, planned dates, tags, and availability.\n\nFILTERING BY COMPLETION DATE (for 'what did I complete today?' questions):\n- Use completedAfter/completedBefore with ISO8601 dates: {\"completedAfter\": \"2026-01-31T00:00:00Z\", \"completedBefore\": \"2026-02-01T00:00:00Z\"}\n- IMPORTANT: Always include 'completionDate' in the fields parameter to see when tasks were completed\n- Results are automatically sorted by completionDate descending (most recent first) to match OmniFocus Completed perspective\n\nFILTERING BY TAGS:\n- Tagged project root tasks are included when they match, even if OmniFocus omits them from flattenedTasks because the project has child tasks.\n- If you want tagged project headers that are not currently actionable, set completed=false and availableOnly=false.\n\nFILTERING BY AVAILABILITY (for 'what should I do?' questions):\n- Use availableOnly=true to see only actionable tasks\n- Use deferAfter/deferBefore for time-of-day filtering (Morning=06:00-12:00, etc.)\n\nCOUNTS:\n- Use includeTotalCount=true to include totalCount for the full filtered result set (not just page size).\n\nTime formats: ISO8601 UTC (YYYY-MM-DDTHH:MM:SSZ). Default fields: only 'id' and 'name'.",
                    inputSchema: toolSchema(
                        properties: [
                            "filter": makeTaskFilterSchema(),
                            "page": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "limit": .object(["type": .string("integer"), "minimum": .int(1)]),
                                    "cursor": .object(["type": .string("string")])
                                ])
                            ]),
                            "fields": .object([
                                "type": .string("array"),
                                "description": .string("CRITICAL: Specify which fields to return. DEFAULT ONLY includes 'id' and 'name'.\n\nIMPORTANT FIELD NAMES (case-sensitive):\n- 'completionDate' - when task was completed (NOT 'completedDate')\n- 'dueDate' - when task is due\n- 'plannedDate' - when task is planned for\n- 'deferDate' - when task becomes available\n- 'completed' - true/false completion status\n- 'projectName' - name of the project\n- 'tagNames' - list of tags\n- 'available' - whether task is actionable now\n- 'flagged' - whether this task itself is flagged\n- 'effectiveFlagged' - visible OmniFocus flag state, including flags inherited from a parent task or project\n\nFor Flagged-perspective questions, filter with flagged=true and request 'effectiveFlagged' when returning flag state. ALWAYS include the fields you need to answer the user's question."),
                                "items": .object(["type": .string("string")]),
                                "examples": .array([
                                    .array([.string("id"), .string("name"), .string("completionDate"), .string("completed"), .string("projectName")]),
                                    .array([.string("id"), .string("name"), .string("dueDate"), .string("plannedDate"), .string("deferDate"), .string("available")]),
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
                    description: listProjectsToolDescription,
                    inputSchema: toolSchema(
                        properties: [
                            "page": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "limit": .object(["type": .string("integer"), "minimum": .int(1)]),
                                    "cursor": .object(["type": .string("string")])
                                ])
                            ]),
                            "statusFilter": .object([
                                "type": .string("string"),
                                "description": .string("Filter projects by status: 'active' (default), 'onHold', 'dropped', 'done', or 'all'. Use 'active' for current-project maintenance. 'all' includes historical done/dropped projects, so inspect each returned status before making recommendations."),
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
                                "description": .string("ISO8601 datetime. Projects completed on or after this time (inclusive). Completion queries ignore default statusFilter=active and return Done projects only."),
                                "examples": .array([.string("2026-01-01T00:00:00Z")])
                            ]),
                            "completedBefore": .object([
                                "type": .string("string"),
                                "description": .string("ISO8601 datetime. Projects completed on or before this time (inclusive). Completion queries ignore default statusFilter=active and return Done projects only."),
                                "examples": .array([.string("2026-02-01T00:00:00Z")])
                            ]),
                            "includeTaskCounts": .object([
                                "type": .string("boolean"),
                                "description": .string("Include child-task counts for each project (available, remaining, completed, dropped, total). Counts do not determine project status: inspect the returned project status, treat empty projects separately, and use isStalled rather than availableTasks=0 for stalled-project analysis."),
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
                                "description": .string("Specify which fields to return. Useful fields: 'id', 'name', 'note', 'status', 'flagged', 'completionDate', 'lastReviewDate', 'nextReviewDate', 'reviewInterval', 'hasChildren', 'nextTask', 'containsSingletonActions', and 'isStalled'. Always include 'status' when comparing projects across statuses. Task-count fields are included by includeTaskCounts."),
                                "items": .object(["type": .string("string")]),
                                "examples": .array([
                                    .array([.string("id"), .string("name"), .string("status"), .string("isStalled")]),
                                    .array([.string("id"), .string("name"), .string("status"), .string("completionDate")]),
                                    .array([.string("id"), .string("name"), .string("status"), .string("lastReviewDate"), .string("nextReviewDate")])
                                ])
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
                                    "limit": .object(["type": .string("integer"), "minimum": .int(1)]),
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
                    name: "list_folders",
                    description: "List OmniFocus folders with pagination for project move destination discovery. Use this before edit_projects with operation=move when moving projects into a folder. Compact default fields are id and name; request parentID, parentName, projectCount, or childFolderCount when needed.",
                    inputSchema: toolSchema(
                        properties: [
                            "page": .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "limit": .object(["type": .string("integer"), "minimum": .int(1)]),
                                    "cursor": .object(["type": .string("string")])
                                ])
                            ]),
                            "fields": .object([
                                "type": .string("array"),
                                "description": .string("Specify folder fields to return: id, name, parentID, parentName, projectCount, childFolderCount."),
                                "items": .object(["type": .string("string")])
                            ])
                        ]
                    ),
                    annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
                ),
                Tool(
                    name: "edit_tasks",
                    description: "Edit existing OmniFocus tasks by ID. Choose exactly one operation and include only its matching payload: update with taskPatch, set_completion with completion, or move with move. One call applies the same operation and payload to every target.\n\nUse update for fields and tags, set_completion only for complete/reopen, and move for inbox/project/parent changes. Dropping, discarding, abandoning, or cancelling tasks is not supported and must not be treated as completion. No plannedDate writes.\n\nSet previewOnly=true to validate without writing. Use verify=true for post-write readback. Repeating completion may advance the original task.",
                    inputSchema: makeTaskEditSchema(
                        properties: [
                            "operation": .object([
                                "type": .string("string"),
                                "enum": .array([.string("update"), .string("set_completion"), .string("move")]),
                                "description": .string("Required edit operation. Include exactly one matching payload.")
                            ]),
                            "targetIDs": .object([
                                "type": .string("array"),
                                "description": .string("Task IDs to update."),
                                "items": .object(["type": .string("string")])
                            ]),
                            "taskPatch": .object([
                                "type": .string("object"),
                                "description": .string("Shared task patch applied to every task ID in targetIDs."),
                                "properties": .object([
                                    "name": propertySchema(type: "string", description: "Set a new task name."),
                                    "note": propertySchema(type: "string", description: "Replace the task note."),
                                    "noteAppend": propertySchema(type: "string", description: "Append text to the task note."),
                                    "flagged": propertySchema(type: "boolean", description: "Set flagged state."),
                                    "estimatedMinutes": propertySchema(type: "integer", description: "Set estimated minutes."),
                                    "dueDate": propertySchema(type: "string", description: "Set due date as ISO8601 UTC.", examples: [.string("2026-04-18T12:00:00Z")]),
                                    "clearDueDate": propertySchema(type: "boolean", description: "Clear the due date."),
                                    "deferDate": propertySchema(type: "string", description: "Set defer date as ISO8601 UTC.", examples: [.string("2026-04-19T09:00:00Z")]),
                                    "clearDeferDate": propertySchema(type: "boolean", description: "Clear the defer date."),
                                    "tags": .object([
                                        "type": .string("object"),
                                        "description": .string("Deterministic tag mutation. Tag IDs only in v1."),
                                        "properties": .object([
                                            "add": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                                            "remove": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                                            "set": .object(["type": .string("array"), "items": .object(["type": .string("string")])]),
                                            "clear": propertySchema(type: "boolean", description: "Clear all tags.")
                                        ])
                                    ])
                                ])
                            ]),
                            "completion": .object([
                                "type": .string("object"),
                                "description": .string("Required only for operation=set_completion. Never use completion to drop a task."),
                                "properties": .object([
                                    "state": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("active"), .string("completed")])
                                    ])
                                ]),
                                "required": .array([.string("state")])
                            ]),
                            "move": .object([
                                "type": .string("object"),
                                "description": .string("Required only for operation=move. Shared task destination."),
                                "properties": .object([
                                    "destinationKind": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("inbox"), .string("project"), .string("parent_task")])
                                    ]),
                                    "destinationID": propertySchema(type: "string", description: "Project or parent task ID. Omit for inbox moves."),
                                    "position": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("beginning"), .string("ending")]),
                                        "default": .string("ending")
                                    ])
                                ]),
                                "required": .array([.string("destinationKind")])
                            ]),
                            "previewOnly": propertySchema(type: "boolean", description: "When true, validate and resolve targets without mutating. False or omitted performs the write.", defaultValue: .bool(false)),
                            "verify": propertySchema(type: "boolean", description: "When true, read back and verify the final state after a write. Defaults to false.", defaultValue: .bool(false)),
                            "returnFields": .object([
                                "type": .string("array"),
                                "description": .string("Optional task fields to return in per-item results after mutation."),
                                "items": .object(["type": .string("string")])
                            ])
                        ]
                    ),
                    annotations: mutationToolAnnotations
                ),
                Tool(
                    name: "edit_projects",
                    description: "Edit existing OmniFocus projects by ID. Choose exactly one operation and include only its matching payload: update with projectPatch, set_status with projectStatus, set_completion with completion, or move with move. One call applies the same operation and payload to every target.\n\nUse set_status for active/on-hold/dropped and set_completion for complete/reopen. Use list_folders before a folder move when its ID is unknown; omit destinationID for the root library. Project tags and containsSingletonActions writes are not supported.\n\nSet previewOnly=true to validate without writing. Use verify=true for post-write readback. Repeating completion may advance the original project.",
                    inputSchema: makeProjectEditSchema(
                        properties: [
                            "operation": .object([
                                "type": .string("string"),
                                "enum": .array([.string("update"), .string("set_status"), .string("set_completion"), .string("move")]),
                                "description": .string("Required edit operation. Include exactly one matching payload.")
                            ]),
                            "targetIDs": .object([
                                "type": .string("array"),
                                "description": .string("Project IDs to update."),
                                "items": .object(["type": .string("string")])
                            ]),
                            "projectPatch": .object([
                                "type": .string("object"),
                                "description": .string("Shared project patch applied to every project ID in targetIDs."),
                                "properties": .object([
                                    "name": propertySchema(type: "string", description: "Set a new project name."),
                                    "note": propertySchema(type: "string", description: "Replace the project note."),
                                    "noteAppend": propertySchema(type: "string", description: "Append text to the project note."),
                                    "flagged": propertySchema(type: "boolean", description: "Set flagged state."),
                                    "dueDate": propertySchema(type: "string", description: "Set due date as ISO8601 UTC.", examples: [.string("2026-04-18T12:00:00Z")]),
                                    "clearDueDate": propertySchema(type: "boolean", description: "Clear the due date."),
                                    "deferDate": propertySchema(type: "string", description: "Set defer date as ISO8601 UTC.", examples: [.string("2026-04-19T09:00:00Z")]),
                                    "clearDeferDate": propertySchema(type: "boolean", description: "Clear the defer date."),
                                    "sequential": propertySchema(type: "boolean", description: "Set whether the project's actions are sequential."),
                                    "reviewInterval": .object([
                                        "type": .string("object"),
                                        "description": .string("Set the simple review interval."),
                                        "properties": .object([
                                            "steps": propertySchema(type: "integer", description: "Review interval step count."),
                                            "unit": propertySchema(type: "string", description: "Review interval unit, such as days, weeks, months, or years.")
                                        ])
                                    ]),
                                    "reviewedNow": propertySchema(
                                        type: "boolean",
                                        description: "Mark active or on-hold projects reviewed now. Only true is accepted, and it must be the only projectPatch field."
                                    )
                                ])
                            ]),
                            "projectStatus": .object([
                                "type": .string("object"),
                                "description": .string("Required only for operation=set_status."),
                                "properties": .object([
                                    "status": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("active"), .string("on_hold"), .string("dropped")])
                                    ])
                                ]),
                                "required": .array([.string("status")])
                            ]),
                            "completion": .object([
                                "type": .string("object"),
                                "description": .string("Required only for operation=set_completion."),
                                "properties": .object([
                                    "state": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("active"), .string("completed")])
                                    ])
                                ]),
                                "required": .array([.string("state")])
                            ]),
                            "move": .object([
                                "type": .string("object"),
                                "description": .string("Required only for operation=move. Omit destinationID for the root library."),
                                "properties": .object([
                                    "destinationKind": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("folder")])
                                    ]),
                                    "destinationID": propertySchema(type: "string", description: "Destination folder ID from list_folders."),
                                    "position": .object([
                                        "type": .string("string"),
                                        "enum": .array([.string("beginning"), .string("ending")]),
                                        "default": .string("ending")
                                    ])
                                ]),
                                "required": .array([.string("destinationKind")])
                            ]),
                            "previewOnly": propertySchema(type: "boolean", description: "When true, validate and resolve targets without mutating. False or omitted performs the write.", defaultValue: .bool(false)),
                            "verify": propertySchema(type: "boolean", description: "When true, read back and verify the final state after a write. Defaults to false.", defaultValue: .bool(false)),
                            "returnFields": .object([
                                "type": .string("array"),
                                "description": .string("Optional project fields to return in per-item results after mutation."),
                                "items": .object(["type": .string("string")])
                            ])
                        ]
                    ),
                    annotations: mutationToolAnnotations
                ),
                Tool(
                    name: "get_task_counts",
                    description: "Get task counts for a filter. Returns {total, available, completed, flagged}.",
                    inputSchema: toolSchema(
                        properties: [
                            "filter": makeTaskFilterSchema()
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
                )
            ]

            precondition(
                tools.map(\.name) == publicToolNames,
                "The MCP tool catalog must match the intentional public tool surface."
            )
            precondition(
                tools.filter { mutationToolNames.contains($0.name) }.allSatisfy {
                    $0.annotations.readOnlyHint == false &&
                        $0.annotations.destructiveHint == true &&
                        $0.annotations.idempotentHint == false &&
                        $0.annotations.openWorldHint == false
                },
                "Mutation tool annotations must truthfully describe write risk."
            )

            return .init(tools: tools)
        }

        await server.withMethodHandler(CallTool.self) { params in
            do {
                let toolStart = Date()
                defer {
                    let elapsed = Date().timeIntervalSince(toolStart)
                    logger.info("Tool \(params.name) completed in \(String(format: "%.3f", elapsed))s")
                }

                guard publicToolNames.contains(params.name) else {
                    return .init(content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)], isError: true)
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
                        return .init(content: [.text(text: "Error decoding filter: \(error)", annotations: nil, _meta: nil)], isError: true)
                    }
                    let page = try decodePageRequest(from: params)
                    let requestedFields = decodeStringArray(params.arguments?["fields"]) ?? []
                    let fields = requestedFields.isEmpty ? ["id", "name"] : requestedFields
                    let result = try await service.listTasks(filter: filter, page: page, fields: fields)
                    let fieldSet = Set(fields)
                    let items = result.items.map { makeTaskOutput(from: $0, fields: fieldSet) }
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount, warnings: result.warnings)
                    return .init(content: [.text(text: try encodeJSON(output), annotations: nil, _meta: nil)])
                case "get_task":
                    let id = try decodeArgument(String.self, from: params.arguments, key: "id") ?? ""
                    if id.isEmpty {
                        return .init(content: [.text(text: "Missing id", annotations: nil, _meta: nil)], isError: true)
                    }
                    let requestedFields = decodeStringArray(params.arguments?["fields"]) ?? []
                    let fields = requestedFields.isEmpty ? ["id", "name"] : requestedFields
                    let result = try await service.getTask(id: id, fields: fields)
                    let fieldSet = Set(fields)
                    let output = makeTaskOutput(from: result, fields: fieldSet)
                    return .init(content: [.text(text: try encodeJSON(output), annotations: nil, _meta: nil)])
                case "list_projects":
                    let page = try decodePageRequest(from: params)
                    let statusFilter = try decodeArgument(String.self, from: params.arguments, key: "statusFilter") ?? "active"
                    let includeTaskCounts = try decodeArgument(Bool.self, from: params.arguments, key: "includeTaskCounts") ?? false
                    let reviewDueBefore = try decodeArgument(Date.self, from: params.arguments, key: "reviewDueBefore")
                    let reviewDueAfter = try decodeArgument(Date.self, from: params.arguments, key: "reviewDueAfter")
                    let reviewPerspective = try decodeArgument(Bool.self, from: params.arguments, key: "reviewPerspective") ?? false
                    let completed = try decodeArgument(Bool.self, from: params.arguments, key: "completed")
                    let completedBefore = try decodeArgument(Date.self, from: params.arguments, key: "completedBefore")
                    let completedAfter = try decodeArgument(Date.self, from: params.arguments, key: "completedAfter")
                    let requestedFields = decodeStringArray(params.arguments?["fields"]) ?? []
                    let fields = resolvedProjectFields(
                        requestedFields: requestedFields,
                        statusFilter: statusFilter,
                        includeTaskCounts: includeTaskCounts
                    )
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
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount, warnings: result.warnings)
                    return .init(content: [.text(text: try encodeJSON(output), annotations: nil, _meta: nil)])
                case "list_tags":
                    let page = try decodePageRequest(from: params)
                    let statusFilter = try decodeArgument(String.self, from: params.arguments, key: "statusFilter") ?? "active"
                    let includeTaskCounts = try decodeArgument(Bool.self, from: params.arguments, key: "includeTaskCounts") ?? false
                    let result = try await service.listTags(page: page, statusFilter: statusFilter, includeTaskCounts: includeTaskCounts)
                    let fieldSet = Set(["id", "name", "status", "availableTasks", "remainingTasks", "totalTasks"])
                    let items = result.items.map { makeTagOutput(from: $0, fields: fieldSet, includeTaskCounts: includeTaskCounts) }
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount, warnings: result.warnings)
                    return .init(content: [.text(text: try encodeJSON(output), annotations: nil, _meta: nil)])
                case "list_folders":
                    let page = try decodePageRequest(from: params)
                    let requestedFields = decodeStringArray(params.arguments?["fields"]) ?? []
                    let fields = requestedFields.isEmpty ? ["id", "name"] : requestedFields
                    let result = try await service.listFolders(page: page, fields: fields)
                    let fieldSet = Set(fields)
                    let items = result.items.map { makeFolderOutput(from: $0, fields: fieldSet) }
                    let output = PageOutput(items: items, nextCursor: result.nextCursor, returnedCount: result.returnedCount, totalCount: result.totalCount, warnings: result.warnings)
                    return .init(content: [.text(text: try encodeJSON(output), annotations: nil, _meta: nil)])
                case "edit_tasks":
                    let request = try decodeTaskEditRequest(from: params.arguments)
                    let result = try await service.performMutation(request)
                    return .init(content: [.text(text: try encodeJSON(result), annotations: nil, _meta: nil)])
                case "edit_projects":
                    let request = try decodeProjectEditRequest(from: params.arguments)
                    let result = try await service.performMutation(request)
                    return .init(content: [.text(text: try encodeJSON(result), annotations: nil, _meta: nil)])
                case "get_task_counts":
                    let filter = try decodeArgument(TaskFilter.self, from: params.arguments, key: "filter") ?? TaskFilter()
                    let counts = try await service.getTaskCounts(filter: filter)
                    return .init(content: [.text(text: try encodeJSON(counts), annotations: nil, _meta: nil)])
                case "get_project_counts":
                    let filter = try decodeArgument(TaskFilter.self, from: params.arguments, key: "filter") ?? TaskFilter()
                    let counts = try await service.getProjectCounts(filter: filter)
                    return .init(content: [.text(text: try encodeJSON(counts), annotations: nil, _meta: nil)])
                default:
                    return .init(content: [.text(text: "Unknown tool: \(params.name)", annotations: nil, _meta: nil)], isError: true)
                }
            } catch {
                logger.error("Tool call failed: \(error.localizedDescription)")
                return .init(content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)], isError: true)
            }
        }

        let transport = StdioTransport(logger: logger)
        try await server.start(transport: transport)
        while true {
            try await Task.sleep(nanoseconds: 60 * 60 * 24 * 1_000_000_000)
        }
    }

    static func decodeArgument<T: Decodable>(_ type: T.Type, from args: [String: Value]?, key: String) throws -> T? {
        guard let value = args?[key] else { return nil }
        let data = try JSONEncoder().encode(value)
        // Match bridge payload decoding: fractional and standard ISO8601.
        let decoder = BridgeDateDecoding.makeJSONDecoder()
        return try decoder.decode(T.self, from: data)
    }

    static func decodeTaskEditRequest(from args: [String: Value]?) throws -> MutationRequest {
        let operationName = try decodeArgument(String.self, from: args, key: "operation")
        guard let operationName else {
            throw MutationValidationError("edit_tasks requires an operation: update, set_completion, or move.")
        }
        if operationName == "set_status" {
            throw MutationValidationError("Task dropping is not supported. Do not use set_completion to drop, discard, abandon, or cancel a task.")
        }
        guard let operation = TaskEditOperation(rawValue: operationName) else {
            throw MutationValidationError("Unsupported edit_tasks operation: \(operationName).")
        }

        return try MutationRequest.editTasks(
            targetIDs: try decodeArgument([String].self, from: args, key: "targetIDs") ?? [],
            operation: operation,
            taskPatch: try decodeArgument(TaskPatchMutation.self, from: args, key: "taskPatch"),
            completion: try decodeArgument(CompletionMutation.self, from: args, key: "completion"),
            move: try decodeArgument(MoveMutation.self, from: args, key: "move"),
            previewOnly: try decodeArgument(Bool.self, from: args, key: "previewOnly") ?? false,
            verify: try decodeArgument(Bool.self, from: args, key: "verify") ?? false,
            returnFields: decodeStringArray(args?["returnFields"])
        )
    }

    static func decodeProjectEditRequest(from args: [String: Value]?) throws -> MutationRequest {
        let operationName = try decodeArgument(String.self, from: args, key: "operation")
        guard let operationName else {
            throw MutationValidationError("edit_projects requires an operation: update, set_status, set_completion, or move.")
        }
        guard let operation = ProjectEditOperation(rawValue: operationName) else {
            throw MutationValidationError("Unsupported edit_projects operation: \(operationName).")
        }

        return try MutationRequest.editProjects(
            targetIDs: try decodeArgument([String].self, from: args, key: "targetIDs") ?? [],
            operation: operation,
            projectPatch: try decodeArgument(ProjectPatchMutation.self, from: args, key: "projectPatch"),
            projectStatus: try decodeArgument(ProjectStatusMutation.self, from: args, key: "projectStatus"),
            completion: try decodeArgument(CompletionMutation.self, from: args, key: "completion"),
            move: try decodeArgument(MoveMutation.self, from: args, key: "move"),
            previewOnly: try decodeArgument(Bool.self, from: args, key: "previewOnly") ?? false,
            verify: try decodeArgument(Bool.self, from: args, key: "verify") ?? false,
            returnFields: decodeStringArray(args?["returnFields"])
        )
    }

    static func decodePageRequest(from args: [String: Value]?, defaultLimit: Int) throws -> PageRequest {
        guard var pageValue = args?["page"] else {
            return PageRequest(limit: defaultLimit)
        }
        if case .object(var pageObject) = pageValue, pageObject["limit"] == nil {
            pageObject["limit"] = .int(defaultLimit)
            pageValue = .object(pageObject)
        }
        let data = try JSONEncoder().encode(pageValue)
        let page = try BridgeDateDecoding.makeJSONDecoder().decode(PageRequest.self, from: data)
        guard page.limit >= 1 else {
            throw MutationValidationError("page.limit must be at least 1.")
        }
        return page
    }

    static func decodePageRequest(from params: CallTool.Parameters) throws -> PageRequest {
        let defaultLimit: Int
        switch params.name {
        case "list_tasks":
            defaultLimit = 50
        case "list_projects", "list_tags", "list_folders":
            defaultLimit = 150
        default:
            throw MutationValidationError("Tool \(params.name) does not accept page arguments.")
        }
        return try decodePageRequest(from: params.arguments, defaultLimit: defaultLimit)
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

func discriminatedToolSchema(
    properties: [String: Value],
    operationPayloads: [String: String]
) -> Value {
    let payloadNames = Array(operationPayloads.values)
    let alternatives = operationPayloads.keys.sorted().map { operation -> Value in
        let forbiddenPayloads = payloadNames
            .filter { $0 != operationPayloads[operation] }
            .sorted()
            .map { payload in
                Value.object([
                    "required": .array([.string(payload)])
                ])
            }

        return .object([
            "properties": .object([
                "operation": .object(["const": .string(operation)])
            ]),
            "required": .array([.string(operationPayloads[operation] ?? "")]),
            "not": .object([
                "anyOf": .array(forbiddenPayloads)
            ])
        ])
    }

    return .object([
        "type": .string("object"),
        "properties": .object(properties),
        "required": .array([.string("operation"), .string("targetIDs")]),
        "additionalProperties": .bool(false),
        "oneOf": .array(alternatives)
    ])
}

private func propertySchema(
    type: String,
    description: String = "",
    examples: [Value]? = nil,
    defaultValue: Value? = nil
) -> Value {
    var schema: [String: Value] = ["type": .string(type)]
    if !description.isEmpty {
        schema["description"] = .string(description)
    }
    if let examples = examples {
        schema["examples"] = .array(examples)
    }
    if let defaultValue {
        schema["default"] = defaultValue
    }
    return .object(schema)
}

private func dateFilterSchema(_ description: String, example: Value) -> Value {
    .object([
        "type": .string("string"),
        "format": .string("date-time"),
        "description": .string(description),
        "examples": .array([example])
    ])
}

private func decodeStringArray(_ value: Value?) -> [String]? {
    guard let value else { return nil }
    let data = try? JSONEncoder().encode(value)
    guard let data else { return nil }
    return try? JSONDecoder().decode([String].self, from: data)
}
