import Foundation
import Testing
@testable import OmniFocusCore

private func decodeMutation<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(type, from: Data(json.utf8))
}

@Test
func everySupportedSparseTaskFieldDecodes() throws {
    let patches = [
        #"{"name":"Renamed"}"#,
        #"{"note":"Replacement"}"#,
        #"{"noteAppend":"Append"}"#,
        #"{"flagged":true}"#,
        #"{"estimatedMinutes":15}"#,
        #"{"dueDate":"2026-07-15T09:00:00Z"}"#,
        #"{"clearDueDate":true}"#,
        #"{"deferDate":"2026-07-15T09:00:00Z"}"#,
        #"{"clearDeferDate":true}"#,
        #"{"tags":{"add":["tag-1"]}}"#,
        #"{"tags":{"remove":["tag-1"]}}"#,
        #"{"tags":{"set":["tag-1"]}}"#,
        #"{"tags":{"clear":true}}"#
    ]

    for patch in patches {
        let decoded = try decodeMutation(TaskPatchMutation.self, from: patch)
        #expect(!decoded.isEmpty)
        try decoded.validate()
    }
}

@Test
func everySupportedSparseProjectFieldDecodes() throws {
    let patches = [
        #"{"name":"Renamed"}"#,
        #"{"note":"Replacement"}"#,
        #"{"noteAppend":"Append"}"#,
        #"{"flagged":true}"#,
        #"{"dueDate":"2026-07-15T09:00:00Z"}"#,
        #"{"clearDueDate":true}"#,
        #"{"deferDate":"2026-07-15T09:00:00Z"}"#,
        #"{"clearDeferDate":true}"#,
        #"{"sequential":true}"#,
        #"{"reviewInterval":{"steps":1,"unit":"weeks"}}"#,
        #"{"reviewedNow":true}"#
    ]

    for patch in patches {
        let decoded = try decodeMutation(ProjectPatchMutation.self, from: patch)
        #expect(!decoded.isEmpty)
        try decoded.validate()
    }
}

@Test
func reviewedNowRejectsFalseAndMixedProjectPatches() {
    let patches = [
        ProjectPatchMutation(reviewedNow: false),
        ProjectPatchMutation(flagged: true, reviewedNow: true),
        ProjectPatchMutation(reviewInterval: ReviewInterval(steps: 1, unit: "weeks"), reviewedNow: true)
    ]

    for patch in patches {
        #expect(throws: MutationValidationError.self) {
            try patch.validate()
        }
    }
}

