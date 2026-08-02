import Foundation
import Testing
@testable import OmniFocusCore

@Suite("Batch name resolution: normalization")
struct BatchNameNormalizationTests {
    @Test func absentStaysAbsent() throws {
        #expect(try BatchNameResolution.normalize(nil, tool: "list_projects") == nil)
    }

    @Test func emptyArrayIsRejected() {
        #expect(throws: MutationValidationError.self) {
            _ = try BatchNameResolution.normalize([], tool: "list_projects")
        }
    }

    @Test func blankEntriesAreRejected() {
        for blank in ["", "   ", "\t\n"] {
            #expect(throws: MutationValidationError.self) {
                _ = try BatchNameResolution.normalize(["Work", blank], tool: "list_projects")
            }
        }
    }

    @Test func whitespaceIsTrimmed() throws {
        #expect(try BatchNameResolution.normalize(["  Work  "], tool: "list_projects") == ["Work"])
    }

    @Test func duplicatesCollapseCaseInsensitivelyKeepingFirstSpelling() throws {
        // Matching is case-insensitive, so "Work" and "work" would otherwise
        // produce two identical groups.
        let out = try BatchNameResolution.normalize(["Work", "work", "WORK", "Home"], tool: "list_projects")
        #expect(out == ["Work", "Home"])
    }

    @Test func duplicatesDifferingOnlyByWhitespaceAlsoCollapse() throws {
        #expect(try BatchNameResolution.normalize([" Work", "Work "], tool: "list_projects") == ["Work"])
    }

    @Test func maximumIsAccepted() throws {
        let names = (1...BatchNameResolution.maximumSearches).map { "name-\($0)" }
        #expect(try BatchNameResolution.normalize(names, tool: "list_projects")?.count == BatchNameResolution.maximumSearches)
    }

    @Test func exceedingMaximumIsRejected() {
        let names = (1...(BatchNameResolution.maximumSearches + 1)).map { "name-\($0)" }
        #expect(throws: MutationValidationError.self) {
            _ = try BatchNameResolution.normalize(names, tool: "list_projects")
        }
    }

    @Test func boundAppliesAfterDeduplication() throws {
        var names = (1...BatchNameResolution.maximumSearches).map { "name-\($0)" }
        names.append("NAME-1")
        #expect(try BatchNameResolution.normalize(names, tool: "list_projects")?.count == BatchNameResolution.maximumSearches)
    }

    @Test func errorsNameTheTool() {
        #expect {
            _ = try BatchNameResolution.normalize([], tool: "list_tags")
        } throws: { error in
            String(describing: error).contains("list_tags")
        }
    }
}

@Suite("Batch name resolution: limits and exclusivity")
struct BatchNameLimitTests {
    @Test func defaultMatchLimitApplies() throws {
        #expect(try BatchNameResolution.validateMatchLimit(nil, tool: "list_projects") == BatchNameResolution.defaultMatchLimit)
    }

    @Test func boundsAreEnforced() {
        for bad in [0, -1, BatchNameResolution.maximumMatchLimit + 1] {
            #expect(throws: MutationValidationError.self) {
                _ = try BatchNameResolution.validateMatchLimit(bad, tool: "list_projects")
            }
        }
    }

    @Test func edgeValuesAreAccepted() throws {
        #expect(try BatchNameResolution.validateMatchLimit(1, tool: "list_projects") == 1)
        #expect(try BatchNameResolution.validateMatchLimit(BatchNameResolution.maximumMatchLimit, tool: "list_projects") == BatchNameResolution.maximumMatchLimit)
    }

    @Test func scalarSearchConflicts() {
        #expect(throws: MutationValidationError.self) {
            try BatchNameResolution.validateExclusivity(tool: "list_projects", hasScalarSearch: true, hasCursor: false, includeTaskCounts: false)
        }
    }

    @Test func cursorConflicts() {
        #expect(throws: MutationValidationError.self) {
            try BatchNameResolution.validateExclusivity(tool: "list_projects", hasScalarSearch: false, hasCursor: true, includeTaskCounts: false)
        }
    }

    @Test func taskCountsConflict() {
        // Settled on #171: batch resolution stays a destination-selection
        // primitive; workload questions belong to #87.
        #expect(throws: MutationValidationError.self) {
            try BatchNameResolution.validateExclusivity(tool: "list_projects", hasScalarSearch: false, hasCursor: false, includeTaskCounts: true)
        }
    }

    @Test func cleanBatchRequestPasses() throws {
        try BatchNameResolution.validateExclusivity(tool: "list_projects", hasScalarSearch: false, hasCursor: false, includeTaskCounts: false)
    }
}

