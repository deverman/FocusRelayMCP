import Foundation

public enum AutomationError: Error, LocalizedError {
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executionFailed(let message):
            return "Automation execution failed: \(message)"
        }
    }
}