@Test
func sparseTaskPatchDecodesOmittedClearFlagsAsFalse() throws {
    let flagged = try decodeMutation(TaskPatchMutation.self, from: #"{"flagged":true}"#)
    #expect(flagged.flagged == true)
    #expect(!flagged.clearDueDate)
    #expect(!flagged.clearDeferDate)

    let dueDate = try decodeMutation(TaskPatchMutation.self, from: #"{"dueDate":"2026-07-15T09:00:00Z"}"#)
    #expect(dueDate.dueDate != nil)
    #expect(!dueDate.clearDueDate)
    #expect(!dueDate.clearDeferDate)
}

@Test
func sparseProjectPatchDecodesOmittedClearFlagsAsFalse() throws {
    let patch = try decodeMutation(
        ProjectPatchMutation.self,
        from: #"{"sequential":true,"reviewInterval":{"steps":1,"unit":"weeks"}}"#
    )
    #expect(patch.sequential == true)
    #expect(patch.reviewInterval == ReviewInterval(steps: 1, unit: "weeks"))
    #expect(!patch.clearDueDate)
    #expect(!patch.clearDeferDate)
}

@Test
func sparseTagMutationDecodesOmittedClearAsFalse() throws {
    let patch = try decodeMutation(TaskPatchMutation.self, from: #"{"tags":{"add":["tag-1"]}}"#)
    #expect(patch.tags == TagMutation(add: ["tag-1"]))
    #expect(patch.tags?.clear == false)
}

@Test
func mutationRequestRoundTripPreservesOperationShape() throws {
    let request = MutationRequest(
        targetType: .task,
        targetIDs: ["task-1", "task-2"],
        operation: MutationOperation(
            kind: .updateTasks,
            taskPatch: TaskPatchMutation(
                name: "Renamed",
                noteAppend: "append",
                flagged: true,
                estimatedMinutes: 25,
                dueDate: Date(timeIntervalSince1970: 1_700_000_000),
                tags: TagMutation(add: ["tag-1"])
            )
        ),
        previewOnly: true,
        verify: true,
        returnFields: ["id", "name", "flagged"]
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let data = try encoder.encode(request)
    let decoded = try decoder.decode(MutationRequest.self, from: data)

    #expect(decoded == request)
}

@Test
func consolidatedEditFactoriesPreserveSpecializedRequestShapes() throws {
    let shared = (previewOnly: true, verify: true, returnFields: ["id", "name"])
    let taskPatch = TaskPatchMutation(flagged: true)
    let completion = CompletionMutation(state: .completed)
    let taskMove = MoveMutation(destinationKind: .project, destinationID: "project-2", position: "ending")
    let projectPatch = ProjectPatchMutation(flagged: true)
    let projectStatus = ProjectStatusMutation(status: .onHold)
    let projectMove = MoveMutation(destinationKind: .folder, destinationID: "folder-1", position: "beginning")

    let cases: [(MutationRequest, MutationRequest)] = [
        (
            try MutationRequest.editTasks(targetIDs: ["task-1"], operation: .update, taskPatch: taskPatch, previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields),
            MutationRequest(targetType: .task, targetIDs: ["task-1"], operation: MutationOperation(kind: .updateTasks, taskPatch: taskPatch), previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields)
        ),
        (
            try MutationRequest.editTasks(targetIDs: ["task-1"], operation: .setCompletion, completion: completion, previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields),
            MutationRequest(targetType: .task, targetIDs: ["task-1"], operation: MutationOperation(kind: .setTasksCompletion, completion: completion), previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields)
        ),
        (
            try MutationRequest.editTasks(targetIDs: ["task-1"], operation: .move, move: taskMove, previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields),
            MutationRequest(targetType: .task, targetIDs: ["task-1"], operation: MutationOperation(kind: .moveTasks, move: taskMove), previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields)
        ),
        (
            try MutationRequest.editProjects(targetIDs: ["project-1"], operation: .update, projectPatch: projectPatch, previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields),
            MutationRequest(targetType: .project, targetIDs: ["project-1"], operation: MutationOperation(kind: .updateProjects, projectPatch: projectPatch), previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields)
        ),
        (
            try MutationRequest.editProjects(targetIDs: ["project-1"], operation: .setStatus, projectStatus: projectStatus, previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields),
            MutationRequest(targetType: .project, targetIDs: ["project-1"], operation: MutationOperation(kind: .setProjectsStatus, projectStatus: projectStatus), previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields)
        ),
        (
            try MutationRequest.editProjects(targetIDs: ["project-1"], operation: .setCompletion, completion: completion, previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields),
            MutationRequest(targetType: .project, targetIDs: ["project-1"], operation: MutationOperation(kind: .setProjectsCompletion, completion: completion), previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields)
        ),
        (
            try MutationRequest.editProjects(targetIDs: ["project-1"], operation: .move, move: projectMove, previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields),
            MutationRequest(targetType: .project, targetIDs: ["project-1"], operation: MutationOperation(kind: .moveProjects, move: projectMove), previewOnly: shared.previewOnly, verify: shared.verify, returnFields: shared.returnFields)
        )
    ]

    for (consolidated, specialized) in cases {
        #expect(consolidated == specialized)
    }
}

@Test
func mutationRequestValidationRejectsWrongTargetType() {
    let request = MutationRequest(
        targetType: .task,
        targetIDs: ["project-1"],
        operation: MutationOperation(
            kind: .setProjectsStatus,
            projectStatus: ProjectStatusMutation(status: .active)
        ),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationRejectsMissingProjectCompletionPayload() {
    let request = MutationRequest(
        targetType: .project,
        targetIDs: ["project-1"],
        operation: MutationOperation(kind: .setProjectsCompletion),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationRejectsEmptyPatch() {
    let request = MutationRequest(
        targetType: .project,
        targetIDs: ["project-1"],
        operation: MutationOperation(
            kind: .updateProjects,
            projectPatch: ProjectPatchMutation()
        ),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationRejectsConflictingTaskDateModes() {
    let request = MutationRequest(
        targetType: .task,
        targetIDs: ["task-1"],
        operation: MutationOperation(
            kind: .updateTasks,
            taskPatch: TaskPatchMutation(
                dueDate: Date(timeIntervalSince1970: 1_700_000_000),
                clearDueDate: true
            )
        ),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func projectPatchValidationRejectsUnsupportedFields() {
    let unsupported: [ProjectPatchMutation] = [
        ProjectPatchMutation(containsSingletonActions: true),
        ProjectPatchMutation(completedByChildren: true),
        ProjectPatchMutation(tags: TagMutation(clear: true))
    ]

    for patch in unsupported {
        let request = MutationRequest(
            targetType: .project,
            targetIDs: ["project-1"],
            operation: MutationOperation(
                kind: .updateProjects,
                projectPatch: patch
            ),
            previewOnly: true
        )

        #expect(throws: MutationValidationError.self) {
            try request.validate()
        }
    }
}

@Test
func mutationRequestValidationRejectsConflictingProjectDateModes() {
    let request = MutationRequest(
        targetType: .project,
        targetIDs: ["project-1"],
        operation: MutationOperation(
            kind: .updateProjects,
            projectPatch: ProjectPatchMutation(
                dueDate: Date(timeIntervalSince1970: 1_700_000_000),
                clearDueDate: true
            )
        ),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationRejectsConflictingTagModes() {
    let request = MutationRequest(
        targetType: .task,
        targetIDs: ["task-1"],
        operation: MutationOperation(
            kind: .updateTasks,
            taskPatch: TaskPatchMutation(
                tags: TagMutation(add: ["tag-1"], set: ["tag-2"])
            )
        ),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationRejectsUnsupportedTaskReturnFields() {
    let request = MutationRequest(
        targetType: .task,
        targetIDs: ["task-1"],
        operation: MutationOperation(
            kind: .updateTasks,
            taskPatch: TaskPatchMutation(name: "Renamed")
        ),
        previewOnly: true,
        returnFields: ["id", "status"]
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationRejectsMissingMoveDestinationID() {
    let request = MutationRequest(
        targetType: .task,
        targetIDs: ["task-1"],
        operation: MutationOperation(
            kind: .moveTasks,
            move: MoveMutation(destinationKind: .project, position: "ending")
        ),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationRejectsInvalidMovePosition() {
    let request = MutationRequest(
        targetType: .task,
        targetIDs: ["task-1"],
        operation: MutationOperation(
            kind: .moveTasks,
            move: MoveMutation(destinationKind: .inbox, position: "middle")
        ),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationAllowsProjectMoveToRootLibrary() throws {
    let request = MutationRequest(
        targetType: .project,
        targetIDs: ["project-1"],
        operation: MutationOperation(
            kind: .moveProjects,
            move: MoveMutation(destinationKind: .folder, position: "ending")
        ),
        previewOnly: true
    )

    try request.validate()
}

@Test
func mutationRequestValidationAllowsProjectMoveToFolder() throws {
    let request = MutationRequest(
        targetType: .project,
        targetIDs: ["project-1"],
        operation: MutationOperation(
            kind: .moveProjects,
            move: MoveMutation(destinationKind: .folder, destinationID: "folder-1", position: "beginning")
        ),
        previewOnly: true
    )

    try request.validate()
}

@Test
func mutationRequestValidationRejectsTaskMoveToFolder() {
    let request = MutationRequest(
        targetType: .task,
        targetIDs: ["task-1"],
        operation: MutationOperation(
            kind: .moveTasks,
            move: MoveMutation(destinationKind: .folder, destinationID: "folder-1", position: "ending")
        ),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationRejectsProjectMoveToProject() {
    let request = MutationRequest(
        targetType: .project,
        targetIDs: ["project-1"],
        operation: MutationOperation(
            kind: .moveProjects,
            move: MoveMutation(destinationKind: .project, destinationID: "project-2", position: "ending")
        ),
        previewOnly: true
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationRequestValidationRejectsUnsupportedProjectReturnFields() {
    let request = MutationRequest(
        targetType: .project,
        targetIDs: ["project-1"],
        operation: MutationOperation(
            kind: .setProjectsStatus,
            projectStatus: ProjectStatusMutation(status: .active)
        ),
        previewOnly: true,
        returnFields: ["id", "projectName"]
    )

    #expect(throws: MutationValidationError.self) {
        try request.validate()
    }
}

@Test
func mutationResponseSupportsSummaryAndReturnedFields() throws {
    let response = MutationResponse(
        targetType: .task,
        operationKind: .setTasksCompletion,
        previewOnly: true,
        verify: true,
        requestedCount: 2,
        successCount: 1,
        failureCount: 1,
        results: [
            MutationItemResult(
                id: "task-1",
                status: .previewed,
                message: "Validated target for preview.",
                returnedFields: ["completed": .bool(true), "name": .string("Task")]
            ),
            MutationItemResult(
                id: "task-missing",
                status: .failed,
                message: "Target ID not found."
            )
        ],
        warnings: ["preview only"]
    )

    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(MutationResponse.self, from: data)

    #expect(decoded == response)
}
