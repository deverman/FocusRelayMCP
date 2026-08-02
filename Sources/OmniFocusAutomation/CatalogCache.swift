import Foundation
import OmniFocusCore

/// Cache identity for a catalog page.
///
/// The filter contributes a fingerprint of its own encoding rather than a
/// hand-listed set of fields, so adding a filter field changes the key
/// automatically. Page and field selection are separate because they are not
/// part of the filter.
struct CacheKey: Hashable {
    let limit: Int
    let cursor: String?
    let fieldsKey: String
    let filterFingerprint: String

    init(page: PageRequest, fields: [String]?, filterFingerprint: String) {
        self.limit = page.limit
        self.cursor = page.cursor
        self.fieldsKey = (fields ?? []).joined(separator: ",")
        self.filterFingerprint = filterFingerprint
    }

    static func projects(page: PageRequest, fields: [String]?, filter: ProjectFilter) throws -> CacheKey {
        CacheKey(page: page, fields: fields, filterFingerprint: try FilterCacheIdentity.fingerprint(filter))
    }

    static func tags(page: PageRequest, fields: [String]?, filter: TagFilter) throws -> CacheKey {
        CacheKey(page: page, fields: fields, filterFingerprint: try FilterCacheIdentity.fingerprint(filter))
    }
}

struct CacheEntry<T> {
    let value: T
    let expiresAt: Date
}

actor CatalogCache {
    private var projects: [CacheKey: CacheEntry<Page<ProjectItem>>] = [:]
    private var tags: [CacheKey: CacheEntry<Page<TagItem>>] = [:]
    private var projectFills: [CacheKey: Task<Page<ProjectItem>, Error>] = [:]
    private var tagFills: [CacheKey: Task<Page<TagItem>, Error>] = [:]

    /// Returns the cached page, or performs `fill` exactly once for concurrent
    /// callers asking for the same key. Without this, several requests arriving
    /// on a cold cache each drive their own catalog fetch through the Bridge
    /// lane — a stampede that is slow precisely when the cache would help most.
    func projects(
        key: CacheKey,
        ttl: TimeInterval,
        fill: @escaping @Sendable () async throws -> Page<ProjectItem>
    ) async throws -> Page<ProjectItem> {
        purgeExpired()
        if let cached = projects[key]?.value { return cached }
        if let inFlight = projectFills[key] { return try await inFlight.value }

        let task = Task { try await fill() }
        projectFills[key] = task
        defer { projectFills[key] = nil }
        let page = try await task.value
        projects[key] = CacheEntry(value: page, expiresAt: Date().addingTimeInterval(ttl))
        return page
    }

    func tags(
        key: CacheKey,
        ttl: TimeInterval,
        fill: @escaping @Sendable () async throws -> Page<TagItem>
    ) async throws -> Page<TagItem> {
        purgeExpired()
        if let cached = tags[key]?.value { return cached }
        if let inFlight = tagFills[key] { return try await inFlight.value }

        let task = Task { try await fill() }
        tagFills[key] = task
        defer { tagFills[key] = nil }
        let page = try await task.value
        tags[key] = CacheEntry(value: page, expiresAt: Date().addingTimeInterval(ttl))
        return page
    }

    func getProjects(key: CacheKey) -> Page<ProjectItem>? {
        purgeExpired()
        return projects[key]?.value
    }

    func setProjects(_ page: Page<ProjectItem>, key: CacheKey, ttl: TimeInterval) {
        projects[key] = CacheEntry(value: page, expiresAt: Date().addingTimeInterval(ttl))
    }

    func getTags(key: CacheKey) -> Page<TagItem>? {
        purgeExpired()
        return tags[key]?.value
    }

    func setTags(_ page: Page<TagItem>, key: CacheKey, ttl: TimeInterval) {
        tags[key] = CacheEntry(value: page, expiresAt: Date().addingTimeInterval(ttl))
    }

    func invalidateProjects() {
        projects.removeAll()
        // In-flight fills started before a mutation may carry pre-mutation
        // data; drop them so the next caller refetches rather than adopting
        // a result that is already stale.
        projectFills.values.forEach { $0.cancel() }
        projectFills.removeAll()
    }

    func invalidateTags() {
        tags.removeAll()
        tagFills.values.forEach { $0.cancel() }
        tagFills.removeAll()
    }

    func invalidateAll() {
        invalidateProjects()
        invalidateTags()
    }

    private func purgeExpired() {
        let now = Date()
        projects = projects.filter { $0.value.expiresAt > now }
        tags = tags.filter { $0.value.expiresAt > now }
    }
}
