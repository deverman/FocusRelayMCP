import Foundation
import Testing
@testable import OmniFocusCore

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
