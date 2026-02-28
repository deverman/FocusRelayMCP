import Foundation
import OmniFocusCore

public struct TaskOutput: Encodable {
    public let id: String?
    public let name: String?
    public let note: String?
    public let projectID: String?
    public let projectName: String?
    public let tagIDs: [String]?
    public let tagNames: [String]?
    public let dueDate: Date?
    public let plannedDate: Date?
    public let deferDate: Date?
    public let completionDate: Date?
    public let completed: Bool?
    public let flagged: Bool?
    public let estimatedMinutes: Int?
    public let available: Bool?

    public init(
        id: String?,
        name: String?,
        note: String?,
        projectID: String?,
        projectName: String?,
        tagIDs: [String]?,
        tagNames: [String]?,
        dueDate: Date?,
        plannedDate: Date?,
        deferDate: Date?,
        completionDate: Date?,
        completed: Bool?,
        flagged: Bool?,
        estimatedMinutes: Int?,
        available: Bool?
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.projectID = projectID
        self.projectName = projectName
        self.tagIDs = tagIDs
        self.tagNames = tagNames
        self.dueDate = dueDate
        self.plannedDate = plannedDate
        self.deferDate = deferDate
        self.completionDate = completionDate
        self.completed = completed
        self.flagged = flagged
        self.estimatedMinutes = estimatedMinutes
        self.available = available
    }
}

public struct PageOutput<T: Encodable>: Encodable {
    public let items: [T]
    public let nextCursor: String?
    public let returnedCount: Int
    public let totalCount: Int?

    public init(items: [T], nextCursor: String? = nil, returnedCount: Int, totalCount: Int? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.returnedCount = returnedCount
        self.totalCount = totalCount
    }
}

public struct ProjectOutput: Encodable {
    public let id: String?
    public let name: String?
    public let note: String?
    public let status: String?
    public let flagged: Bool?
    public let lastReviewDate: Date?
    public let nextReviewDate: Date?
    public let reviewInterval: ReviewInterval?
    public let availableTasks: Int?
    public let remainingTasks: Int?
    public let completedTasks: Int?
    public let droppedTasks: Int?
    public let totalTasks: Int?
    public let hasChildren: Bool?
    public let nextTask: ProjectTaskSummary?
    public let containsSingletonActions: Bool?
    public let isStalled: Bool?
    public let completionDate: Date?

    public init(
        id: String?,
        name: String?,
        note: String?,
        status: String?,
        flagged: Bool?,
        lastReviewDate: Date?,
        nextReviewDate: Date?,
        reviewInterval: ReviewInterval?,
        availableTasks: Int?,
        remainingTasks: Int?,
        completedTasks: Int?,
        droppedTasks: Int?,
        totalTasks: Int?,
        hasChildren: Bool?,
        nextTask: ProjectTaskSummary?,
        containsSingletonActions: Bool?,
        isStalled: Bool?,
        completionDate: Date?
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.status = status
        self.flagged = flagged
        self.lastReviewDate = lastReviewDate
        self.nextReviewDate = nextReviewDate
        self.reviewInterval = reviewInterval
        self.availableTasks = availableTasks
        self.remainingTasks = remainingTasks
        self.completedTasks = completedTasks
        self.droppedTasks = droppedTasks
        self.totalTasks = totalTasks
        self.hasChildren = hasChildren
        self.nextTask = nextTask
        self.containsSingletonActions = containsSingletonActions
        self.isStalled = isStalled
        self.completionDate = completionDate
    }
}

public struct TagOutput: Encodable {
    public let id: String
    public let name: String
    public let status: String?
    public let availableTasks: Int?
    public let remainingTasks: Int?
    public let totalTasks: Int?

    public init(
        id: String,
        name: String,
        status: String?,
        availableTasks: Int?,
        remainingTasks: Int?,
        totalTasks: Int?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.availableTasks = availableTasks
        self.remainingTasks = remainingTasks
        self.totalTasks = totalTasks
    }
}

public func makeTaskOutput(from task: TaskItem, fields: Set<String>) -> TaskOutput {
    TaskOutput(
        id: fields.contains("id") ? task.id : nil,
        name: fields.contains("name") ? task.name : nil,
        note: fields.contains("note") ? task.note : nil,
        projectID: fields.contains("projectID") ? task.projectID : nil,
        projectName: fields.contains("projectName") ? task.projectName : nil,
        tagIDs: fields.contains("tagIDs") ? task.tagIDs : nil,
        tagNames: fields.contains("tagNames") ? task.tagNames : nil,
        dueDate: fields.contains("dueDate") ? task.dueDate : nil,
        plannedDate: fields.contains("plannedDate") ? task.plannedDate : nil,
        deferDate: fields.contains("deferDate") ? task.deferDate : nil,
        completionDate: fields.contains("completionDate") ? task.completionDate : nil,
        completed: fields.contains("completed") ? task.completed : nil,
        flagged: fields.contains("flagged") ? task.flagged : nil,
        estimatedMinutes: fields.contains("estimatedMinutes") ? task.estimatedMinutes : nil,
        available: fields.contains("available") ? task.available : nil
    )
}

public func makeProjectOutput(from project: ProjectItem, fields: Set<String>, includeTaskCounts: Bool) -> ProjectOutput {
    ProjectOutput(
        id: fields.contains("id") ? project.id : nil,
        name: fields.contains("name") ? project.name : nil,
        note: fields.contains("note") ? project.note : nil,
        status: fields.contains("status") ? project.status : nil,
        flagged: fields.contains("flagged") ? project.flagged : nil,
        lastReviewDate: fields.contains("lastReviewDate") ? project.lastReviewDate : nil,
        nextReviewDate: fields.contains("nextReviewDate") ? project.nextReviewDate : nil,
        reviewInterval: fields.contains("reviewInterval") ? project.reviewInterval : nil,
        availableTasks: includeTaskCounts ? project.availableTasks : nil,
        remainingTasks: includeTaskCounts ? project.remainingTasks : nil,
        completedTasks: includeTaskCounts ? project.completedTasks : nil,
        droppedTasks: includeTaskCounts ? project.droppedTasks : nil,
        totalTasks: includeTaskCounts ? project.totalTasks : nil,
        hasChildren: fields.contains("hasChildren") ? project.hasChildren : nil,
        nextTask: fields.contains("nextTask") ? project.nextTask : nil,
        containsSingletonActions: fields.contains("containsSingletonActions") ? project.containsSingletonActions : nil,
        isStalled: fields.contains("isStalled") ? project.isStalled : nil,
        completionDate: fields.contains("completionDate") ? project.completionDate : nil
    )
}

public func makeTagOutput(from tag: TagItem, fields: Set<String>, includeTaskCounts: Bool) -> TagOutput {
    TagOutput(
        id: tag.id,
        name: tag.name,
        status: fields.contains("status") ? tag.status : nil,
        availableTasks: includeTaskCounts ? tag.availableTasks : nil,
        remainingTasks: includeTaskCounts ? tag.remainingTasks : nil,
        totalTasks: includeTaskCounts ? tag.totalTasks : nil
    )
}

public func encodeJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    return String(decoding: data, as: UTF8.self)
}
