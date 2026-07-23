import Foundation
import Testing
@testable import OmniFocusAutomation
@testable import OmniFocusCore

@Test(.enabled(
    if: LiveTestEnvironment.taskStatusMutationEnabled,
    "Set FOCUS_RELAY_BRIDGE_TESTS=1 and FOCUS_RELAY_TASK_STATUS_FIXTURE_ID to a disposable active, non-repeating task."
))
func taskStatusDropVerifyRestoreLive() async throws {
    let taskID = try #require(LiveTestEnvironment.value("FOCUS_RELAY_TASK_STATUS_FIXTURE_ID"))
    let service = OmniFocusBridgeService()
    let fields = ["id", "name", "taskStatus", "dropDate", "completionDate"]

    let preview = try await service.performMutation(try MutationRequest.editTasks(
        targetIDs: [taskID],
        operation: .setStatus,
        taskStatus: TaskStatusMutation(status: .dropped),
        previewOnly: true,
        verify: true,
        returnFields: fields
    ))
    #expect(preview.successCount == 1)
    #expect(preview.failureCount == 0)

    var requiresRestore = false
    do {
        let dropped = try await service.performMutation(try MutationRequest.editTasks(
            targetIDs: [taskID],
            operation: .setStatus,
            taskStatus: TaskStatusMutation(status: .dropped),
            verify: true,
            returnFields: fields
        ))
        requiresRestore = true
        let droppedFields = try #require(dropped.results.first?.returnedFields)
        #expect(dropped.successCount == 1)
        #expect(dropped.failureCount == 0)
        #expect(droppedFields["taskStatus"] == .string("dropped"))
        #expect(droppedFields["dropDate"] != .null)
        #expect(droppedFields["completionDate"] == .null)

        let restored = try await restoreTask(taskID, service: service, fields: fields)
        requiresRestore = false
        let restoredFields = try #require(restored.results.first?.returnedFields)
        #expect(restored.successCount == 1)
        #expect(restored.failureCount == 0)
        #expect(restoredFields["taskStatus"] == .string("active"))
        #expect(restoredFields["completionDate"] == .null)
    } catch {
        if requiresRestore {
            _ = try? await restoreTask(taskID, service: service, fields: fields)
        }
        throw error
    }
}

private func restoreTask(
    _ taskID: String,
    service: OmniFocusBridgeService,
    fields: [String]
) async throws -> MutationResponse {
    try await service.performMutation(try MutationRequest.editTasks(
        targetIDs: [taskID],
        operation: .setStatus,
        taskStatus: TaskStatusMutation(status: .active),
        verify: true,
        returnFields: fields
    ))
}
