import Foundation
import Testing
@testable import FocusRelayServer
import FocusRelayVersion
import MCP
@testable import OmniFocusAutomation
import OmniFocusCore

@Test
func mcpArgumentBoundaryDecodesSparseTaskFieldPatches() throws {
    let flagged = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: ["taskPatch": .object(["flagged": .bool(true)])],
        key: "taskPatch"
    )
    #expect(flagged?.flagged == true)
    #expect(flagged?.clearDueDate == false)
    #expect(flagged?.clearDeferDate == false)

    let dueDate = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: ["taskPatch": .object(["dueDate": .string("2026-07-15T09:00:00Z")])],
        key: "taskPatch"
    )
    #expect(dueDate?.dueDate != nil)
}

@Test
func mcpArgumentBoundaryDecodesFractionalISO8601Dates() throws {
    let fractional = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: ["taskPatch": .object(["dueDate": .string("2026-07-15T09:00:00.000Z")])],
        key: "taskPatch"
    )
    let standard = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: ["taskPatch": .object(["dueDate": .string("2026-07-15T09:00:00Z")])],
        key: "taskPatch"
    )
    let fractionalDue = try #require(fractional?.dueDate)
    let standardDue = try #require(standard?.dueDate)
    #expect(abs(fractionalDue.timeIntervalSince(standardDue)) < 0.001)

    let filter = try FocusRelayServer.decodeArgument(
        TaskFilter.self,
        from: [
            "filter": .object([
                "completedAfter": .string("2026-01-31T00:00:00.123Z"),
                "completedBefore": .string("2026-02-01T00:00:00.456Z")
            ])
        ],
        key: "filter"
    )
    #expect(filter?.completedAfter != nil)
    #expect(filter?.completedBefore != nil)
}

@Test
func everyPublicSparseTaskPatchSurvivesMCPValueDecoding() throws {
    let cases: [[String: Value]] = [
        ["name": .string("Renamed")],
        ["note": .string("Replacement")],
        ["noteAppend": .string("Append")],
        ["flagged": .bool(false)],
        ["estimatedMinutes": .int(15)],
        ["dueDate": .string("2026-07-16T09:00:00Z")],
        ["clearDueDate": .bool(true)],
        ["deferDate": .string("2026-07-16T08:00:00Z")],
        ["clearDeferDate": .bool(true)],
        ["tags": .object(["clear": .bool(true)])]
    ]

    for value in cases {
        let decoded = try FocusRelayServer.decodeArgument(
            TaskPatchMutation.self,
            from: ["taskPatch": .object(value)],
            key: "taskPatch"
        )
        let patch = try #require(decoded)
        #expect(!patch.isEmpty)
        try patch.validate()
    }
}

@Test
func mcpArgumentBoundaryDecodesSparseProjectAndTagPatches() throws {
    let project = try FocusRelayServer.decodeArgument(
        ProjectPatchMutation.self,
        from: ["projectPatch": .object(["sequential": .bool(true)])],
        key: "projectPatch"
    )
    #expect(project?.sequential == true)
    #expect(project?.clearDueDate == false)
    #expect(project?.clearDeferDate == false)

    let task = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: [
            "taskPatch": .object([
                "tags": .object(["add": .array([.string("tag-1")])])
            ])
        ],
        key: "taskPatch"
    )
    #expect(task?.tags == TagMutation(add: ["tag-1"]))
}

@Test
func everyPublicSparseProjectPatchSurvivesMCPValueDecoding() throws {
    let cases: [[String: Value]] = [
        ["name": .string("Renamed")],
        ["note": .string("Replacement")],
        ["noteAppend": .string("Append")],
        ["flagged": .bool(true)],
        ["dueDate": .string("2026-07-16T09:00:00Z")],
        ["clearDueDate": .bool(true)],
        ["deferDate": .string("2026-07-16T08:00:00Z")],
        ["clearDeferDate": .bool(true)],
        ["sequential": .bool(true)],
        ["reviewInterval": .object(["steps": .int(2), "unit": .string("weeks")])],
        ["reviewedNow": .bool(true)]
    ]

    for value in cases {
        let decoded = try FocusRelayServer.decodeArgument(
            ProjectPatchMutation.self,
            from: ["projectPatch": .object(value)],
            key: "projectPatch"
        )
        let patch = try #require(decoded)
        #expect(!patch.isEmpty)
        try patch.validate()
    }
}

