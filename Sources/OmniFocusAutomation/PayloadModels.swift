import Foundation

struct TaskItemPayload: Codable {
    let id: String?
    let name: String?
    let note: String?
    let projectID: String?
    let projectName: String?
    let tagIDs: [String]?
    let tagNames: [String]?
    let dueDate: Date?
    let deferDate: Date?
    let completionDate: Date?
    let completed: Bool?
    let flagged: Bool?
    let estimatedMinutes: Int?
    let available: Bool?
}

struct ProjectTaskSummaryPayload: Codable {
    let id: String?
    let name: String?
}

struct ProjectItemPayload: Codable {
    let id: String?
    let name: String?
    let note: String?
    let status: String?
    let flagged: Bool?
    let availableTasks: Int?
    let remainingTasks: Int?
    let completedTasks: Int?
    let droppedTasks: Int?
    let totalTasks: Int?
    let hasChildren: Bool?
    let nextTask: ProjectTaskSummaryPayload?
    let containsSingletonActions: Bool?
    let isStalled: Bool?
}

struct TagItemPayload: Codable {
    let id: String?
    let name: String?
    let status: String?
    let availableTasks: Int?
    let remainingTasks: Int?
    let totalTasks: Int?
}
