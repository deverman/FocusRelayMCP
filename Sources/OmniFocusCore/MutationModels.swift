import Foundation

public enum MutationTargetType: String, Codable, Sendable {
    case task
    case project
}

public enum MutationOperationKind: String, Codable, Sendable {
    case updateTasks = "update_tasks"
    case setTasksCompletion = "set_tasks_completion"
    case moveTasks = "move_tasks"
    case updateProjects = "update_projects"
    case setProjectsStatus = "set_projects_status"
    case setProjectsCompletion = "set_projects_completion"
    case moveProjects = "move_projects"
}

public enum MutationCompletionState: String, Codable, Sendable {
    case active
    case completed
}

public enum MutationProjectStatus: String, Codable, Sendable {
    case active
    case onHold = "on_hold"
    case dropped
}

public enum MutationMoveDestinationKind: String, Codable, Sendable {
    case inbox
    case project
    case parentTask = "parent_task"
    case folder
}

public enum MutationItemStatus: String, Codable, Sendable {
    case previewed
    case mutated
    case failed
}

public enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

public struct TagMutation: Codable, Sendable, Equatable {
    public let add: [String]?
    public let remove: [String]?
    public let set: [String]?
    public let clear: Bool

    public init(add: [String]? = nil, remove: [String]? = nil, set: [String]? = nil, clear: Bool = false) {
        self.add = add
        self.remove = remove
        self.set = set
        self.clear = clear
    }

    public var isEmpty: Bool {
        !clear &&
        (add?.isEmpty ?? true) &&
        (remove?.isEmpty ?? true) &&
        (set?.isEmpty ?? true)
    }

    public func validate() throws {
        if let set, set.isEmpty {
            throw MutationValidationError("Tag set operations must include at least one tag ID.")
        }
        if let add, add.isEmpty {
            throw MutationValidationError("Tag add operations must include at least one tag ID.")
        }
        if let remove, remove.isEmpty {
            throw MutationValidationError("Tag remove operations must include at least one tag ID.")
        }
        if set != nil && (add != nil || remove != nil || clear) {
            throw MutationValidationError("Tag set operations cannot be combined with add, remove, or clear.")
        }
        if clear && (add != nil || remove != nil) {
            throw MutationValidationError("Tag clear operations cannot be combined with add or remove.")
        }
        if isEmpty {
            throw MutationValidationError("Tag operations must include add, remove, set, or clear.")
        }
        try validateUniqueIdentifiers(add, label: "Tag add")
        try validateUniqueIdentifiers(remove, label: "Tag remove")
        try validateUniqueIdentifiers(set, label: "Tag set")
        if let add, let remove {
            let overlap = Set(add).intersection(remove)
            if !overlap.isEmpty {
                throw MutationValidationError("Tag add and remove operations must not reference the same tag IDs.")
            }
        }
    }
}

public struct TaskPatchMutation: Codable, Sendable, Equatable {
    public let name: String?
    public let note: String?
    public let noteAppend: String?
    public let flagged: Bool?
    public let estimatedMinutes: Int?
    public let dueDate: Date?
    public let clearDueDate: Bool
    public let deferDate: Date?
    public let clearDeferDate: Bool
    public let tags: TagMutation?

    public init(
        name: String? = nil,
        note: String? = nil,
        noteAppend: String? = nil,
        flagged: Bool? = nil,
        estimatedMinutes: Int? = nil,
        dueDate: Date? = nil,
        clearDueDate: Bool = false,
        deferDate: Date? = nil,
        clearDeferDate: Bool = false,
        tags: TagMutation? = nil
    ) {
        self.name = name
        self.note = note
        self.noteAppend = noteAppend
        self.flagged = flagged
        self.estimatedMinutes = estimatedMinutes
        self.dueDate = dueDate
        self.clearDueDate = clearDueDate
        self.deferDate = deferDate
        self.clearDeferDate = clearDeferDate
        self.tags = tags
    }

    public var isEmpty: Bool {
        name == nil &&
        note == nil &&
        noteAppend == nil &&
        flagged == nil &&
        estimatedMinutes == nil &&
        dueDate == nil &&
        !clearDueDate &&
        deferDate == nil &&
        !clearDeferDate &&
        tags == nil
    }

    public func validate() throws {
        if dueDate != nil && clearDueDate {
            throw MutationValidationError("Task patches cannot set and clear dueDate in the same request.")
        }
        if deferDate != nil && clearDeferDate {
            throw MutationValidationError("Task patches cannot set and clear deferDate in the same request.")
        }
        if let estimatedMinutes, estimatedMinutes < 0 {
            throw MutationValidationError("estimatedMinutes must be zero or greater.")
        }
        try tags?.validate()
    }
}

public struct ProjectPatchMutation: Codable, Sendable, Equatable {
    public let name: String?
    public let note: String?
    public let noteAppend: String?
    public let flagged: Bool?
    public let dueDate: Date?
    public let clearDueDate: Bool
    public let deferDate: Date?
    public let clearDeferDate: Bool
    public let sequential: Bool?
    public let reviewInterval: ReviewInterval?