@Test
func mcpServerReportsEmbeddedBuildVersion() {
    #expect(FocusRelayServer.version == FocusRelayBuildVersion.current)
}

@Test
func mcpLogOutputUsesStandardError() {
    switch FocusRelayServer.mcpLogOutputTarget {
    case .standardError:
        #expect(Bool(true))
    case .standardOutput:
        #expect(Bool(false))
    }
}

@Test
func publicMCPToolSurfaceExcludesInternalDiagnostics() {
    #expect(FocusRelayServer.publicToolNames == [
        "list_tasks",
        "get_task",
        "list_projects",
        "list_tags",
        "list_folders",
        "edit_tasks",
        "edit_projects",
        "get_task_counts",
        "get_project_counts"
    ])
    #expect(!FocusRelayServer.publicToolNames.contains("debug_inbox_probe"))
    #expect(!FocusRelayServer.publicToolNames.contains("debug_inbox_probe_alt"))
    #expect(!FocusRelayServer.publicToolNames.contains("bridge_health_check"))
}

@Test
func mutationToolCatalogIsExplicitlySeparatedFromReadTools() {
    #expect(FocusRelayServer.mutationToolNames == [
        "edit_tasks",
        "edit_projects"
    ])
    #expect(FocusRelayServer.mutationToolNames.isSubset(of: Set(FocusRelayServer.publicToolNames)))
    #expect(FocusRelayServer.publicToolNames.count - FocusRelayServer.mutationToolNames.count == 7)

    let annotations = FocusRelayServer.mutationToolAnnotations
    #expect(annotations.readOnlyHint == false)
    #expect(annotations.destructiveHint == true)
    #expect(annotations.idempotentHint == false)
    #expect(annotations.openWorldHint == false)
}

@Test
func productionToolsListMatchesGoldenPublicCatalog() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let executable = packageRoot.appendingPathComponent(".build/debug/focusrelay")
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))

    let process = Process()
    let standardInput = Pipe()
    let standardOutput = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", "alarm 10; exec @ARGV", executable.path, "serve"]
    process.currentDirectoryURL = packageRoot
    process.standardInput = standardInput
    process.standardOutput = standardOutput
    process.standardError = Pipe()
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
        }
    }

    let requests = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"catalog-test","version":"1"}}}"#,
        #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#
    ].joined(separator: "\n") + "\n"
    try standardInput.fileHandleForWriting.write(contentsOf: Data(requests.utf8))

    var buffered = Data()
    var response: [String: Any]?
    while response == nil {
        let chunk = standardOutput.fileHandleForReading.availableData
        guard !chunk.isEmpty else {
            Issue.record("MCP server exited before returning tools/list")
            break
        }
        buffered.append(chunk)
        while let newline = buffered.firstIndex(of: 0x0A) {
            let line = buffered[..<newline]
            buffered.removeSubrange(...newline)
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["id"] as? Int == 2 else {
                continue
            }
            response = object
            break
        }
    }

    let result = try #require(response?["result"] as? [String: Any])
    let tools = try #require(result["tools"] as? [[String: Any]])
    #expect(tools.compactMap { $0["name"] as? String } == FocusRelayServer.publicToolNames)

    for tool in tools {
        let schema = try #require(tool["inputSchema"] as? [String: Any])
        expectClosedObjectSchemas(schema)
    }

    for name in FocusRelayServer.mutationToolNames {
        let tool = try #require(tools.first { $0["name"] as? String == name })
        let annotations = try #require(tool["annotations"] as? [String: Any])
        #expect(annotations["readOnlyHint"] as? Bool == false)
        #expect(annotations["destructiveHint"] as? Bool == true)
        #expect(annotations["idempotentHint"] as? Bool == false)
        #expect(annotations["openWorldHint"] as? Bool == false)

        let schema = try #require(tool["inputSchema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect((schema["oneOf"] as? [[String: Any]])?.isEmpty == false)
    }
}

