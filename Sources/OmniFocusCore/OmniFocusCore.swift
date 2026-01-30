import Foundation

public struct TaskItem: Codable, Sendable {
    public let id: String
    public let name: String
    public let note: String?
    public let projectID: String?
    public let projectName: String?
    public let tagIDs: [String]
    public let tagNames: [String]
    public let dueDate: Date?
    public let deferDate: Date?
    public let completed: Bool
    public let flagged: Bool
    public let estimatedMinutes: Int?
    public let available: Bool

    public init(
        id: String,
        name: String,
        note: String? = nil,
        projectID: String? = nil,
        projectName: String? = nil,
        tagIDs: [String] = [],
        tagNames: [String] = [],
        dueDate: Date? = nil,
        deferDate: Date? = nil,
        completed: Bool,
        flagged: Bool,
        estimatedMinutes: Int? = nil,
        available: Bool
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.projectID = projectID
        self.projectName = projectName
        self.tagIDs = tagIDs
        self.tagNames = tagNames
        self.dueDate = dueDate
        self.deferDate = deferDate
        self.completed = completed
        self.flagged = flagged
        self.estimatedMinutes = estimatedMinutes
        self.available = available
    }
}

public struct ProjectItem: Codable, Sendable {
    public let id: String
    public let name: String
    public let note: String?
    public let status: String
    public let flagged: Bool

    public init(id: String, name: String, note: String? = nil, status: String, flagged: Bool) {
        self.id = id
        self.name = name
        self.note = note
        self.status = status
        self.flagged = flagged
    }
}

public struct TagItem: Codable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct TaskCounts: Codable, Sendable {
    public let total: Int
    public let completed: Int
    public let available: Int
    public let flagged: Int

    public init(total: Int, completed: Int, available: Int, flagged: Int) {
        self.total = total
        self.completed = completed
        self.available = available
        self.flagged = flagged
    }
}

public struct ProjectCounts: Codable, Sendable {
    public let projects: Int
    public let actions: Int

    public init(projects: Int, actions: Int) {
        self.projects = projects
        self.actions = actions
    }
}

public struct Page<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let nextCursor: String?
    public let totalCount: Int?

    public init(items: [T], nextCursor: String? = nil, totalCount: Int? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.totalCount = totalCount
    }
}

public struct TaskFilter: Codable, Sendable {
    public var completed: Bool?
    public var flagged: Bool?
    public var availableOnly: Bool?
    public var inboxView: String?
    public var project: String?
    public var tags: [String]?
    public var dueBefore: Date?
    public var dueAfter: Date?
    public var deferBefore: Date?
    public var deferAfter: Date?
    public var completedBefore: Date?
    public var completedAfter: Date?
    public var search: String?
    public var inboxOnly: Bool?
    public var projectView: String?
    public var maxEstimatedMinutes: Int?
    public var minEstimatedMinutes: Int?

    public init(
        completed: Bool? = nil,
        flagged: Bool? = nil,
        availableOnly: Bool? = nil,
        inboxView: String? = nil,
        project: String? = nil,
        tags: [String]? = nil,
        dueBefore: Date? = nil,
        dueAfter: Date? = nil,
        deferBefore: Date? = nil,
        deferAfter: Date? = nil,
        completedBefore: Date? = nil,
        completedAfter: Date? = nil,
        search: String? = nil,
        inboxOnly: Bool? = nil,
        projectView: String? = nil,
        maxEstimatedMinutes: Int? = nil,
        minEstimatedMinutes: Int? = nil
    ) {
        self.completed = completed
        self.flagged = flagged
        self.availableOnly = availableOnly
        self.inboxView = inboxView
        self.project = project
        self.tags = tags
        self.dueBefore = dueBefore
        self.dueAfter = dueAfter
        self.deferBefore = deferBefore
        self.deferAfter = deferAfter
        self.completedBefore = completedBefore
        self.completedAfter = completedAfter
        self.search = search
        self.inboxOnly = inboxOnly
        self.projectView = projectView
        self.maxEstimatedMinutes = maxEstimatedMinutes
        self.minEstimatedMinutes = minEstimatedMinutes
    }
}

public struct PageRequest: Codable, Sendable {
    public let limit: Int
    public let cursor: String?

    public init(limit: Int = 50, cursor: String? = nil) {
        self.limit = limit
        self.cursor = cursor
    }
}

public protocol OmniFocusService: Sendable {
    func listTasks(filter: TaskFilter, page: PageRequest, fields: [String]?) async throws -> Page<TaskItem>
    func getTask(id: String, fields: [String]?) async throws -> TaskItem
    func listProjects(page: PageRequest, fields: [String]?) async throws -> Page<ProjectItem>
    func listTags(page: PageRequest) async throws -> Page<TagItem>
    func getTaskCounts(filter: TaskFilter) async throws -> TaskCounts
    func getProjectCounts(filter: TaskFilter) async throws -> ProjectCounts
}
