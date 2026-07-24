import Foundation
import Testing
@testable import FocusRelayCLI
import FocusRelayVersion
import OmniFocusCore

@Test
func cliVersionFlagReportsEmbeddedBuildVersion() throws {
    #expect(FocusRelayCLI.configuration.version == FocusRelayBuildVersion.current)

    let coreVersion = FocusRelayBuildVersion.current.split(separator: "-", maxSplits: 1)[0]
    let numericComponents = coreVersion.split(separator: ".")
    #expect(numericComponents.count == 3)
    #expect(numericComponents.allSatisfy { Int($0) != nil })

    do {
        _ = try FocusRelayCLI.parseAsRoot(["--version"])
        Issue.record("Expected --version to exit after printing the embedded version")
    } catch {
        #expect(FocusRelayCLI.fullMessage(for: error) == FocusRelayBuildVersion.current)
    }
}

@Test
func fieldListParsesCommaSeparatedValues() {
    #expect(FieldList.parse(nil).isEmpty)
    #expect(FieldList.parse("").isEmpty)
    #expect(FieldList.parse("id,name, completionDate") == ["id", "name", "completionDate"])
}

@Test
func listProjectsParsesProjectNameSearch() throws {
    let command = try ListProjects.parse([
        "--search", "drop test",
        "--status", "all",
        "--fields", "id,name,status"
    ])

    #expect(command.search == "drop test")
    #expect(command.statusFilter == "all")
    #expect(command.fields == "id,name,status")
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
func editTasksParsesAndBuildsCompletionRequest() throws {
    let command = try EditTasks.parse([
        "task-1",
        "task-2",
        "--operation", "set_completion",
        "--state", "completed",
        "--verify",
        "--return-fields", "id,name,completed"
    ])

    #expect(command.ids == ["task-1", "task-2"])
    #expect(command.state == .completed)
    #expect(command.verify)
    #expect(command.returnFields == "id,name,completed")
    #expect(try command.makeRequest().operation.kind == .setTasksCompletion)
}

@Test
func editTasksParsesAndBuildsStatusRequest() throws {
    let command = try EditTasks.parse([
        "task-1",
        "--operation", "set_status",
        "--status", "dropped",
        "--recurrence-scope", "occurrence",
        "--verify",
        "--return-fields", "id,name,taskStatus,dropDate,completionDate"
    ])

    let request = try command.makeRequest()
    #expect(request.operation.kind == .setTasksStatus)
    #expect(request.operation.taskStatus == TaskStatusMutation(status: .dropped, recurrenceScope: .occurrence))
    #expect(command.verify)
}

@Test
func editTasksRejectsRecurrenceScopeWithoutStatus() throws {
    let command = try EditTasks.parse([
        "task-1",
        "--operation", "set_completion",
        "--state", "completed",
        "--recurrence-scope", "series"
    ])

    #expect(throws: Error.self) {
        _ = try command.makeRequest()
    }
}