@Test
func mcpWireRejectsUnknownTopLevelAndNestedArgumentsBeforeDispatch() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let executable = packageRoot.appendingPathComponent(".build/debug/focusrelay")

    let process = Process()
    let standardInput = Pipe()
    let standardOutput = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", "alarm 10; exec @ARGV", executable.path, "serve"]
    process.currentDirectoryURL = packageRoot
    process.standardInput = standardInput
    process.standardOutput = standardOutput
    process.standardError = Pipe()
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
        }
    }

    let reviewQueryKey = try QueryBoundCursor.queryKey(
        tool: "list_projects",
        input: ProjectFilter(statusFilter: "active", reviewPerspective: true)
    )
    let reviewCursor = try #require(
        QueryBoundCursor.publicPage(
            from: Page<ProjectItem>(
                items: [],
                nextCursor: "100",
                returnedCount: 100
            ),
            queryKey: reviewQueryKey
        ).nextCursor
    )

    let requests = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"validation-test","version":"1"}}}"#,
        #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_tasks","arguments":{"search":"drop test"}}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_projects","arguments":{"search":"drop test","statusFilter":"all"}}}"#,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_tasks","arguments":{"filter":{"unexpected":true}}}}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"list_tasks","arguments":{"page":{"offset":"50"}}}}"#,
        #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"edit_tasks","arguments":{"operation":"set_completion","targetIDs":["real-task"],"completion":{"state":"completed","unexpected":true}}}}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"list_projects","arguments":{"statusFilter":"active","page":{"cursor":"100"}}}}"#,
        #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"list_projects","arguments":{"statusFilter":"active","reviewPerspective":false,"page":{"cursor":"\#(reviewCursor)"}}}}"#
    ].joined(separator: "\n") + "\n"
    try standardInput.fileHandleForWriting.write(contentsOf: Data(requests.utf8))

    var responses: [Int: [String: Any]] = [:]
    var buffered = Data()
    while responses.count < 8 {
        let chunk = standardOutput.fileHandleForReading.availableData
        guard !chunk.isEmpty else {
            Issue.record("MCP server exited before returning argument-validation responses")
            break
        }
        buffered.append(chunk)
        while let newline = buffered.firstIndex(of: 0x0A) {
            let line = buffered[..<newline]
            buffered.removeSubrange(...newline)
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? Int else {
                continue
            }
            responses[id] = object
        }
    }

    #expect(toolErrorText(responses[2]).contains("list_tasks.search is unsupported; use list_tasks.filter.search"))
    #expect(toolErrorText(responses[3]).contains("list_projects.search is unsupported"))
    #expect(toolErrorText(responses[4]).contains("list_tasks.filter.unexpected is unsupported"))
    #expect(toolErrorText(responses[5]).contains("list_tasks.page.offset is unsupported"))
    #expect(toolErrorText(responses[6]).contains("edit_tasks.completion.unexpected is unsupported"))
    #expect(toolErrorText(responses[7]).contains("Pagination cursor is malformed or unsupported"))
    #expect(toolErrorText(responses[8]).contains("Pagination cursor is for a different query"))
}

@Test
func editToolSchemasRequireExactlyOneMatchingPayload() throws {
    let common: [String: Value] = [
        "operation": .object(["type": .string("string")]),
        "targetIDs": .object(["type": .string("array")])
    ]
    let taskSchema = FocusRelayServer.makeTaskEditSchema(properties: common.merging([
        "taskPatch": .object(["type": .string("object")]),
        "taskStatus": .object(["type": .string("object")]),
        "completion": .object(["type": .string("object")]),
        "move": .object(["type": .string("object")])
    ]) { _, new in new })
    let projectSchema = FocusRelayServer.makeProjectEditSchema(properties: common.merging([
        "projectPatch": .object(["type": .string("object")]),
        "projectStatus": .object(["type": .string("object")]),
        "completion": .object(["type": .string("object")]),
        "move": .object(["type": .string("object")])
    ]) { _, new in new })

    try expectDiscriminatedSchema(
        taskSchema,
        operationPayloads: [
            "update": "taskPatch",
            "set_status": "taskStatus",
            "set_completion": "completion",
            "move": "move"
        ]
    )
    try expectDiscriminatedSchema(
        projectSchema,
        operationPayloads: [
            "update": "projectPatch",
            "set_status": "projectStatus",
            "set_completion": "completion",
            "move": "move"
        ]
    )
}

