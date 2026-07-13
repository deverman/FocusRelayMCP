import Testing
@testable import FocusRelayServer
import FocusRelayVersion

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
