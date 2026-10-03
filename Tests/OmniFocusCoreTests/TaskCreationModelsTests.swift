import Foundation
import Testing
@testable import OmniFocusCore

@Suite("Task creation contract")
struct TaskCreationModelsTests {
    let key = "7186bc33-067a-44c6-afab-9a5659c5f953"

    @Test func omittedFlagsDecodeAsPreviewNotWrite() throws {
        let json = #"{"creationKey":"7186bc33-067a-44c6-afab-9a5659c5f953","tasks":[{"clientID":"one","name":"Capture"}]}"#
        let request = try JSONDecoder().decode(TaskCreationRequest.self, from: Data(json.utf8))
        try request.validate()
        #expect(request.previewOnly)
        #expect(request.destination.kind == .inbox)
        #expect(request.tasks[0].children.isEmpty)
        #expect(request.normalizedCreationKey == key.uppercased())
        #expect(request.approvedPreviewID == nil)
    }

    @Test func executionRequiresApprovalAndPreviewRejectsExecutionToken() throws {
        let task = TaskCreationNode(clientID: "one", name: "Capture")
        #expect(throws: MutationValidationError.self) {
            try TaskCreationRequest(creationKey: key, tasks: [task], previewOnly: false).validate()
        }
        #expect(throws: MutationValidationError.self) {
            try TaskCreationRequest(creationKey: key, tasks: [task], approvedPreviewID: key).validate()
        }
        try TaskCreationRequest(creationKey: key, tasks: [task], previewOnly: false, approvedPreviewID: key).validate()
        for invalid in ["", "../requests", "not-a-UUID"] {
            #expect(throws: MutationValidationError.self) {
                try TaskCreationRequest(creationKey: invalid, tasks: [task]).validate()
            }
        }
    }

    @Test func heterogeneousHierarchyPreservesSiblingAndConstructorOrder() throws {
        let parent = TaskCreationNode(clientID: "plan", name: "Plan", note: "Approved steps", children: [
            .init(clientID: "research", name: "Research", flagged: true, tagIDs: ["tag-id"]),
            .init(clientID: "draft", name: "Draft", children: [.init(clientID: "review", name: "Review")])
        ])
        let request = TaskCreationRequest(creationKey: key, destination: .init(kind: .project, id: "project-id"),
                                          tasks: [parent, .init(clientID: "send", name: "Send", estimatedMinutes: 10)])
        let ordered = try request.orderedNodes()
        #expect(ordered.map(\.clientID) == ["plan", "research", "draft", "review", "send"])
        #expect(ordered.map(\.parentClientID) == [nil, "plan", "plan", "draft", nil])
        #expect(ordered.map(\.siblingIndex) == [0, 0, 1, 0, 1])
        #expect(ordered[1].node.flagged == true)
        #expect(ordered.last?.node.estimatedMinutes == 10)
        #expect(try JSONDecoder().decode(TaskCreationRequest.self, from: JSONEncoder().encode(request)) == request)
    }

    @Test func fingerprintBindsIntentButNotExecutionFlagsOrUUIDCasing() throws {
        let tasks: [TaskCreationNode] = [.init(clientID: "one", name: "Capture", note: "Private note"),
                                        .init(clientID: "two", name: "Another", due: .init(on: "2026-10-06", time: .init()))]
        let preview = TaskCreationRequest(creationKey: key, tasks: tasks)
        let execute = TaskCreationRequest(creationKey: key.uppercased(), tasks: tasks, previewOnly: false, approvedPreviewID: key)
        let fingerprint = try preview.intentFingerprint()
        #expect(fingerprint.count == 64)
        #expect(try execute.intentFingerprint() == fingerprint)
        #expect(try TaskCreationRequest(creationKey: key, tasks: tasks.reversed()).intentFingerprint() != fingerprint)
        #expect(try TaskCreationRequest(creationKey: key, destination: .init(kind: .project, id: "different"), tasks: tasks).intentFingerprint() != fingerprint)
        for changed in [TaskCreationNode(clientID: "one", name: "Capture", note: "Changed"),
                        .init(clientID: "one", name: "Renamed", note: "Private note"),
                        .init(clientID: "one", name: "Capture", note: "Private note", flagged: true),
                        .init(clientID: "one", name: "Capture", note: "Private note", tagIDs: ["tag"])] {
            #expect(try TaskCreationRequest(creationKey: key, tasks: [changed, tasks[1]]).intentFingerprint() != fingerprint)
        }
    }

    @Test func replayAdmissionNeverAuthorizesAnotherConstructorAfterApplyBegan() throws {
        let tasks: [TaskCreationNode] = [.init(clientID: "one", name: "Capture")]
        let preview = TaskCreationRequest(creationKey: key, tasks: tasks)
        let fingerprint = try preview.intentFingerprint()
        let execute = TaskCreationRequest(creationKey: key, tasks: tasks, previewOnly: false, approvedPreviewID: key)
        func decision(_ request: TaskCreationRequest, _ state: TaskCreationReplayPolicy.State) throws -> TaskCreationReplayPolicy.Decision {
            try TaskCreationReplayPolicy.decision(for: request, storedCreationKey: key.uppercased(),
                storedFingerprint: fingerprint, storedPreviewID: key.uppercased(), state: state)
        }
        #expect(try decision(preview, .prepared) == .reusePreview)
        #expect(try decision(execute, .prepared) == .applyApprovedPreview)
        for state in [TaskCreationReplayPolicy.State.applying, .uncertain, .completed] {
            #expect(try decision(execute, state) == .reconcileOnly)
            #expect(try decision(preview, state) == .reconcileOnly)
        }
        let wrongApproval = TaskCreationRequest(creationKey: key, tasks: tasks, previewOnly: false,
                                               approvedPreviewID: "149d9457-a82f-41bb-8903-287c16231c4e")
        #expect(throws: MutationValidationError.self) { try decision(wrongApproval, .prepared) }
        let changed = TaskCreationRequest(creationKey: key, tasks: [.init(clientID: "one", name: "Changed")])
        #expect(throws: MutationValidationError.self) { try decision(changed, .prepared) }
        #expect(throws: MutationValidationError.self) {
            try TaskCreationReplayPolicy.decision(for: preview, storedCreationKey: "invalid",
                storedFingerprint: fingerprint, storedPreviewID: key, state: .prepared)
        }
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
                try TaskCreationRequest(creationKey: key, tasks: [root]).orderedNodes()
            }
        }
    }

    @Test func rejectsDuplicateIDsEmptyPlansAndOversizedHierarchies() throws {
        let one = TaskCreationNode(clientID: "one", name: "One")
        let duplicate = TaskCreationNode(clientID: "root", name: "Root", children: [one])
        for tasks in [[], [one, duplicate], (0...20).map({ TaskCreationNode(clientID: "id-\($0)", name: "Task") })] {
            #expect(throws: MutationValidationError.self) { try TaskCreationRequest(creationKey: key, tasks: tasks).validate() }
        }
        let limit = (0..<20).map { TaskCreationNode(clientID: "id-\($0)", name: "Task") }
        try TaskCreationRequest(creationKey: key, tasks: limit).validate()
        var tree = one
        for level in 1...4 { tree = .init(clientID: "parent-\(level)", name: "Parent", children: [tree]) }
        try TaskCreationRequest(creationKey: key, tasks: [tree]).validate()
        tree = .init(clientID: "too-deep", name: "Parent", children: [tree])
        #expect(throws: MutationValidationError.self) { try TaskCreationRequest(creationKey: key, tasks: [tree]).validate() }
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
