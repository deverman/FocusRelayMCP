import Foundation

/// Creation is separate from homogeneous edits: siblings can have different fields.
public struct TaskCreationRequest: Codable, Sendable, Equatable {
    public static let maximumTaskCount = 20
    public static let maximumDepth = 5

    public let destination: TaskCreationDestination
    public let tasks: [TaskCreationNode]
    public let previewOnly: Bool
    public let returnFields: [String]

    public init(destination: TaskCreationDestination = .init(kind: .inbox),
                tasks: [TaskCreationNode], previewOnly: Bool = false,
                returnFields: [String] = ["name"]) {
        self.destination = destination
        self.tasks = tasks
        self.previewOnly = previewOnly
        self.returnFields = returnFields
    }

    private enum CodingKeys: String, CodingKey {
        case destination, tasks, previewOnly, returnFields
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        destination = try values.decodeIfPresent(TaskCreationDestination.self, forKey: .destination) ?? .init(kind: .inbox)
        tasks = try values.decode([TaskCreationNode].self, forKey: .tasks)
        // Match the edit tools: approval is the client's responsibility.
        previewOnly = try values.decodeIfPresent(Bool.self, forKey: .previewOnly) ?? false
        returnFields = try values.decodeIfPresent([String].self, forKey: .returnFields) ?? ["name"]
    }

    public func validate() throws {
        try destination.validate()
        let allowedFields: Set<String> = ["name", "note", "flagged", "estimatedMinutes", "tagIDs", "dueDate", "deferDate"]
        guard Set(returnFields).count == returnFields.count, Set(returnFields).isSubset(of: allowedFields) else {
            throw MutationValidationError("returnFields must contain unique supported creation confirmation fields.")
        }
        guard !tasks.isEmpty else { throw MutationValidationError("Creation requires at least one task.") }
        var identifiers = Set<String>()
        var count = 0
        func visit(_ nodes: [TaskCreationNode], depth: Int) throws {
            guard depth <= Self.maximumDepth else {
                throw MutationValidationError("Creation supports at most \(Self.maximumDepth) hierarchy levels.")
            }
            for node in nodes {
                count += 1
                guard count <= Self.maximumTaskCount else {
                    throw MutationValidationError("Creation supports at most \(Self.maximumTaskCount) tasks including subtasks.")
                }
                try node.validateFields()
                if !previewOnly && (node.due?.on != nil || node.defer?.on != nil) {
                    throw MutationValidationError("Preview date-only values first, then submit the returned applyRequest.")
                }
                guard identifiers.insert(node.clientID).inserted else {
                    throw MutationValidationError("Every created task must have a unique clientID within the request.")
                }
                if !node.children.isEmpty { try visit(node.children, depth: depth + 1) }
            }
        }
        try visit(tasks, depth: 1)
    }

    /// Preorder is constructor order; siblingIndex is relative to newly requested siblings,
    /// not the destination's existing children. Final native order is verified by the Bridge.
    public func orderedNodes() throws -> [OrderedTaskCreationNode] {
        try validate()
        var result: [OrderedTaskCreationNode] = []
        func visit(_ nodes: [TaskCreationNode], parent: String?) {
            for (index, node) in nodes.enumerated() {
                result.append(.init(clientID: node.clientID, parentClientID: parent, siblingIndex: index, node: node))
                visit(node.children, parent: node.clientID)
            }
        }
        visit(tasks, parent: nil)
        return result
    }
}

public struct OrderedTaskCreationNode: Sendable, Equatable {
    public let clientID: String
    public let parentClientID: String?
    public let siblingIndex: Int
    public let node: TaskCreationNode
}

public struct TaskCreationDestination: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case inbox, project; case parentTask = "parent_task" }
    public let kind: Kind
    public let id: String?

    public init(kind: Kind, id: String? = nil) { self.kind = kind; self.id = id }

    public func validate() throws {
        switch kind {
        case .inbox:
            guard id == nil else { throw MutationValidationError("An inbox destination must not contain an ID.") }
        case .project, .parentTask:
            guard let id, !id.isEmpty, id == id.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw MutationValidationError("Project and parent_task destinations require an existing stable ID, not a name.")
            }
        }
    }
}

public struct TaskCreationNode: Codable, Sendable, Equatable {
    public let clientID: String
    public let name: String
    public let note: String?
    public let flagged: Bool?
    public let estimatedMinutes: Int?
    public let tagIDs: [String]?
    public let due: TaskCreationDate?
    public let `defer`: TaskCreationDate?
    public let children: [TaskCreationNode]

    public init(clientID: String, name: String, note: String? = nil, flagged: Bool? = nil,
                estimatedMinutes: Int? = nil, tagIDs: [String]? = nil, due: TaskCreationDate? = nil,
                defer: TaskCreationDate? = nil, children: [TaskCreationNode] = []) {
        self.clientID = clientID; self.name = name; self.note = note; self.flagged = flagged
        self.estimatedMinutes = estimatedMinutes; self.tagIDs = tagIDs; self.due = due
        self.defer = `defer`; self.children = children
    }

