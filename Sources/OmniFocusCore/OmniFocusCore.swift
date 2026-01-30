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
    public let completionDate: Date?
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
        completionDate: Date? = nil,
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
        self.completionDate = completionDate
        self.completed = completed
        self.flagged = flagged
        self.estimatedMinutes = estimatedMinutes
        self.available = available
    }
}

public struct ProjectTaskSummary: Codable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ProjectItem: Codable, Sendable {
    public let id: String
    public let name: String
    public let note: String?
    public let status: String
    public let flagged: Bool
    public let availableTasks: Int?
    public let remainingTasks: Int?
    public let completedTasks: Int?
    public let droppedTasks: Int?
    public let totalTasks: Int?
    public let hasChildren: Bool?
    public let nextTask: ProjectTaskSummary?
    public let containsSingletonActions: Bool?
    public let isStalled: Bool?

    public init(
        id: String,
        name: String,
        note: String? = nil,
        status: String,
        flagged: Bool,
        availableTasks: Int? = nil,
        remainingTasks: Int? = nil,
        completedTasks: Int? = nil,
        droppedTasks: Int? = nil,
        totalTasks: Int? = nil,
        hasChildren: Bool? = nil,
        nextTask: ProjectTaskSummary? = nil,
        containsSingletonActions: Bool? = nil,
        isStalled: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.status = status
        self.flagged = flagged
        self.availableTasks = availableTasks
        self.remainingTasks = remainingTasks
        self.completedTasks = completedTasks
        self.droppedTasks = droppedTasks
        self.totalTasks = totalTasks
        self.hasChildren = hasChildren
        self.nextTask = nextTask
        self.containsSingletonActions = containsSingletonActions
        self.isStalled = isStalled
    }
}

public struct TagItem: Codable, Sendable {
    public let id: String
    public let name: String
    public let status: String?
    public let availableTasks: Int?
    public let remainingTasks: Int?
    public let totalTasks: Int?

    public init(
        id: String,
        name: String,
        status: String? = nil,
        availableTasks: Int? = nil,
        remainingTasks: Int? = nil,
        totalTasks: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.availableTasks = availableTasks
        self.remainingTasks = remainingTasks
        self.totalTasks = totalTasks
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

public struct TagFilter: Codable, Sendable {
    public var statusFilter: String?
    public var includeTaskCounts: Bool?

    public init(
        statusFilter: String? = nil,
        includeTaskCounts: Bool? = nil
    ) {
        self.statusFilter = statusFilter
        self.includeTaskCounts = includeTaskCounts
    }
}

public struct ProjectFilter: Codable, Sendable {
    public var statusFilter: String?
    public var includeTaskCounts: Bool?

    public init(
        statusFilter: String? = nil,
        includeTaskCounts: Bool? = nil
    ) {
        self.statusFilter = statusFilter
        self.includeTaskCounts = includeTaskCounts
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
    public var staleThreshold: String?

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
        minEstimatedMinutes: Int? = nil,
        staleThreshold: String? = nil
    ) {
        self.completed = completed
        self.flagged = flagged
        self.availableOnly = availableOnly
        self.inboxView = inboxView
        self.project = project
        self.tags = tags
        self.dueBefore = dueBefore
        self.dueAfter = dueAfter
        self.search = search
        self.inboxOnly = inboxOnly
        self.projectView = projectView
        self.maxEstimatedMinutes = maxEstimatedMinutes
        self.minEstimatedMinutes = minEstimatedMinutes
        self.staleThreshold = staleThreshold

        // staleThreshold is mutually exclusive with deferBefore - calculate deferBefore if staleThreshold is set
        if let threshold = staleThreshold {
            let days: Int
            switch threshold {
            case "7days": days = 7
            case "30days": days = 30
            case "90days": days = 90
            case "180days": days = 180
            case "270days": days = 270
            case "365days": days = 365
            default: days = 30
            }
            let calendar = Calendar.current
            let now = Date()
            self.deferBefore = calendar.date(byAdding: .day, value: -days, to: now)
            self.deferAfter = nil
        } else {
            self.deferBefore = deferBefore
            self.deferAfter = deferAfter
        }

        self.completedBefore = completedBefore
        self.completedAfter = completedAfter
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
    func listProjects(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool, fields: [String]?) async throws -> Page<ProjectItem>
    func listTags(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool) async throws -> Page<TagItem>
    func getTaskCounts(filter: TaskFilter) async throws -> TaskCounts
    func getProjectCounts(filter: TaskFilter) async throws -> ProjectCounts
}
