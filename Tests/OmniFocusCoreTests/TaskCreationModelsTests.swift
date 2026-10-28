import Foundation
import Testing
@testable import OmniFocusCore

@Suite("Task creation contract")
struct TaskCreationModelsTests {
    @Test func omittedFlagsDecodeAsWriteLikeEdits() throws {
        let json = #"{"tasks":[{"clientID":"one","name":"Capture"}]}"#
        let request = try JSONDecoder().decode(TaskCreationRequest.self, from: Data(json.utf8))
        try request.validate()
        #expect(!request.previewOnly)
        #expect(request.destination.kind == .inbox)
        #expect(request.tasks[0].children.isEmpty)
    }

    @Test func dateOnlyApplyRequiresPreviewButExactApplyIsAllowed() throws {
        let dateOnly = TaskCreationNode(clientID: "one", name: "Capture", due: .init(on: "2026-10-06", time: .init()))
        #expect(throws: MutationValidationError.self) {
            try TaskCreationRequest(tasks: [dateOnly]).validate()
        }
        try TaskCreationRequest(tasks: [dateOnly], previewOnly: true).validate()
        let exact = TaskCreationNode(clientID: "one", name: "Capture", due: .init(at: "2026-10-06T09:00:00Z"))
        try TaskCreationRequest(tasks: [exact]).validate()
    }

    @Test func heterogeneousHierarchyPreservesSiblingAndConstructorOrder() throws {
        let parent = TaskCreationNode(clientID: "plan", name: "Plan", note: "Approved steps", children: [
            .init(clientID: "research", name: "Research", flagged: true, tagIDs: ["tag-id"]),
            .init(clientID: "draft", name: "Draft", children: [.init(clientID: "review", name: "Review")])
        ])
        let request = TaskCreationRequest(destination: .init(kind: .project, id: "project-id"),
                                          tasks: [parent, .init(clientID: "send", name: "Send", estimatedMinutes: 10)])
        let ordered = try request.orderedNodes()
        #expect(ordered.map(\.clientID) == ["plan", "research", "draft", "review", "send"])
        #expect(ordered.map(\.parentClientID) == [nil, "plan", "plan", "draft", nil])
        #expect(ordered.map(\.siblingIndex) == [0, 0, 1, 0, 1])
        #expect(ordered[1].node.flagged == true)
        #expect(ordered.last?.node.estimatedMinutes == 10)
        #expect(try JSONDecoder().decode(TaskCreationRequest.self, from: JSONEncoder().encode(request)) == request)
    }

    @Test func destinationsAreExplicitAndBounded() throws {
        try TaskCreationDestination(kind: .inbox).validate()
        try TaskCreationDestination(kind: .project, id: "project-id").validate()
        try TaskCreationDestination(kind: .parentTask, id: "task-id").validate()
        for destination in [TaskCreationDestination(kind: .inbox, id: "unexpected"),
                            .init(kind: .project), .init(kind: .parentTask, id: " "),
                            .init(kind: .project, id: " project-id ")] {
            #expect(throws: MutationValidationError.self) { try destination.validate() }
        }
    }

    @Test func validatesEveryNodeBeforeDispatch() {
        let invalidNodes: [TaskCreationNode] = [
            .init(clientID: "", name: "One"), .init(clientID: "../unsafe", name: "One"),
            .init(clientID: "one\n", name: "One"), .init(clientID: String(repeating: "a", count: 65), name: "One"),
            .init(clientID: "one", name: "\n "), .init(clientID: "one", name: "One", estimatedMinutes: -1),
            .init(clientID: "one", name: "One", tagIDs: ["tag", "tag"]),
            .init(clientID: "one", name: "One", tagIDs: [" "]),
            .init(clientID: "one", name: "One", due: .init(on: "2026-02-30", time: .init()))
        ]
        for node in invalidNodes {
            let root = TaskCreationNode(clientID: "root", name: "Valid root", children: [node])
            #expect(throws: MutationValidationError.self) {
                try TaskCreationRequest(tasks: [root]).orderedNodes()
            }
        }
    }

    @Test func rejectsDuplicateIDsEmptyPlansAndOversizedHierarchies() throws {
        let one = TaskCreationNode(clientID: "one", name: "One")
        let duplicate = TaskCreationNode(clientID: "root", name: "Root", children: [one])
        for tasks in [[], [one, duplicate], (0...20).map({ TaskCreationNode(clientID: "id-\($0)", name: "Task") })] {
            #expect(throws: MutationValidationError.self) { try TaskCreationRequest(tasks: tasks).validate() }
        }
        let limit = (0..<20).map { TaskCreationNode(clientID: "id-\($0)", name: "Task") }
        try TaskCreationRequest(tasks: limit).validate()
        var tree = one
        for level in 1...4 { tree = .init(clientID: "parent-\(level)", name: "Parent", children: [tree]) }
        try TaskCreationRequest(tasks: [tree]).validate()
        tree = .init(clientID: "too-deep", name: "Parent", children: [tree])
        #expect(throws: MutationValidationError.self) { try TaskCreationRequest(tasks: [tree]).validate() }
    }

    @Test(arguments: ["2026-08-18T09:00:00Z", "2026-08-18T17:00:00+08:00", "2026-08-18T09:00:00.123Z", "2024-02-29T00:00:00-05:00"])
    func exactDatesRequireAnUnambiguousInstant(at: String) throws { try TaskCreationDate(at: at).validate() }

    @Test(arguments: ["2026-02-29T09:00:00Z", "2026-02-30T09:00:00Z", "2026-08-18T24:00:00Z", "2026-08-18T09:60:00Z", "2026-08-18T09:00:60Z", "2026-08-18T09:00:00+14:30", "2026-08-18T09:00:00+08:99", "2026-08-18T09:00:00", "tomorrow", "2026-08-18"])
    func exactDatesRejectNormalizationAndGuesses(at: String) {
        #expect(throws: MutationValidationError.self) { try TaskCreationDate(at: at).validate() }
    }

    @Test func dateOnlyIsStrictAndDoesNotResolveInTheServer() throws {
        for date in ["2024-02-29", "2026-03-08", "2026-11-01", "2026-12-31"] {
            try TaskCreationDate(on: date, time: .init()).validate()
        }
        for date in ["2026-02-29", "2026-04-31", "2026-13-01", "2026-00-01", "0000-01-01", "2026-1-1", " tomorrow "] {
            #expect(throws: MutationValidationError.self) { try TaskCreationDate(on: date, time: .init()).validate() }
        }
        for date in [TaskCreationDate(), .init(at: "2026-08-18T09:00:00Z", on: "2026-08-18", time: .init()),
                     .init(at: "2026-08-18T09:00:00Z", time: .init()), .init(on: "2026-08-18")] {
            #expect(throws: MutationValidationError.self) { try date.validate() }
        }
        let json = #"{"on":"2026-08-18","time":{"policy":"noon"}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(TaskCreationDate.self, from: Data(json.utf8)) }
    }
}
