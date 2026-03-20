import Testing
@testable import OmniFocusAutomation
@testable import OmniFocusCore

private final class ScriptSourceCaptureBox: @unchecked Sendable {
    var lastSource: String?
}

private func makeAutomationServiceForScriptCapture(
    output: String = #"{"items":[],"nextCursor":null,"returnedCount":0,"totalCount":0}"#
) -> (OmniAutomationService, ScriptSourceCaptureBox) {
    let box = ScriptSourceCaptureBox()
    let runner = ScriptRunner(
        osaKitExecutor: { source in
            box.lastSource = source
            return output
        },
        osaScriptExecutor: { _ in
            Issue.record("Unexpected osascript fallback in script capture test")
            return output
        }
    )
    return (OmniAutomationService(runner: runner), box)
}

@Test
func listTagsScriptTraversesNestedTagsFromRootFallback() async throws {
    let (service, box) = makeAutomationServiceForScriptCapture()

    _ = try await service.listTags(page: PageRequest(limit: 10), statusFilter: "active", includeTaskCounts: false)

    let source = try #require(box.lastSource)
    #expect(source.contains("function pushUnique(result, seen, item)"))
    #expect(source.contains("var roots = toArray(safe(function() { return tags; }) || safe(function() { return tags(); }));"))
    #expect(source.contains("pushUnique(result, seen, tag);"))
}

@Test
func listTagsScriptDerivesCountsFromTaskStatus() async throws {
    let (service, box) = makeAutomationServiceForScriptCapture()

    _ = try await service.listTags(page: PageRequest(limit: 10), statusFilter: "active", includeTaskCounts: true)

    let source = try #require(box.lastSource)
    #expect(source.contains("function tasksForTag(tag)"))
    #expect(source.contains("currentTag.flattenedTasks"))
    #expect(source.contains("currentTag.tasks"))
    #expect(source.contains("task.taskStatus"))
    #expect(source.contains("isActionableTaskStatus(statusName)"))
}