private func expectClosedObjectSchemas(_ schema: [String: Any]) {
    if schema["type"] as? String == "object", schema["properties"] != nil {
        #expect(schema["additionalProperties"] as? Bool == false)
    }
    if let properties = schema["properties"] as? [String: Any] {
        for child in properties.values {
            if let childSchema = child as? [String: Any] {
                expectClosedObjectSchemas(childSchema)
            }
        }
    }
    if let items = schema["items"] as? [String: Any] {
        expectClosedObjectSchemas(items)
    }
}

private func toolErrorText(_ response: [String: Any]?) -> String {
    guard let result = response?["result"] as? [String: Any],
          result["isError"] as? Bool == true,
          let content = result["content"] as? [[String: Any]],
          let text = content.first?["text"] as? String else {
        return ""
    }
    return text
}

@Test
func taskEditWireArgumentsDispatchEveryOperation() throws {
    let update = try FocusRelayServer.decodeTaskEditRequest(from: [
        "operation": .string("update"),
        "targetIDs": .array([.string("task-1")]),
        "taskPatch": .object(["flagged": .bool(true)])
    ])
    #expect(update.operation.kind == .updateTasks)
    #expect(update.operation.taskPatch?.flagged == true)

    let status = try FocusRelayServer.decodeTaskEditRequest(from: [
        "operation": .string("set_status"),
        "targetIDs": .array([.string("task-1")]),
        "taskStatus": .object([
            "status": .string("dropped"),
            "recurrenceScope": .string("series")
        ])
    ])
    #expect(status.operation.kind == .setTasksStatus)
    #expect(status.operation.taskStatus == TaskStatusMutation(status: .dropped, recurrenceScope: .series))

    let completion = try FocusRelayServer.decodeTaskEditRequest(from: [
        "operation": .string("set_completion"),
        "targetIDs": .array([.string("task-1")]),
        "completion": .object(["state": .string("completed")])
    ])
    #expect(completion.operation.kind == .setTasksCompletion)

    let move = try FocusRelayServer.decodeTaskEditRequest(from: [
        "operation": .string("move"),
        "targetIDs": .array([.string("task-1")]),
        "move": .object(["destinationKind": .string("inbox")])
    ])
    #expect(move.operation.kind == .moveTasks)
}

@Test
func projectEditWireArgumentsDispatchEveryOperation() throws {
    let cases: [(String, String, Value, MutationOperationKind)] = [
        ("update", "projectPatch", .object(["flagged": .bool(true)]), .updateProjects),
        ("set_status", "projectStatus", .object(["status": .string("on_hold")]), .setProjectsStatus),
        ("set_completion", "completion", .object(["state": .string("completed")]), .setProjectsCompletion),
        ("move", "move", .object(["destinationKind": .string("folder")]), .moveProjects)
    ]

    for (operation, payloadName, payload, expectedKind) in cases {
        let request = try FocusRelayServer.decodeProjectEditRequest(from: [
            "operation": .string(operation),
            "targetIDs": .array([.string("project-1")]),
            payloadName: payload
        ])
        #expect(request.operation.kind == expectedKind)
    }
}

@Test
func projectReviewedNowWireArgumentsUseUpdatePatch() throws {
    let request = try FocusRelayServer.decodeProjectEditRequest(from: [
        "operation": .string("update"),
        "targetIDs": .array([.string("project-1"), .string("project-2")]),
        "projectPatch": .object(["reviewedNow": .bool(true)]),
        "previewOnly": .bool(true),
        "verify": .bool(true),
        "returnFields": .array([.string("id"), .string("lastReviewDate"), .string("nextReviewDate")])
    ])

    #expect(request.operation.projectPatch?.reviewedNow == true)
    #expect(request.previewOnly)
    #expect(request.verify)
}