    private enum CodingKeys: String, CodingKey { case clientID, name, note, flagged, estimatedMinutes, tagIDs, due, `defer`, children }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try values.decode(String.self, forKey: .clientID)
        name = try values.decode(String.self, forKey: .name)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        flagged = try values.decodeIfPresent(Bool.self, forKey: .flagged)
        estimatedMinutes = try values.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        tagIDs = try values.decodeIfPresent([String].self, forKey: .tagIDs)
        due = try values.decodeIfPresent(TaskCreationDate.self, forKey: .due)
        self.defer = try values.decodeIfPresent(TaskCreationDate.self, forKey: .defer)
        children = try values.decodeIfPresent([TaskCreationNode].self, forKey: .children) ?? []
    }

    func validateFields() throws {
        guard clientID.range(of: #"\A[A-Za-z0-9_-]{1,64}\z"#, options: .regularExpression) != nil else {
            throw MutationValidationError("clientID must contain 1–64 ASCII letters, digits, underscores, or hyphens.")
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MutationValidationError("Created tasks require a non-empty name.")
        }
        if let estimatedMinutes, estimatedMinutes < 0 {
            throw MutationValidationError("estimatedMinutes must be non-negative.")
        }
        if let tagIDs {
            guard Set(tagIDs).count == tagIDs.count,
                  tagIDs.allSatisfy({ !$0.isEmpty && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) }) else {
                throw MutationValidationError("tagIDs must contain unique, non-empty existing stable IDs.")
            }
        }
        try due?.validate()
        try self.defer?.validate()
    }
}

/// Structured date intent only. No locale-dependent or unrestricted natural-language parser.
/// The Bridge, not the model, resolves `on` using current OmniFocus settings during preview.
public struct TaskCreationDate: Codable, Sendable, Equatable {
    public struct Time: Codable, Sendable, Equatable {
        public enum Policy: String, Codable, Sendable { case omnifocusDefault = "omnifocus_default" }
        public let policy: Policy
        public init(policy: Policy = .omnifocusDefault) { self.policy = policy }
    }
    public let at: String?
    public let on: String?
    public let time: Time?

    public init(at: String? = nil, on: String? = nil, time: Time? = nil) {
        self.at = at; self.on = on; self.time = time
    }

    public func validate() throws {
        guard (at != nil) != (on != nil) else {
            throw MutationValidationError("A creation date requires exactly one of at (exact timestamp) or on (calendar date).")
        }
        if let at {
            guard time == nil else { throw MutationValidationError("An exact timestamp must not specify a default-time policy.") }
            guard at.range(of: #"\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,3})?(Z|[+-]\d{2}:\d{2})\z"#, options: .regularExpression) != nil,
                  Self.validCalendarDate(String(at.prefix(10))) else {
                throw MutationValidationError("at must be a valid ISO-8601 timestamp including seconds, at most millisecond precision, and Z or an explicit timezone offset.")
            }
            let clock = at.dropFirst(11).prefix(8).split(separator: ":").compactMap { Int($0) }
            guard clock.count == 3, clock[0] < 24, clock[1] < 60, clock[2] < 60 else {
                throw MutationValidationError("at contains an invalid time; normalized or overflowing times are not accepted.")
            }
            if !at.hasSuffix("Z") {
                let offset = at.suffix(5).split(separator: ":").compactMap { Int($0) }
                guard offset.count == 2, offset[0] <= 14, offset[1] < 60,
                      offset[0] < 14 || offset[1] == 0 else {
                    throw MutationValidationError("at contains an invalid timezone offset.")
                }
            }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = at.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            guard formatter.date(from: at) != nil else { throw MutationValidationError("at is not a valid timestamp.") }
        } else if let on {
            guard Self.validCalendarDate(on), time?.policy == .omnifocusDefault else {
                throw MutationValidationError("on must be a real YYYY-MM-DD date with time.policy=omnifocus_default.")
            }
        }
    }

    private static func validCalendarDate(_ value: String) -> Bool {
        guard value.range(of: #"\A\d{4}-\d{2}-\d{2}\z"#, options: .regularExpression) != nil else { return false }
        let numbers = value.split(separator: "-").compactMap { Int($0) }
        guard numbers.count == 3, numbers[0] >= 1, (1...12).contains(numbers[1]), (1...31).contains(numbers[2]) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let requested = DateComponents(year: numbers[0], month: numbers[1], day: numbers[2])
        guard let date = calendar.date(from: requested) else { return false }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        return actual.year == requested.year && actual.month == requested.month && actual.day == requested.day
    }
}