    public init(
        name: String? = nil,
        note: String? = nil,
        noteAppend: String? = nil,
        flagged: Bool? = nil,
        dueDate: Date? = nil,
        clearDueDate: Bool = false,
        deferDate: Date? = nil,
        clearDeferDate: Bool = false,
        sequential: Bool? = nil,
        reviewInterval: ReviewInterval? = nil
    ) {
        self.name = name
        self.note = note
        self.noteAppend = noteAppend
        self.flagged = flagged
        self.dueDate = dueDate
        self.clearDueDate = clearDueDate
        self.deferDate = deferDate
        self.clearDeferDate = clearDeferDate
        self.sequential = sequential
        self.reviewInterval = reviewInterval
    }

    public var isEmpty: Bool {
        name == nil &&
        note == nil &&
        noteAppend == nil &&
        flagged == nil &&
        dueDate == nil &&
        !clearDueDate &&
        deferDate == nil &&
        !clearDeferDate &&
        sequential == nil &&
        reviewInterval == nil
    }

    public func validate() throws {
        if dueDate != nil && clearDueDate {
            throw MutationValidationError("Project patches cannot set and clear dueDate in the same request.")
        }
        if deferDate != nil && clearDeferDate {
            throw MutationValidationError("Project patches cannot set and clear deferDate in the same request.")
        }
        if let reviewInterval, let steps = reviewInterval.steps, steps < 0 {
            throw MutationValidationError("reviewInterval.steps must be zero or greater.")
        }
    }
}

public struct CompletionMutation: Codable, Sendable, Equatable {
    public let state: MutationCompletionState

    public init(state: MutationCompletionState) {
        self.state = state
    }
}

public struct ProjectStatusMutation: Codable, Sendable, Equatable {
    public let status: MutationProjectStatus

    public init(status: MutationProjectStatus) {
        self.status = status
    }
}

public struct MoveMutation: Codable, Sendable, Equatable {
    public let destinationKind: MutationMoveDestinationKind
    public let destinationID: String?
    public let position: String?

    public init(destinationKind: MutationMoveDestinationKind, destinationID: String? = nil, position: String? = nil) {
        self.destinationKind = destinationKind
        self.destinationID = destinationID
        self.position = position
    }

    public func validate(for targetType: MutationTargetType) throws {
        let normalizedPosition = (position ?? "ending").lowercased()
        guard normalizedPosition == "beginning" || normalizedPosition == "ending" else {
            throw MutationValidationError("Move position must be beginning or ending.")
        }

        switch destinationKind {
        case .inbox:
            if targetType != .task {
                throw MutationValidationError("Only task moves can target inbox.")
            }
            if destinationID != nil {
                throw MutationValidationError("Inbox moves must not include a destinationID.")
            }
        case .project:
            guard let destinationID, !destinationID.isEmpty else {
                throw MutationValidationError("Project moves require a destinationID.")
            }
        case .parentTask:
            guard let destinationID, !destinationID.isEmpty else {
                throw MutationValidationError("Parent task moves require a destinationID.")
            }
        case .folder:
            guard let destinationID, !destinationID.isEmpty else {
                throw MutationValidationError("Folder moves require a destinationID.")
            }
        }
    }
}

public struct MutationOperation: Codable, Sendable, Equatable {
    public let kind: MutationOperationKind
    public let taskPatch: TaskPatchMutation?
    public let projectPatch: ProjectPatchMutation?
    public let completion: CompletionMutation?
    public let projectStatus: ProjectStatusMutation?
    public let move: MoveMutation?

    public init(
        kind: MutationOperationKind,
        taskPatch: TaskPatchMutation? = nil,
        projectPatch: ProjectPatchMutation? = nil,
        completion: CompletionMutation? = nil,
        projectStatus: ProjectStatusMutation? = nil,
        move: MoveMutation? = nil
    ) {
        self.kind = kind
        self.taskPatch = taskPatch
        self.projectPatch = projectPatch
        self.completion = completion
        self.projectStatus = projectStatus
        self.move = move
    }
}

public struct MutationRequest: Codable, Sendable, Equatable {
    public let targetType: MutationTargetType
    public let targetIDs: [String]
    public let operation: MutationOperation
    public let previewOnly: Bool
    public let verify: Bool
    public let returnFields: [String]?

    public init(
        targetType: MutationTargetType,
        targetIDs: [String],
        operation: MutationOperation,
        previewOnly: Bool = false,
        verify: Bool = false,
        returnFields: [String]? = nil
    ) {
        self.targetType = targetType
        self.targetIDs = targetIDs
        self.operation = operation
        self.previewOnly = previewOnly
        self.verify = verify
        self.returnFields = returnFields
    }

