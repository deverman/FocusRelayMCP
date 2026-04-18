import Foundation
import OmniFocusCore

struct CacheKey: Hashable {
    let limit: Int
    let cursor: String?
    let fieldsKey: String
    let statusFilter: String?
    let includeTaskCounts: Bool

    private init(
        limit: Int,
        cursor: String?,
        fieldsKey: String,
        statusFilter: String?,
        includeTaskCounts: Bool
    ) {
        self.limit = limit
        self.cursor = cursor
        self.fieldsKey = fieldsKey
        self.statusFilter = statusFilter
        self.includeTaskCounts = includeTaskCounts
    }

    static func projects(
        page: PageRequest,
        fields: [String]?,
        statusFilter: String?,
        includeTaskCounts: Bool
    ) -> CacheKey {
        CacheKey(
            limit: page.limit,
            cursor: page.cursor,
            fieldsKey: (fields ?? []).joined(separator: ","),
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts
        )
    }

    static func tags(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool
    ) -> CacheKey {
        CacheKey(
            limit: page.limit,
            cursor: page.cursor,
            fieldsKey: "",
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts
        )
    }
}

struct CacheEntry<T> {
    let value: T
    let expiresAt: Date
}

actor CatalogCache {
    private var projects: [CacheKey: CacheEntry<Page<ProjectItem>>] = [:]
    private var tags: [CacheKey: CacheEntry<Page<TagItem>>] = [:]

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
    }

    func invalidateTags() {
        tags.removeAll()
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
