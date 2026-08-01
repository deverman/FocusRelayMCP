import Foundation
import Testing
@testable import OmniFocusCore

@Suite("Bounded task-ID selection: normalization")
struct TaskIDSelectionNormalizationTests {
    @Test func absentSelectionStaysAbsent() throws {
        #expect(try TaskIDSelection.normalize(nil) == nil)
    }

    @Test func emptyArrayIsRejected() {
        #expect(throws: MutationValidationError.self) {
            _ = try TaskIDSelection.normalize([])
        }
    }

    @Test func blankAndWhitespaceOnlyIDsAreRejected() {
        for invalid in ["", "   ", "\t", "\n"] {
            #expect(throws: MutationValidationError.self, "\(invalid.debugDescription) must be rejected") {
                _ = try TaskIDSelection.normalize(["valid-id", invalid])
            }
        }
    }

    @Test func surroundingWhitespaceIsTrimmed() throws {
        #expect(try TaskIDSelection.normalize(["  abc  ", "\tdef\n"]) == ["abc", "def"])
    }

    @Test func duplicatesCollapseAndKeepFirstRequestedOrder() throws {
        let normalized = try TaskIDSelection.normalize(["c", "a", "c", "b", "a"])
        #expect(normalized == ["c", "a", "b"])
    }

    @Test func duplicatesThatDifferOnlyByWhitespaceAlsoCollapse() throws {
        #expect(try TaskIDSelection.normalize(["a", " a ", "b"]) == ["a", "b"])
    }

    @Test func maximumDistinctCountIsAccepted() throws {
        let ids = (1...TaskIDSelection.maximumCount).map { "id-\($0)" }
        #expect(try TaskIDSelection.normalize(ids)?.count == TaskIDSelection.maximumCount)
    }

    @Test func exceedingMaximumDistinctCountIsRejected() {
        let ids = (1...(TaskIDSelection.maximumCount + 1)).map { "id-\($0)" }
        #expect(throws: MutationValidationError.self) {
            _ = try TaskIDSelection.normalize(ids)
        }
    }

    @Test func duplicatesAreCountedAfterCollapsing() throws {
        // 21 entries, 20 distinct: the bound applies to distinct IDs.
        var ids = (1...TaskIDSelection.maximumCount).map { "id-\($0)" }
        ids.append("id-1")
        #expect(try TaskIDSelection.normalize(ids)?.count == TaskIDSelection.maximumCount)
    }
}

@Suite("Bounded task-ID selection: paging rules")
struct TaskIDSelectionPagingTests {
    @Test func cursorIsRejected() {
        #expect(throws: MutationValidationError.self) {
            try TaskIDSelection.validatePaging(idCount: 3, limit: 50, cursor: "eyJvZmZzZXQiOiIzIn0")
        }
    }

    @Test func limitBelowRequestedCountIsRejected() {
        #expect(throws: MutationValidationError.self) {
            try TaskIDSelection.validatePaging(idCount: 5, limit: 4, cursor: nil)
        }
    }

    @Test func limitEqualToRequestedCountIsAccepted() throws {
        try TaskIDSelection.validatePaging(idCount: 5, limit: 5, cursor: nil)
    }

    @Test func generousLimitIsAccepted() throws {
        try TaskIDSelection.validatePaging(idCount: 2, limit: 50, cursor: nil)
    }
}

private struct StubItem: Equatable {
    let id: String
}

@Suite("Bounded task-ID selection: ordering and unresolved IDs")
struct TaskIDSelectionOrderingTests {
    @Test func resultsFollowRequestedOrderNotBridgeOrder() {
        let bridgeOrder = [StubItem(id: "b"), StubItem(id: "c"), StubItem(id: "a")]
        let (ordered, unresolved) = TaskIDSelection.order(bridgeOrder, by: ["a", "b", "c"]) { $0.id }
        #expect(ordered.map(\.id) == ["a", "b", "c"])
        #expect(unresolved.isEmpty)
    }

    @Test func missingIDsAreReportedAndNeverSubstituted() {
        let resolved = [StubItem(id: "a"), StubItem(id: "c")]
        let (ordered, unresolved) = TaskIDSelection.order(resolved, by: ["a", "missing", "c"]) { $0.id }
        #expect(ordered.map(\.id) == ["a", "c"], "an unresolved ID must not be replaced by another task")
        #expect(unresolved == ["missing"])
    }

    @Test func scopedOutIDsSurfaceAsUnresolved() {
        // The bridge applies other filters as an intersection, so a task
        // excluded by scope simply does not come back.
        let (ordered, unresolved) = TaskIDSelection.order([StubItem(id: "in-scope")], by: ["in-scope", "out-of-scope"]) { $0.id }
        #expect(ordered.map(\.id) == ["in-scope"])
        #expect(unresolved == ["out-of-scope"])
    }

    @Test func everyIDUnresolvedYieldsNoItemsRatherThanAFallbackPage() {
        let (ordered, unresolved) = TaskIDSelection.order([StubItem]([]), by: ["x", "y"]) { $0.id }
        #expect(ordered.isEmpty)
        #expect(unresolved == ["x", "y"])
    }

    @Test func unresolvedListPreservesRequestedOrder() {
        let (_, unresolved) = TaskIDSelection.order([StubItem(id: "b")], by: ["z", "b", "a"]) { $0.id }
        #expect(unresolved == ["z", "a"])
    }

    @Test func duplicateBridgeItemsDoNotDuplicateOutput() {
        let withDuplicate = [StubItem(id: "a"), StubItem(id: "a")]
        let (ordered, _) = TaskIDSelection.order(withDuplicate, by: ["a"]) { $0.id }
        #expect(ordered.count == 1)
    }
}