    public func validate() throws {
        guard !targetIDs.isEmpty else {
            throw MutationValidationError("Mutation requests must include at least one target ID.")
        }
        if Set(targetIDs).count != targetIDs.count {
            throw MutationValidationError("Mutation requests must not contain duplicate target IDs.")
        }

        switch operation.kind {
        case .updateTasks:
            guard targetType == .task else {
                throw MutationValidationError("update_tasks requires task targets.")
            }
            guard let taskPatch = operation.taskPatch, !taskPatch.isEmpty else {
                throw MutationValidationError("update_tasks requires a non-empty taskPatch.")
            }
            try taskPatch.validate()
        case .setTasksCompletion:
            guard targetType == .task else {
                throw MutationValidationError("set_tasks_completion requires task targets.")
            }
            guard operation.completion != nil else {
                throw MutationValidationError("set_tasks_completion requires a completion payload.")
            }
        case .moveTasks:
            guard targetType == .task else {
                throw MutationValidationError("move_tasks requires task targets.")
            }
            guard let move = operation.move else {
                throw MutationValidationError("move_tasks requires a move payload.")
            }
            try move.validate(for: targetType)
        case .updateProjects:
            guard targetType == .project else {
                throw MutationValidationError("update_projects requires project targets.")
            }
            guard let projectPatch = operation.projectPatch, !projectPatch.isEmpty else {
                throw MutationValidationError("update_projects requires a non-empty projectPatch.")
            }
            try projectPatch.validate()
        case .setProjectsStatus:
            guard targetType == .project else {
                throw MutationValidationError("set_projects_status requires project targets.")
            }
            guard operation.projectStatus != nil else {
                throw MutationValidationError("set_projects_status requires a projectStatus payload.")
            }
        case .setProjectsCompletion:
            guard targetType == .project else {
                throw MutationValidationError("set_projects_completion requires project targets.")
            }
            guard operation.completion != nil else {
                throw MutationValidationError("set_projects_completion requires a completion payload.")
            }
        case .moveProjects:
            guard targetType == .project else {
                throw MutationValidationError("move_projects requires project targets.")
            }
            guard let move = operation.move else {
                throw MutationValidationError("move_projects requires a move payload.")
            }
            try move.validate(for: targetType)
        }

        if let returnFields {
            let allowedFields = targetType == .task ? Self.allowedTaskReturnFields : Self.allowedProjectReturnFields
            let unsupportedFields = returnFields.filter { !allowedFields.contains($0) }
            if !unsupportedFields.isEmpty {
                throw MutationValidationError("Unsupported returnFields for \(targetType.rawValue) mutations: \(unsupportedFields.joined(separator: ", ")).")
            }
        }
    }

    private static let allowedTaskReturnFields: Set<String> = [
        "id", "name", "note", "projectID", "projectName",
        "tagIDs", "tagNames", "dueDate", "plannedDate", "deferDate",
        "completionDate", "completed", "flagged", "estimatedMinutes", "available"
    ]

    private static let allowedProjectReturnFields: Set<String> = [
        "id", "name", "note", "status", "flagged", "lastReviewDate",
        "nextReviewDate", "reviewInterval", "availableTasks", "remainingTasks",
        "completedTasks", "droppedTasks", "totalTasks", "hasChildren", "nextTask",
        "containsSingletonActions", "isStalled", "completionDate"
    ]
}

public struct MutationItemResult: Codable, Sendable, Equatable {
    public let id: String
    public let status: MutationItemStatus
    public let message: String?
    public let returnedFields: [String: JSONValue]?

    public init(
        id: String,
        status: MutationItemStatus,
        message: String? = nil,
        returnedFields: [String: JSONValue]? = nil
    ) {
        self.id = id
        self.status = status
        self.message = message
        self.returnedFields = returnedFields
    }
}

public struct MutationResponse: Codable, Sendable, Equatable {
    public let targetType: MutationTargetType
    public let operationKind: MutationOperationKind
    public let previewOnly: Bool
    public let verify: Bool
    public let requestedCount: Int
    public let successCount: Int
    public let failureCount: Int
    public let results: [MutationItemResult]
    public let warnings: [String]

    public init(
        targetType: MutationTargetType,
        operationKind: MutationOperationKind,
        previewOnly: Bool,
        verify: Bool,
        requestedCount: Int,
        successCount: Int,
        failureCount: Int,
        results: [MutationItemResult],
        warnings: [String] = []
    ) {
        self.targetType = targetType
        self.operationKind = operationKind
        self.previewOnly = previewOnly
        self.verify = verify
        self.requestedCount = requestedCount
        self.successCount = successCount
        self.failureCount = failureCount
        self.results = results
        self.warnings = warnings
    }
}

public struct MutationValidationError: Error, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

private func validateUniqueIdentifiers(_ ids: [String]?, label: String) throws {
    guard let ids else { return }
    if Set(ids).count != ids.count {
        throw MutationValidationError("\(label) operations must not contain duplicate tag IDs.")
    }
}
