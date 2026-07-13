import Testing
@testable import FocusRelayServer
import FocusRelayVersion
import MCP

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