@Test
func editTasksParsesAndBuildsMoveRequest() throws {
    let command = try EditTasks.parse([
        "task-1",
        "--operation", "move",
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
    #expect(try command.makeRequest().operation.kind == .moveTasks)
}

@Test
func projectPatchOptionsBuildSharedProjectPatch() throws {
    let options = try ProjectPatchOptions.parse([
        "--name", "Renamed Project",
        "--note-append", "\nWeekly review",
        "--flagged", "true",
        "--due-date", "2026-04-20T12:00:00Z",
        "--sequential", "true",
        "--review-steps", "2",
        "--review-unit", "weeks"
    ])

    let patch = try options.makeProjectPatchMutation()

    #expect(patch.name == "Renamed Project")
    #expect(patch.noteAppend == "\nWeekly review")
    #expect(patch.flagged == true)
    #expect(patch.dueDate != nil)
    #expect(patch.sequential == true)
    #expect(patch.reviewInterval?.steps == 2)
    #expect(patch.reviewInterval?.unit == "weeks")
}

@Test
func editProjectsParsesReviewedNowUpdate() throws {
    let command = try EditProjects.parse([
        "project-1", "project-2",
        "--operation", "update",
        "--reviewed-now",
        "--preview-only",
        "--verify",
        "--return-fields", "id,name,status,lastReviewDate,nextReviewDate,reviewInterval"
    ])

    let request = try command.makeRequest()
    #expect(request.operation.kind == .updateProjects)
    #expect(request.operation.projectPatch?.reviewedNow == true)
    #expect(request.previewOnly)
    #expect(request.verify)
}

@Test
func editProjectsRejectsReviewedNowWithOtherPatchFields() throws {
    let command = try EditProjects.parse([
        "project-1",
        "--operation", "update",
        "--reviewed-now",
        "--flagged", "true"
    ])

    #expect(throws: MutationValidationError.self) {
        _ = try command.makeRequest()
    }
}

@Test
func editProjectsParsesAndBuildsStatusRequest() throws {
    let command = try EditProjects.parse([
        "project-1",
        "--operation", "set_status",
        "--status", "on_hold",
        "--verify",
        "--return-fields", "id,name,status"
    ])

    #expect(command.ids == ["project-1"])
    #expect(command.status == .onHold)
    #expect(command.verify)
    #expect(try command.makeRequest().operation.kind == .setProjectsStatus)
}

@Test
func editProjectsParsesAndBuildsFolderMoveRequest() throws {
    let command = try EditProjects.parse([
        "project-1",
        "project-2",
        "--operation", "move",
        "--destination-kind", "folder",
        "--destination-id", "folder-1",
        "--position", "beginning",
        "--verify",
        "--return-fields", "id,name,status"
    ])

    #expect(command.ids == ["project-1", "project-2"])
    #expect(command.destinationKind == .folder)
    #expect(command.destinationID == "folder-1")
    #expect(command.position == "beginning")
    #expect(command.verify)
    #expect(command.returnFields == "id,name,status")
    #expect(try command.makeRequest().operation.kind == .moveProjects)
}

@Test
func editProjectsAllowsRootLibraryDestination() throws {
    let command = try EditProjects.parse([
        "project-1",
        "--operation", "move",
        "--destination-kind", "folder",
        "--position", "ending"
    ])

    #expect(command.ids == ["project-1"])
    #expect(command.destinationKind == .folder)
    #expect(command.destinationID == nil)
    #expect(command.position == "ending")
}

@Test
func listFoldersParsesFieldsAndPagination() throws {
    let command = try ListFolders.parse([
        "--fields", "id,name,parentID",
        "--limit", "5",
        "--cursor", "10"
    ])

    #expect(command.fields == "id,name,parentID")
    #expect(command.page.limit == 5)
    #expect(command.page.cursor == "10")
}

@Test
func editProjectsParsesAndBuildsCompletionRequest() throws {
    let command = try EditProjects.parse([
        "project-1",
        "project-2",
        "--operation", "set_completion",
        "--state", "completed",
        "--verify",
        "--return-fields", "id,name,status,completionDate"
    ])

    #expect(command.ids == ["project-1", "project-2"])
    #expect(command.state == .completed)
    #expect(command.verify)
    #expect(command.returnFields == "id,name,status,completionDate")
    #expect(try command.makeRequest().operation.kind == .setProjectsCompletion)
}

@Test
func cliExposesOnlyConsolidatedEditCommands() {
    let names = Set(FocusRelayCLI.configuration.subcommands.map { $0.configuration.commandName })
    #expect(names.contains("edit-tasks"))
    #expect(names.contains("edit-projects"))
    #expect(names.isDisjoint(with: [
        "update-tasks", "set-tasks-completion", "move-tasks", "update-projects",
        "set-projects-status", "set-projects-completion", "move-projects"
    ]))
}

@Test
func cliEditCommandsRejectContradictoryOperationOptions() throws {
    let command = try EditTasks.parse([
        "task-1",
        "--operation", "set_completion",
        "--state", "completed",
        "--flagged", "true"
    ])
    #expect(throws: MutationValidationError.self) {
        _ = try command.makeRequest()
    }
}

