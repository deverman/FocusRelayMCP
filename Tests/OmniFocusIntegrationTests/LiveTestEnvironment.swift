import Foundation

enum LiveTestEnvironment {
    static let bridgeEnabled = enabled("FOCUS_RELAY_BRIDGE_TESTS")

    private static func enabled(_ name: String) -> Bool {
        ProcessInfo.processInfo.environment[name] == "1"
    }
}
