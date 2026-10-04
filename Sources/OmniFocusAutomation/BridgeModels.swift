import Foundation
import OmniFocusCore

struct BridgeRequest: Codable {
    let schemaVersion: Int
    let requestId: String
    let op: String
    let timestamp: String
    let userTimeZone: String?
    let id: String?
    let filter: TaskFilter?
    let tagFilter: TagFilter?
    let projectFilter: ProjectFilter?
    let mutation: MutationRequest?
    let fields: [String]?
    let page: PageRequest?
    var forecastWindow: ForecastWindow? = nil
    var creation: TaskCreationRequest? = nil
}

/// Half-open local calendar day, computed by Foundation rather than JS locale guesses.
struct ForecastWindow: Codable {
    let startMilliseconds: Double
    let endMilliseconds: Double

    init(now: Date = Date(), timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        startMilliseconds = start.timeIntervalSince1970 * 1000
        endMilliseconds = end.timeIntervalSince1970 * 1000
    }
}

struct BridgeResponse<T: Codable>: Codable {
    let schemaVersion: Int
    let requestId: String
    let ok: Bool
    let data: T?
    let error: BridgeError?
    let timingMs: Int?
    let warnings: [String]?
}

struct BridgeError: Codable {
    let code: String
    let message: String
}

struct BridgePing: Codable {
    let ok: Bool
    let plugin: String
    let version: String
}
