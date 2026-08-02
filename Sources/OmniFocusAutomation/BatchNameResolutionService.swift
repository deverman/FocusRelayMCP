import Foundation
import OmniFocusCore

/// Batch name resolution for `list_projects` and `list_tags`.
///
/// One compact catalog fill is cached and matched locally for every requested
/// name, so N names cost one Bridge round trip on a cold cache and none while
/// the entry stays warm — replacing one scalar Bridge search per name.
extension OmniFocusBridgeService {
    /// Page size for a catalog fill. Large enough to take most databases in a
    /// single round trip; paging below covers the rest.
    static let catalogFillPageLimit = 1000
    /// Hard stop so a pathological database cannot page forever.
    static let catalogFillMaximumPages = 10

    /// Matching reads `name`, so the catalog fill must request it even when the
    /// caller only wants other fields back. Without this a request for
    /// `fields: ["id"]` fetches nameless items and matches nothing.
    static func catalogFetchFields(_ requested: [String]?) -> [String] {
        var fields = requested ?? []
        for required in ["id", "name"] where !fields.contains(required) {
            fields.append(required)
        }
        return fields
    }

    public func resolveProjectNames(
        searches: [String],
        matchLimitPerSearch: Int,
        statusFilter: String?,
        fields: [String]?
    ) async throws -> [NameSearchGroup<ProjectItem>] {
        let catalog = try await projectCatalog(
            statusFilter: statusFilter,
            fields: Self.catalogFetchFields(fields)
        )
        return BatchNameResolution.group(
            searches: searches,
            candidates: catalog,
            matchLimitPerSearch: matchLimitPerSearch,
            name: { $0.name }
        ).map { NameSearchGroup(search: $0.search, items: $0.items, truncated: $0.truncated) }
    }

    public func resolveTagNames(
        searches: [String],
        matchLimitPerSearch: Int,
        statusFilter: String?,
        fields: [String]?
    ) async throws -> [NameSearchGroup<TagItem>] {
        let catalog = try await tagCatalog(
            statusFilter: statusFilter,
            fields: Self.catalogFetchFields(fields)
        )
        return BatchNameResolution.group(
            searches: searches,
            candidates: catalog,
            matchLimitPerSearch: matchLimitPerSearch,
            name: { $0.name }
        ).map { NameSearchGroup(search: $0.search, items: $0.items, truncated: $0.truncated) }
    }

    private func projectCatalog(statusFilter: String?, fields: [String]?) async throws -> [ProjectItem] {
        let key = CacheKey.projects(
            page: PageRequest(limit: Self.catalogFillPageLimit),
            fields: fields,
            statusFilter: statusFilter,
            includeTaskCounts: false,
            search: nil,
            rootOnly: false
        )
        let client = self.client
        let runtime = self.runtime
        let page = try await cache.projects(key: key, ttl: cacheTTL) {
            var collected: [ProjectItem] = []
            var cursor: String?
            for _ in 0..<Self.catalogFillMaximumPages {
                let request = PageRequest(limit: Self.catalogFillPageLimit, cursor: cursor)
                let result = try await runtime.submit(category: .projectQuery) {
                    try client.listProjects(
                        page: request,
                        statusFilter: statusFilter,
                        includeTaskCounts: false,
                        search: nil,
                        rootOnly: false,
                        reviewDueBefore: nil,
                        reviewDueAfter: nil,
                        reviewPerspective: false,
                        completed: nil,
                        completedBefore: nil,
                        completedAfter: nil,
                        fields: fields
                    )
                }
                collected.append(contentsOf: result.items)
                guard let next = result.nextCursor else { break }
                cursor = next
            }
            return Page(items: collected, returnedCount: collected.count)
        }
        return page.items
    }

    private func tagCatalog(statusFilter: String?, fields: [String]?) async throws -> [TagItem] {
        let key = CacheKey.tags(
            page: PageRequest(limit: Self.catalogFillPageLimit),
            fields: fields,
            statusFilter: statusFilter,
            includeTaskCounts: false,
            search: nil
        )
        let client = self.client
        let runtime = self.runtime
        let page = try await cache.tags(key: key, ttl: cacheTTL) {
            var collected: [TagItem] = []
            var cursor: String?
            for _ in 0..<Self.catalogFillMaximumPages {
                let request = PageRequest(limit: Self.catalogFillPageLimit, cursor: cursor)
                let result = try await runtime.submit(category: .tagQuery) {
                    try client.listTags(
                        page: request,
                        statusFilter: statusFilter,
                        includeTaskCounts: false,
                        search: nil,
                        fields: fields
                    )
                }
                collected.append(contentsOf: result.items)
                guard let next = result.nextCursor else { break }
                cursor = next
            }
            return Page(items: collected, returnedCount: collected.count)
        }
        return page.items
    }
}
