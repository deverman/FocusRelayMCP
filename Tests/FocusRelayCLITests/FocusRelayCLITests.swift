import Foundation
import Testing
@testable import FocusRelayCLI

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