@Test
func editWireArgumentsRejectMissingMismatchedAndContradictoryPayloads() {
    #expect(throws: MutationValidationError.self) {
        try FocusRelayServer.decodeTaskEditRequest(from: [
            "operation": .string("update"),
            "targetIDs": .array([.string("task-1")])
        ])
    }
    #expect(throws: MutationValidationError.self) {
        try FocusRelayServer.decodeTaskEditRequest(from: [
            "operation": .string("move"),
            "targetIDs": .array([.string("task-1")]),
            "completion": .object(["state": .string("completed")])
        ])
    }
    #expect(throws: MutationValidationError.self) {
        try FocusRelayServer.decodeProjectEditRequest(from: [
            "operation": .string("set_status"),
            "targetIDs": .array([.string("project-1")]),
            "projectStatus": .object(["status": .string("active")]),
            "completion": .object(["state": .string("active")])
        ])
    }
}

@Test
func taskEditStatusRequiresTaskStatusPayload() {
    #expect(throws: MutationValidationError.self) {
        try FocusRelayServer.decodeTaskEditRequest(from: [
            "operation": .string("set_status"),
            "targetIDs": .array([.string("task-1")]),
            "projectStatus": .object(["status": .string("dropped")])
        ])
    }
}

private func expectDiscriminatedSchema(
    _ value: Value,
    operationPayloads: [String: String]
) throws {
    guard case let .object(schema) = value else {
        Issue.record("Expected an object schema")
        return
    }
    #expect(schema["additionalProperties"] == .bool(false))
    #expect(schema["required"] == .array([.string("operation"), .string("targetIDs")]))

    guard case let .array(alternatives)? = schema["oneOf"] else {
        Issue.record("Expected oneOf operation alternatives")
        return
    }
    #expect(alternatives.count == operationPayloads.count)

    for (operation, payload) in operationPayloads {
        let alternative = try #require(alternatives.first { value in
            guard case let .object(branch) = value,
                  case let .object(properties)? = branch["properties"],
                  case let .object(operationSchema)? = properties["operation"] else {
                return false
            }
            return operationSchema["const"] == .string(operation)
        })
        guard case let .object(branch) = alternative else { continue }
        #expect(branch["required"] == .array([.string(payload)]))

        guard case let .object(notSchema)? = branch["not"],
              case let .array(forbidden)? = notSchema["anyOf"] else {
            Issue.record("Expected forbidden payload alternatives for \(operation)")
            continue
        }
        #expect(forbidden.count == operationPayloads.count - 1)
        #expect(!forbidden.contains(.object(["required": .array([.string(payload)])])))
    }
}

@Test
func projectDefaultsIncludeStatusWhenCountsOrHistoricalStatusesNeedInterpretation() {
    #expect(FocusRelayServer.resolvedProjectFields(
        requestedFields: [],
        statusFilter: "active",
        includeTaskCounts: false
    ) == ["id", "name"])

    #expect(FocusRelayServer.resolvedProjectFields(
        requestedFields: [],
        statusFilter: "all",
        includeTaskCounts: false
    ) == ["id", "name", "status"])

    #expect(FocusRelayServer.resolvedProjectFields(
        requestedFields: [],
        statusFilter: "active",
        includeTaskCounts: true
    ) == ["id", "name", "status"])

    #expect(FocusRelayServer.resolvedProjectFields(
        requestedFields: ["id", "name", "completionDate"],
        statusFilter: "all",
        includeTaskCounts: true
    ) == ["id", "name", "completionDate"])
}

@Test
func projectToolDescriptionGuardsCompletionAndStalledRecommendations() {
    let description = FocusRelayServer.listProjectsToolDescription
    #expect(description.contains("start with statusFilter='active'"))
    #expect(description.contains("remainingTasks=0 is not automatically a completion candidate"))
    #expect(description.contains("totalTasks=0 means the project is empty or unplanned"))
    #expect(description.contains("If all child tasks are dropped, treat it as a drop/review candidate"))
    #expect(description.contains("availableTasks=0 does not mean a project is stalled"))
    #expect(description.contains("default statusFilter='active' is ignored"))
    #expect(description.contains("statusFilter remains active inside Review queries"))
    #expect(description.contains("inclusive"))
}

