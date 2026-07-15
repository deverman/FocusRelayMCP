import Foundation

enum LiveTestEnvironment {
    static let omniFocusEnabled = enabled("FOCUS_RELAY_LIVE_TESTS")
    static let bridgeEnabled = enabled("FOCUS_RELAY_BRIDGE_TESTS")
    static let parityEnabled = enabled("FOCUS_RELAY_PARITY_TESTS")

    private static func enabled(_ name: String) -> Bool {
        ProcessInfo.processInfo.environment[name] == "1"
    }
}
