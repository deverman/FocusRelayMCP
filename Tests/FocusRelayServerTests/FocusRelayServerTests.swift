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
