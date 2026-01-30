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
    let fields: [String]?
    let page: PageRequest?
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
