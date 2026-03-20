import Testing
import Foundation
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

@Test
func bridgeListTagsUsesDocumentedCountDerivation() throws {
    let source = try String(contentsOfFile: "Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js", encoding: .utf8)

    #expect(source.contains("function collectAllTags()"))
    #expect(source.contains("function collectTasksForTag(tag)"))
    #expect(source.contains("const rootTags = safe(() => tags) || [];"))
    #expect(source.contains("let tagItems = collectAllTags();"))
    #expect(!source.contains("let tags = collectAllTags();"))
    #expect(source.contains("safe(() => tag.flattenedTasks)"))
    #expect(source.contains("isAvailableStatusValue(status)"))
}

@Test
func listProjectsScriptRejectsUndefinedHealthFields() async throws {
    let (service, box) = makeAutomationServiceForScriptCapture()

    _ = try await service.listProjects(
        page: PageRequest(limit: 10),
        statusFilter: "active",
        includeTaskCounts: true,
        reviewDueBefore: nil,
        reviewDueAfter: nil,
        reviewPerspective: false,
        completed: nil,
        completedBefore: nil,
        completedAfter: nil,
        fields: ["id", "name", "nextTask", "containsSingletonActions", "isStalled"]
    )

    let source = try #require(box.lastSource)
    #expect(source.contains("function requireDefinedProjectField(label, fn)"))
    #expect(source.contains("Undefined Omni Automation project field"))
    #expect(source.contains("function requireBooleanProjectField(label, fn)"))
    #expect(source.contains("requireBooleanProjectField"))
}

@Test
func listProjectsScriptKeepsBestEffortProjectFieldsExplicitWhenFieldsOmitted() async throws {
    let (service, box) = makeAutomationServiceForScriptCapture()

    _ = try await service.listProjects(
        page: PageRequest(limit: 10),
        statusFilter: "active",
        includeTaskCounts: false,
        reviewDueBefore: nil,
        reviewDueAfter: nil,
        reviewPerspective: false,
        completed: nil,
        completedBefore: nil,
        completedAfter: nil,
        fields: nil
    )

    let source = try #require(box.lastSource)
    #expect(source.contains("function hasExplicitField(name)"))
    #expect(source.contains("includeTaskCounts || hasExplicitField"))
    #expect(source.contains("hasExplicitField(\\\"containsSingletonActions\\\")"))
    #expect(!source.contains("includeTaskCounts || hasField"))
}

@Test
func listProjectsScriptKeepsCompletedBeforeExclusive() async throws {
    let (service, box) = makeAutomationServiceForScriptCapture()

    _ = try await service.listProjects(
        page: PageRequest(limit: 10),
        statusFilter: "done",
        includeTaskCounts: false,
        reviewDueBefore: nil,
        reviewDueAfter: nil,
        reviewPerspective: false,
        completed: true,
        completedBefore: Date(timeIntervalSince1970: 1_700_000_000),
        completedAfter: nil,
        fields: ["id", "name", "completionDate"]
    )

    let source = try #require(box.lastSource)
    #expect(source.contains("if (completedBefore && completionDate >= completedBefore.getTime()) { return false; }"))
    #expect(!source.contains("if (completedBefore && completionDate > completedBefore.getTime()) { return false; }"))
}
