import Testing
@testable import FocusRelayServer

@Test
func mcpLogOutputUsesStandardError() {
    switch FocusRelayServer.mcpLogOutputTarget {
    case .standardError:
        #expect(Bool(true))
    case .standardOutput:
        #expect(Bool(false))
    }
}
