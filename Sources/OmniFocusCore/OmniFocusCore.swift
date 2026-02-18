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

public struct ReviewInterval: Codable, Sendable {
    public let steps: Int?
    public let unit: String?

    public init(steps: Int? = nil, unit: String? = nil) {
        self.steps = steps
        self.unit = unit
    }
}

public struct ProjectItem: Codable, Sendable {
    public let id: String
    public let name: String
    public let note: String?
    public let status: String
    public let flagged: Bool
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
        id: String,
        name: String,
        note: String? = nil,
        status: String,
        flagged: Bool,
        lastReviewDate: Date? = nil,
        nextReviewDate: Date? = nil,
        reviewInterval: ReviewInterval? = nil,
        availableTasks: Int? = nil,
        remainingTasks: Int? = nil,
        completedTasks: Int? = nil,
        droppedTasks: Int? = nil,
        totalTasks: Int? = nil,
        hasChildren: Bool? = nil,
        nextTask: ProjectTaskSummary? = nil,
        containsSingletonActions: Bool? = nil,
        isStalled: Bool? = nil,
        completionDate: Date? = nil
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
    public let returnedCount: Int
    public let totalCount: Int?

    public init(items: [T], nextCursor: String? = nil, returnedCount: Int, totalCount: Int? = nil) {
        self.items = items
        self.nextCursor = nextCursor
        self.returnedCount = returnedCount
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
    public var reviewDueBefore: Date?
    public var reviewDueAfter: Date?
    public var reviewPerspective: Bool?
    public var completed: Bool?
    public var completedBefore: Date?
    public var completedAfter: Date?

    public init(
        statusFilter: String? = nil,
        includeTaskCounts: Bool? = nil,
        reviewDueBefore: Date? = nil,
        reviewDueAfter: Date? = nil,
        reviewPerspective: Bool? = nil,
        completed: Bool? = nil,
        completedBefore: Date? = nil,
        completedAfter: Date? = nil
    ) {
        self.statusFilter = statusFilter
        self.includeTaskCounts = includeTaskCounts
        self.reviewDueBefore = reviewDueBefore
        self.reviewDueAfter = reviewDueAfter
        self.reviewPerspective = reviewPerspective
        self.completed = completed
        self.completedBefore = completedBefore
        self.completedAfter = completedAfter
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
    public var includeTotalCount: Bool?

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
        includeTotalCount: Bool? = nil
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
        self.includeTotalCount = includeTotalCount
        self.deferBefore = deferBefore
        self.deferAfter = deferAfter
        self.completedBefore = completedBefore
        self.completedAfter = completedAfter
    }

    /// Date-range and full-text filters can force OmniFocus to scan much larger
    /// data sets, so callers may need a longer bridge timeout budget.
    public var requiresExtendedBridgeTimeout: Bool {
        dueBefore != nil ||
        dueAfter != nil ||
        deferBefore != nil ||
        deferAfter != nil ||
        completedBefore != nil ||
        completedAfter != nil ||
        (search?.isEmpty == false)
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
    func listProjects(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool,
        reviewDueBefore: Date?,
        reviewDueAfter: Date?,
        reviewPerspective: Bool,
        completed: Bool?,
        completedBefore: Date?,
        completedAfter: Date?,
        fields: [String]?
    ) async throws -> Page<ProjectItem>
    func listTags(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool) async throws -> Page<TagItem>
    func getTaskCounts(filter: TaskFilter) async throws -> TaskCounts
    func getProjectCounts(filter: TaskFilter) async throws -> ProjectCounts
}
