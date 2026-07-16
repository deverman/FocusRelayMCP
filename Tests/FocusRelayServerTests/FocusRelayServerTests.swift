import Testing
@testable import FocusRelayServer
import FocusRelayVersion
import MCP
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
        ["reviewInterval": .object(["steps": .int(2), "unit": .string("weeks")])]
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
        "update_tasks",
        "set_tasks_completion",
        "move_tasks",
        "update_projects",
        "set_projects_status",
        "set_projects_completion",
        "move_projects",
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
        "update_tasks",
        "set_tasks_completion",
        "move_tasks",
        "update_projects",
        "set_projects_status",
        "set_projects_completion",
        "move_projects"
    ])
    #expect(FocusRelayServer.mutationToolNames.isSubset(of: Set(FocusRelayServer.publicToolNames)))
    #expect(FocusRelayServer.publicToolNames.count - FocusRelayServer.mutationToolNames.count == 7)
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
