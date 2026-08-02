import Foundation

/// Bounded multi-name resolution for `list_projects` and `list_tags`.
///
/// Choosing a destination during inbox processing otherwise costs one scalar
/// catalog search per candidate name — one observed inbox-zero run spent 46
/// project searches and 22 tag searches. This resolves a bounded set of names
/// in one call without exposing the whole catalog to the model.
public enum BatchNameResolution {
    /// Upper bound on names per request, so a batch can never become an
    /// unpaginated catalog dump.
    public static let maximumSearches = 20
    public static let defaultMatchLimit = 10
    public static let maximumMatchLimit = 25

    /// Trims, rejects blanks, and de-duplicates **case-insensitively** while
    /// preserving the order first requested. Case-insensitive because matching
    /// is case-insensitive: "Work" and "work" would otherwise produce two
    /// identical result groups.
    public static func normalize(_ searches: [String]?, tool: String) throws -> [String]? {
        guard let searches else { return nil }

        guard !searches.isEmpty else {
            throw MutationValidationError("\(tool).searches must contain at least one name when supplied.")
        }

        var seen = Set<String>()
        var normalized: [String] = []
        for (index, raw) in searches.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw MutationValidationError("\(tool).searches[\(index)] must be a non-empty name.")
            }
            if seen.insert(matchKey(trimmed)).inserted {
                normalized.append(trimmed)
            }
        }

        guard normalized.count <= maximumSearches else {
            throw MutationValidationError(
                "\(tool).searches accepts at most \(maximumSearches) distinct names; received \(normalized.count)."
            )
        }
        return normalized
    }

    public static func validateMatchLimit(_ limit: Int?, tool: String) throws -> Int {
        guard let limit else { return defaultMatchLimit }
        guard limit >= 1, limit <= maximumMatchLimit else {
            throw MutationValidationError(
                "\(tool).matchLimitPerSearch must be between 1 and \(maximumMatchLimit); received \(limit)."
            )
        }
        return limit
    }

    /// Batch resolution answers "which catalog entries match these names".
    /// Scalar `search`, a `cursor`, and task counts each belong to a different
    /// question, so combining them is rejected rather than silently ignored.
    public static func validateExclusivity(
        tool: String,
        hasScalarSearch: Bool,
        hasCursor: Bool,
        includeTaskCounts: Bool
    ) throws {
        if hasScalarSearch {
            throw MutationValidationError(
                "\(tool).searches cannot be combined with \(tool).search. Use one or the other."
            )
        }
        if hasCursor {
            throw MutationValidationError(
                "\(tool).searches cannot be combined with page.cursor. "
                    + "A bounded batch resolution returns one complete response per requested name."
            )
        }
        if includeTaskCounts {
            throw MutationValidationError(
                "\(tool).searches cannot be combined with includeTaskCounts. "
                    + "Batch resolution selects a destination; use a scalar query when workload matters."
            )
        }
    }

    /// Literal, case-insensitive substring match — identical in intent to the
    /// scalar `search` the bridge already applies (`trim`, lower-case, then
    /// `contains`), so batch and scalar results agree for the same name.
    public static func matches(name: String, query: String) -> Bool {
        matchKey(name).contains(matchKey(query))
    }

    private static func matchKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Groups candidates by the requested name, preserving request order and
    /// the catalog's own ordering within each group. A name with no match
    /// returns an empty group rather than being omitted, so the caller can
    /// tell "nothing matched" from "not asked".
    public static func group<Item>(
        searches: [String],
        candidates: [Item],
        matchLimitPerSearch: Int,
        name: (Item) -> String
    ) -> [(search: String, items: [Item], truncated: Bool)] {
        searches.map { search in
            var matched: [Item] = []
            var overflow = false
            for candidate in candidates where matches(name: name(candidate), query: search) {
                if matched.count == matchLimitPerSearch {
                    // Keep scanning only long enough to know more exist.
                    overflow = true
                    break
                }
                matched.append(candidate)
            }
            return (search: search, items: matched, truncated: overflow)
        }
    }
}
