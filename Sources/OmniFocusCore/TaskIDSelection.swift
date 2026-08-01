import Foundation

/// Bounded stable-ID selection for `list_tasks`.
///
/// Progressive expansion — read a compact page, then fetch notes for the few
/// ambiguous items — otherwise turns into one `get_task` call per item. This
/// keeps that expansion to a single bounded read without opening a
/// name-based or unbounded lookup surface.
public enum TaskIDSelection {
    /// Upper bound on IDs per request. Bounded so a selection can never
    /// degenerate into an unpaginated full-database read.
    public static let maximumCount = 20

    /// Trims, rejects blanks, and de-duplicates while preserving the order the
    /// caller asked for. Returns nil when no selection was supplied.
    public static func normalize(_ ids: [String]?) throws -> [String]? {
        guard let ids else { return nil }

        guard !ids.isEmpty else {
            throw MutationValidationError(
                "list_tasks.filter.ids must contain at least one task ID when supplied."
            )
        }

        var seen = Set<String>()
        var normalized: [String] = []
        for (index, id) in ids.enumerated() {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw MutationValidationError(
                    "list_tasks.filter.ids[\(index)] must be a non-empty task ID."
                )
            }
            if seen.insert(trimmed).inserted {
                normalized.append(trimmed)
            }
        }

        guard normalized.count <= maximumCount else {
            throw MutationValidationError(
                "list_tasks.filter.ids accepts at most \(maximumCount) distinct task IDs; received \(normalized.count)."
            )
        }

        return normalized
    }

    /// Paging rules for a bounded ID selection: the response is the whole
    /// answer, so a cursor is meaningless and a limit must not be able to
    /// truncate it.
    public static func validatePaging(idCount: Int, limit: Int, cursor: String?) throws {
        guard cursor == nil else {
            throw MutationValidationError(
                "list_tasks.filter.ids cannot be combined with page.cursor. "
                    + "A bounded ID selection returns one complete response."
            )
        }
        guard limit >= idCount else {
            throw MutationValidationError(
                "page.limit (\(limit)) must be at least the number of requested task IDs (\(idCount))."
            )
        }
    }

    /// Orders resolved items by the order the caller requested, and reports
    /// which IDs produced nothing. An ID can be absent because it does not
    /// exist or because the supplied scope excluded it; the two are not
    /// distinguished, because guessing why would require reading outside the
    /// caller's own scope.
    public static func order<Item>(
        _ items: [Item],
        by requestedIDs: [String],
        id: (Item) -> String
    ) -> (ordered: [Item], unresolvedIDs: [String]) {
        var byID: [String: Item] = [:]
        for item in items where byID[id(item)] == nil {
            byID[id(item)] = item
        }
        var ordered: [Item] = []
        var unresolved: [String] = []
        for requested in requestedIDs {
            if let item = byID[requested] {
                ordered.append(item)
            } else {
                unresolved.append(requested)
            }
        }
        return (ordered, unresolved)
    }
}
