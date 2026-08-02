import Foundation
import OmniFocusCore

/// Batch name resolution for `list_projects` and `list_tags`.
///
/// Matching runs inside OmniFocus, in the bridge plug-in, using the same
/// normaliser and matcher the scalar `search` already uses. That keeps batch
/// and scalar results identical by construction, needs no catalog copy in this
/// process, and cannot go stale or silently truncate on a large database —
/// each call reads live data and returns only the matches.
extension OmniFocusBridgeService {
    public func resolveProjectNames(
        searches: [String],
        matchLimitPerSearch: Int,
        statusFilter: String?,
        fields: [String]?
    ) async throws -> [NameSearchGroup<ProjectItem>] {
        try await runtime.submit(category: .projectQuery) {
            try self.client.resolveProjectNames(
                searches: searches,
                matchLimitPerSearch: matchLimitPerSearch,
                statusFilter: statusFilter,
                fields: fields
            )
        }
    }

    public func resolveTagNames(
        searches: [String],
        matchLimitPerSearch: Int,
        statusFilter: String?,
        fields: [String]?
    ) async throws -> [NameSearchGroup<TagItem>] {
        try await runtime.submit(category: .tagQuery) {
            try self.client.resolveTagNames(
                searches: searches,
                matchLimitPerSearch: matchLimitPerSearch,
                statusFilter: statusFilter,
                fields: fields
            )
        }
    }
}