@Test
func sharedTaskFilterSchemaCoversCompleteModelSurface() {
    let expectedPropertyNames: Set<String> = [
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

    #expect(FocusRelayServer.taskFilterPropertyNames == expectedPropertyNames)

    guard case let .object(schema) = FocusRelayServer.makeTaskFilterSchema(),
          case let .object(properties)? = schema["properties"] else {
        Issue.record("Expected an object task-filter schema with object properties")
        return
    }

    #expect(Set(properties.keys) == expectedPropertyNames)

    guard case let .object(flaggedSchema)? = properties["flagged"],
          case let .string(flaggedDescription)? = flaggedSchema["description"] else {
        Issue.record("Expected a flagged filter description")
        return
    }
    #expect(flaggedDescription.contains("effective flagged state"))
    #expect(flaggedDescription.contains("inherited"))

    guard case let .object(maximumEstimate)? = properties["maxEstimatedMinutes"],
          case let .object(minimumEstimate)? = properties["minEstimatedMinutes"] else {
        Issue.record("Expected estimate filter schemas")
        return
    }
    #expect(maximumEstimate["minimum"] == .int(0))
    #expect(minimumEstimate["minimum"] == .int(0))

    guard case let .object(includeTotalCount)? = properties["includeTotalCount"] else {
        Issue.record("Expected includeTotalCount filter schema")
        return
    }
    #expect(includeTotalCount["default"] == .bool(false))
}

@Test
func pageRequestValidationRejectsNonPositiveLimits() throws {
    #expect(throws: (any Error).self) {
        try FocusRelayServer.decodePageRequest(
            from: ["page": .object(["limit": .int(-5)])],
            defaultLimit: 50
        )
    }
    #expect(throws: (any Error).self) {
        try FocusRelayServer.decodePageRequest(
            from: ["page": .object(["limit": .int(0)])],
            defaultLimit: 50
        )
    }
}

@Test
func pageRequestValidationAcceptsOmittedAndPositiveLimits() throws {
    let defaulted = try FocusRelayServer.decodePageRequest(from: [:], defaultLimit: 150)
    #expect(defaulted.limit == 150)
    #expect(defaulted.cursor == nil)

    let explicit = try FocusRelayServer.decodePageRequest(
        from: ["page": .object(["limit": .int(25), "cursor": .string("50")])],
        defaultLimit: 150
    )
    #expect(explicit.limit == 25)
    #expect(explicit.cursor == "50")
}

@Test
func pageRequestAppliesToolDefaultLimitWhenCursorSentAlone() throws {
    let taskPage = try FocusRelayServer.decodePageRequest(
        from: ["page": .object(["cursor": .string("50")])],
        defaultLimit: 50
    )
    #expect(taskPage.limit == 50)
    #expect(taskPage.cursor == "50")

    let projectPage = try FocusRelayServer.decodePageRequest(
        from: ["page": .object(["cursor": .string("150")])],
        defaultLimit: 150
    )
    #expect(projectPage.limit == 150)
    #expect(projectPage.cursor == "150")
}

@Test
func cursorOnlyPagesApplyDefaultsAtMCPWireBoundary() throws {
    let cases = [
        (tool: "list_tasks", cursor: "50", expectedLimit: 50),
        (tool: "list_projects", cursor: "150", expectedLimit: 150)
    ]

    for testCase in cases {
        let data = Data(
            """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "method": "tools/call",
              "params": {
                "name": "\(testCase.tool)",
                "arguments": {"page": {"cursor": "\(testCase.cursor)"}}
              }
            }
            """.utf8
        )
        let request = try JSONDecoder().decode(Request<CallTool>.self, from: data)
        let page = try FocusRelayServer.decodePageRequest(from: request.params)

        #expect(request.method == CallTool.name)
        #expect(page.limit == testCase.expectedLimit)
        #expect(page.cursor == testCase.cursor)
    }
}

@Test
func reviewPerspectiveAndStatusFilterDecodeTogetherAtMCPWireBoundary() throws {
    let data = Data(
        #"""
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "tools/call",
          "params": {
            "name": "list_projects",
            "arguments": {
              "statusFilter": "onHold",
              "reviewPerspective": true
            }
          }
        }
        """#.utf8
    )
    let request = try JSONDecoder().decode(Request<CallTool>.self, from: data)

    #expect(
        try FocusRelayServer.decodeArgument(
            String.self,
            from: request.params.arguments,
            key: "statusFilter"
        ) == "onHold"
    )
    #expect(
        try FocusRelayServer.decodeArgument(
            Bool.self,
            from: request.params.arguments,
            key: "reviewPerspective"
        ) == true
    )
}
