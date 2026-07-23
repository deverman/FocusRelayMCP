import Foundation

enum LiveTestEnvironment {
    static let bridgeEnabled = enabled("FOCUS_RELAY_BRIDGE_TESTS")
    static let taskStatusMutationEnabled = bridgeEnabled && value("FOCUS_RELAY_TASK_STATUS_FIXTURE_ID") != nil

    static func value(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
        return value
    }

    private static func enabled(_ name: String) -> Bool {
        ProcessInfo.processInfo.environment[name] == "1"
    }
}