@Test
func benchmarkGateTaskCountScenariosCoverBoundaryAndFlaggedCases() {
    let contractNames = gateTaskCountContractScenarios().map(\.name)

    #expect(contractNames.contains("completed_after_anchor"))
    #expect(contractNames.contains("flagged_only"))
    #expect(contractNames.contains("search_no_match"))
    #expect(gateTaskCountContractScenarios().first { $0.name == "search_no_match" }?.expectedTotal == 0)
}

@Test
func benchmarkGateDefaultsToProductionContractsOnly() throws {
    let command = try BenchmarkGateCheck.parse([])

    #expect(command.tool == .all)
}

@Test
func benchmarkGateParsesToolScope() throws {
    let command = try BenchmarkGateCheck.parse(["--tool", "project-counts"])

    #expect(command.tool == .projectCounts)
}

@Test
func listTaskBenchmarkRotatesEveryScenario() {
    #expect((0..<8).map { benchmarkScenarioIndex(callIndex: $0, scenarioCount: 4) } == [0, 1, 2, 3, 0, 1, 2, 3])
    #expect((0..<7).map { benchmarkScenarioIndex(callIndex: $0, scenarioCount: 3) } == [0, 1, 2, 0, 1, 2, 0])
}

@Test
func listTaskBenchmarkReportsMissingMeasuredCoverage() {
    var success = BenchmarkStats()
    success.success = 1
    var failure = BenchmarkStats()
    failure.errors = 1
    let complete = [
        "first": success,
        "second": failure
    ]

    #expect(listTaskMissingMeasuredCoverage(scenarios: ["first", "second"], stats: complete).isEmpty)

    let incomplete = ["first": success]
    #expect(listTaskMissingMeasuredCoverage(scenarios: ["first", "second"], stats: incomplete) == [
        "second:plugin"
    ])
}

@Test
func benchmarkArgumentsUseOneValidationContract() {
    #expect(throws: (any Error).self) {
        try validateBenchmarkArguments(durationHours: 0, warmupCalls: 0, intervalMS: 0, cooldownMS: 0)
    }
    #expect(throws: (any Error).self) {
        try validateBenchmarkArguments(durationHours: 1, warmupCalls: -1, intervalMS: 0, cooldownMS: 0)
    }
    #expect(throws: (any Error).self) {
        try validateBenchmarkArguments(durationHours: 1, warmupCalls: 0, intervalMS: 0, cooldownMS: 0, memoryIntervalSeconds: 0)
    }
}

@Test
func countBenchmarkArtifactKeepsHistoricalKeys() throws {
    let event = CountBenchmarkEvent(
        timestamp: "2026-07-18T00:00:00.000Z",
        phase: "measured",
        callIndex: 1,
        transport: benchmarkTransport,
        scenario: "default",
        latencyMs: 12.5,
        ok: true,
        timeout: false,
        error: nil,
        counts: TaskCounts(total: 1, completed: 0, available: 1, flagged: 0)
    )
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])

    #expect(Set(object.keys) == [
        "timestamp", "phase", "callIndex", "transport", "scenario", "latencyMs",
        "ok", "timeout", "counts"
    ])
    #expect(object["transport"] as? String == "plugin")
}

@Test
func listBenchmarkArtifactKeepsHistoricalKeys() throws {
    let event = ListTaskEvent(
        timestamp: "2026-07-18T00:00:00.000Z",
        phase: "measured",
        callIndex: 1,
        transport: benchmarkTransport,
        scenario: "default",
        latencyMs: 12.5,
        ok: true,
        timeout: false,
        error: nil,
        returnedCount: 1,
        totalCount: 1,
        nextCursor: nil,
        firstItemID: "first",
        lastItemID: "first"
    )
    let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(event)) as? [String: Any])

    #expect(Set(object.keys) == [
        "timestamp", "phase", "callIndex", "transport", "scenario", "latencyMs",
        "ok", "timeout", "returnedCount", "totalCount", "firstItemID", "lastItemID"
    ])
    #expect(object["transport"] as? String == "plugin")
}