private struct Entry: Equatable {
    let name: String
}

@Suite("Batch name resolution: matching and grouping")
struct BatchNameMatchingTests {
    private let catalog = [
        Entry(name: "Work"), Entry(name: "Work Archive"), Entry(name: "Homework"),
        Entry(name: "Home"), Entry(name: "Errands")
    ]

    @Test func matchingIsLiteralAndCaseInsensitive() {
        #expect(BatchNameResolution.matches(name: "Work Archive", query: "work"))
        #expect(BatchNameResolution.matches(name: "work archive", query: "WORK"))
        #expect(!BatchNameResolution.matches(name: "Errands", query: "work"))
    }

    @Test func matchingIsSubstringNotPrefix() {
        // Mirrors the scalar bridge search, which uses indexOf.
        #expect(BatchNameResolution.matches(name: "Homework", query: "work"))
    }

    @Test func matchingIgnoresSurroundingWhitespaceInTheQuery() {
        #expect(BatchNameResolution.matches(name: "Work", query: "  work  "))
    }

    @Test func groupsFollowRequestOrderNotCatalogOrder() {
        let groups = BatchNameResolution.group(
            searches: ["home", "errands", "work"],
            candidates: catalog,
            matchLimitPerSearch: 10,
            name: { $0.name }
        )
        #expect(groups.map(\.search) == ["home", "errands", "work"])
    }

    @Test func unmatchedNameReturnsAnEmptyGroupRatherThanBeingDropped() {
        let groups = BatchNameResolution.group(
            searches: ["work", "nonexistent"],
            candidates: catalog,
            matchLimitPerSearch: 10,
            name: { $0.name }
        )
        #expect(groups.count == 2)
        #expect(groups[1].search == "nonexistent")
        #expect(groups[1].items.isEmpty)
        #expect(!groups[1].truncated)
    }

    @Test func broadNameIsMarkedTruncatedRatherThanSilentlyNarrowed() {
        let groups = BatchNameResolution.group(
            searches: ["work"],
            candidates: catalog,
            matchLimitPerSearch: 1,
            name: { $0.name }
        )
        #expect(groups[0].items.count == 1)
        #expect(groups[0].truncated, "more matches existed than the limit allowed")
    }

    @Test func exactLimitIsNotReportedAsTruncated() {
        // "Work", "Work Archive", "Homework" all contain "work".
        let groups = BatchNameResolution.group(
            searches: ["work"],
            candidates: catalog,
            matchLimitPerSearch: 3,
            name: { $0.name }
        )
        #expect(groups[0].items.count == 3)
        #expect(!groups[0].truncated, "matching exactly the limit is complete, not truncated")
    }

    @Test func overlappingNamesEachGetTheirOwnGroup() {
        let groups = BatchNameResolution.group(
            searches: ["work", "home"],
            candidates: catalog,
            matchLimitPerSearch: 10,
            name: { $0.name }
        )
        #expect(groups[0].items.contains(Entry(name: "Homework")))
        #expect(groups[1].items.contains(Entry(name: "Homework")),
                "an entry matching two requested names appears under both")
    }

    @Test func duplicateNamedEntriesAreAllReturned() {
        let dupes = [Entry(name: "Archive"), Entry(name: "Archive")]
        let groups = BatchNameResolution.group(
            searches: ["archive"],
            candidates: dupes,
            matchLimitPerSearch: 10,
            name: { $0.name }
        )
        #expect(groups[0].items.count == 2, "duplicates must stay visible so the caller can disambiguate by path")
    }
}
