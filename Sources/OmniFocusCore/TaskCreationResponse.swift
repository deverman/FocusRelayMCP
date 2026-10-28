import Foundation

/// Success means all requested tasks were saved and verified, not merely constructed.
public struct TaskCreationResponse: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case previewed, completed, partial, uncertain }
    public let status: Status
    public let destination: TaskCreationDestination
    public let results: [TaskCreationResult]
    public let message: String
    /// A stateless apply payload, with date-only inputs resolved to exact instants.
    public let applyRequest: TaskCreationRequest?

    public init(status: Status, destination: TaskCreationDestination, results: [TaskCreationResult],
                message: String, applyRequest: TaskCreationRequest? = nil) {
        self.status = status
        self.destination = destination
        self.results = results
        self.message = message
        self.applyRequest = applyRequest
    }
}

public struct TaskCreationResult: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case previewed, verified, unverified, notCreated = "not_created" }
    public let clientID: String
    public let name: String
    public let parentClientID: String?
    public let siblingIndex: Int
    public let id: String?
    public let parentID: String?
    /// Zero-based position in the complete native sibling collection, not just this batch.
    public let finalOrder: Int?
    public let status: Status
    public let due: ResolvedCreationDate?
    public let `defer`: ResolvedCreationDate?
    public let returnedFields: [String: JSONValue]
    public let message: String?
}

public struct ResolvedCreationDate: Codable, Sendable, Equatable {
    public let intent: TaskCreationDate
    public let local: String
    public let timeZoneID: String
    public let iso8601: String
}
