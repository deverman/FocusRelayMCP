import Foundation
import Testing
@testable import FocusRelayCLI
import OmniFocusCore

@Test
func fieldListParsesCommaSeparatedValues() {
    #expect(FieldList.parse(nil).isEmpty)
    #expect(FieldList.parse("").isEmpty)
    #expect(FieldList.parse("id,name, completionDate") == ["id", "name", "completionDate"])
}

@Test
func iso8601DateParserAcceptsValidDates() throws {
    let date = try ISO8601DateParser.parse("2026-02-04T12:00:00Z", argumentName: "--due-before")
    #expect(date.timeIntervalSince1970 > 0)
}

@Test
func iso8601DateParserRejectsInvalidDates() {
    var didThrow = false
    do {
        _ = try ISO8601DateParser.parse("not-a-date", argumentName: "--due-before")
    } catch {
        didThrow = true
    }
    #expect(didThrow)
}

@Test
func taskPatchOptionsBuildSharedTaskPatch() throws {
    let options = try TaskPatchOptions.parse([
        "--name", "Renamed",
        "--note-append", "\nFollow up",
        "--flagged", "true",
        "--estimated-minutes", "30",
        "--due-date", "2026-04-18T12:00:00Z",
        "--tag-add", "tag-1,tag-2"
    ])

    let patch = try options.makeTaskPatchMutation()

    #expect(patch.name == "Renamed")
    #expect(patch.noteAppend == "\nFollow up")
    #expect(patch.flagged == true)
    #expect(patch.estimatedMinutes == 30)
    #expect(patch.dueDate != nil)
    #expect(patch.tags?.add == ["tag-1", "tag-2"])
}

@Test
func taskPatchOptionsRejectConflictingTagModes() {
    let options = try! TaskPatchOptions.parse([
        "--tag-add", "tag-1",
        "--tag-set", "tag-2"
    ])

    #expect(throws: MutationValidationError.self) {
        _ = try options.makeTaskPatchMutation()
    }
}

@Test
func setTasksCompletionParsesCompletedState() throws {
    let command = try SetTasksCompletion.parse([
        "task-1",
        "task-2",
        "--state", "completed",
        "--verify",
        "--return-fields", "id,name,completed"
    ])

    #expect(command.ids == ["task-1", "task-2"])
    #expect(command.state == .completed)
    #expect(command.verify)
    #expect(command.returnFields == "id,name,completed")
}

@Test
func moveTasksParsesProjectDestination() throws {
    let command = try MoveTasks.parse([
        "task-1",
        "--destination-kind", "project",
        "--destination-id", "project-1",
        "--position", "beginning",
        "--verify",
        "--return-fields", "id,name,projectID"
    ])

    #expect(command.ids == ["task-1"])
    #expect(command.destinationKind == .project)
    #expect(command.destinationID == "project-1")
    #expect(command.position == "beginning")
    #expect(command.verify)
}

@Test
func benchmarkGateTaskCountScenariosCoverBoundaryAndFlaggedCases() {
    let contractNames = gateTaskCountContractScenarios().map(\.name)
    let parityNames = gateTaskCountParityScenarios().map(\.name)

    #expect(contractNames.contains("completed_after_anchor"))
    #expect(parityNames.contains("flagged_only"))
    #expect(parityNames.contains("completed_after_anchor"))
}

@Test
func benchmarkGateListTaskScenariosCoverRegressionShapes() {
    let baseNames = gateListTaskParityScenarios(projectID: nil).map(\.name)
    let projectNames = gateListTaskParityScenarios(projectID: "project-123").map(\.name)

    #expect(baseNames.contains("flagged_only"))
    #expect(baseNames.contains("flagged_only_no_total"))
    #expect(baseNames.contains("completed_after_anchor"))
    #expect(!baseNames.contains("project_scoped_simple"))
    #expect(projectNames.contains("project_scoped_simple"))
}

@Test
func benchmarkGateProjectCountScenariosCoverCompletedWindowParity() {
    let names = gateProjectCountParityScenarios().map(\.name)

    #expect(names.contains("project_view_remaining"))
    #expect(names.contains("project_view_active"))
    #expect(names.contains("completed_after_anchor"))
}
