import Foundation
import Testing
@testable import OmniFocusAutomation
import OmniFocusCore

private func projectKey(
    page: PageRequest = PageRequest(limit: 10, cursor: "cursor"),
    fields: [String]? = ["id", "name"],
    _ filter: ProjectFilter
) -> CacheKey {
    try! CacheKey.projects(page: page, fields: fields, filter: filter)
}

private func tagKey(
    page: PageRequest = PageRequest(limit: 10, cursor: "cursor"),
    fields: [String]? = ["id", "name"],
    _ filter: TagFilter
) -> CacheKey {
    try! CacheKey.tags(page: page, fields: fields, filter: filter)
}

@Test
func projectCacheKeyMatchesForSameInputs() {
    let filter = ProjectFilter(statusFilter: "active", includeTaskCounts: true)
    #expect(projectKey(filter) == projectKey(filter))
}

@Test
func projectCacheKeySeparatesStatusFilter() {
    #expect(projectKey(ProjectFilter(statusFilter: "active", includeTaskCounts: false))
        != projectKey(ProjectFilter(statusFilter: "done", includeTaskCounts: false)))
}

@Test
func projectCacheKeySeparatesNameSearch() {
    let page = PageRequest(limit: 10)
    #expect(projectKey(page: page, ProjectFilter(statusFilter: "all", includeTaskCounts: false, search: "drop test"))
        != projectKey(page: page, ProjectFilter(statusFilter: "all", includeTaskCounts: false, search: "another")))
}

@Test
func projectCacheKeySeparatesIncludeTaskCounts() {
    #expect(projectKey(ProjectFilter(statusFilter: "active", includeTaskCounts: false))
        != projectKey(ProjectFilter(statusFilter: "active", includeTaskCounts: true)))
}

@Test
func projectCacheKeySeparatesRequestedFields() {
    let filter = ProjectFilter(statusFilter: "active", includeTaskCounts: false)
    #expect(projectKey(fields: ["id", "name"], filter) != projectKey(fields: ["id", "name", "folderPath"], filter))
}

/// The near-miss from #88: `rootOnly` must change the key, or a cached
/// full-catalogue page satisfies a request for unfiled projects only.
@Test
func projectCacheKeySeparatesRootOnly() {
    #expect(projectKey(ProjectFilter(statusFilter: "active"))
        != projectKey(ProjectFilter(rootOnly: true, statusFilter: "active")))
}

/// The field #171 added. Under the previous hand-listed key this was invisible;
/// derivation covers it without anyone remembering to.
@Test
func projectCacheKeySeparatesBatchSearches() {
    #expect(projectKey(ProjectFilter(statusFilter: "active"))
        != projectKey(ProjectFilter(searches: ["work"], statusFilter: "active")))
}

@Test
func tagCacheKeySeparatesStatusFilter() {
    #expect(tagKey(TagFilter(statusFilter: "active", includeTaskCounts: false))
        != tagKey(TagFilter(statusFilter: "onHold", includeTaskCounts: false)))
}

@Test
func tagCacheKeySeparatesIncludeTaskCounts() {
    #expect(tagKey(TagFilter(statusFilter: "active", includeTaskCounts: false))
        != tagKey(TagFilter(statusFilter: "active", includeTaskCounts: true)))
}

@Test
func tagCacheKeySeparatesSearchAndHierarchyFields() {
    let filter = TagFilter(statusFilter: "active", includeTaskCounts: false, search: "contact")
    let compact = tagKey(fields: ["id", "name"], filter)
    let hierarchy = tagKey(fields: ["id", "name", "path"], filter)
    let differentSearch = tagKey(
        fields: ["id", "name"],
        TagFilter(statusFilter: "active", includeTaskCounts: false, search: "context")
    )

    #expect(compact != hierarchy)
    #expect(compact != differentSearch)
}

@Test
func tagCacheKeySeparatesBatchSearches() {
    #expect(tagKey(TagFilter(statusFilter: "active"))
        != tagKey(TagFilter(searches: ["work"], statusFilter: "active")))
}

@Test
func catalogCacheSeparatesProjectEntriesByKey() async {
    let cache = CatalogCache()
    let page = PageRequest(limit: 10)
    let summary = ProjectTaskSummary(id: "task-1", name: "Next")
    let activeKey = projectKey(page: page, ProjectFilter(statusFilter: "active", includeTaskCounts: false))
    let doneKey = projectKey(page: page, ProjectFilter(statusFilter: "done", includeTaskCounts: false))
    let activePage = Page(
        items: [ProjectItem(id: "project-active", name: "Active", status: "active", flagged: false, nextTask: summary)],
        returnedCount: 1,
        totalCount: 1
    )
    let donePage = Page(
        items: [ProjectItem(id: "project-done", name: "Done", status: "done", flagged: false)],
        returnedCount: 1,
        totalCount: 1
    )

    await cache.setProjects(activePage, key: activeKey, ttl: 60)
    await cache.setProjects(donePage, key: doneKey, ttl: 60)

    let cachedActive = await cache.getProjects(key: activeKey)
    let cachedDone = await cache.getProjects(key: doneKey)
    #expect(cachedActive?.items.first?.id == "project-active")
    #expect(cachedDone?.items.first?.id == "project-done")
}

@Test
func catalogCacheSeparatesTagEntriesByKey() async {
    let cache = CatalogCache()
    let page = PageRequest(limit: 10)
    let plainKey = tagKey(page: page, TagFilter(statusFilter: "active", includeTaskCounts: false))
    let countedKey = tagKey(page: page, TagFilter(statusFilter: "active", includeTaskCounts: true))
    let plainPage = Page(
        items: [TagItem(id: "tag-1", name: "Inbox", status: "active")],
        returnedCount: 1,
        totalCount: 1
    )
    let countedPage = Page(
        items: [TagItem(id: "tag-1", name: "Inbox", status: "active", availableTasks: 2, remainingTasks: 3, totalTasks: 5)],
        returnedCount: 1,
        totalCount: 1
    )

    await cache.setTags(plainPage, key: plainKey, ttl: 60)
    await cache.setTags(countedPage, key: countedKey, ttl: 60)

    let cachedPlain = await cache.getTags(key: plainKey)
    let cachedCounted = await cache.getTags(key: countedKey)
    #expect(cachedPlain?.items.first?.totalTasks == nil)
    #expect(cachedCounted?.items.first?.totalTasks == 5)
}

@Test
func catalogCacheInvalidatesProjectsAndTags() async {
    let cache = CatalogCache()
    let pKey = projectKey(
        page: PageRequest(limit: 10),
        fields: ["id"],
        ProjectFilter(statusFilter: "active", includeTaskCounts: false)
    )
    let tKey = tagKey(page: PageRequest(limit: 10), TagFilter(statusFilter: "active", includeTaskCounts: false))

    await cache.setProjects(
        Page(items: [ProjectItem(id: "project-1", name: "Project", status: "active", flagged: false)], returnedCount: 1, totalCount: 1),
        key: pKey,
        ttl: 60
    )
    await cache.setTags(
        Page(items: [TagItem(id: "tag-1", name: "Tag", status: "active")], returnedCount: 1, totalCount: 1),
        key: tKey,
        ttl: 60
    )

    await cache.invalidateAll()

    let cachedProject = await cache.getProjects(key: pKey)
    let cachedTag = await cache.getTags(key: tKey)
    #expect(cachedProject == nil)
    #expect(cachedTag == nil)
}

/// The point of deriving the key: cacheability and identity are decided from
/// the same encoded filter, so a new field cannot be missed by one and not the
/// other.
@Suite("Filter cache identity")
struct FilterCacheIdentityTests {
    @Test func ordinaryFilterIsCacheable() throws {
        #expect(try FilterCacheIdentity.isCacheable(
            ProjectFilter(statusFilter: "active"),
            uncacheableFields: FilterCacheIdentity.uncacheableProjectFields
        ))
    }

    @Test func reviewPerspectiveIsNotCacheable() throws {
        #expect(!(try FilterCacheIdentity.isCacheable(
            ProjectFilter(statusFilter: "active", reviewPerspective: true),
            uncacheableFields: FilterCacheIdentity.uncacheableProjectFields
        )))
    }

    @Test func completionWindowIsNotCacheable() throws {
        #expect(!(try FilterCacheIdentity.isCacheable(
            ProjectFilter(statusFilter: "active", completed: true),
            uncacheableFields: FilterCacheIdentity.uncacheableProjectFields
        )))
    }

    @Test func batchResolutionIsNotCacheable() throws {
        #expect(!(try FilterCacheIdentity.isCacheable(
            ProjectFilter(searches: ["work"], statusFilter: "active"),
            uncacheableFields: FilterCacheIdentity.uncacheableProjectFields
        )))
    }

    @Test func absentFieldsDoNotCountAsPresent() throws {
        let names = try FilterCacheIdentity.presentFieldNames(of: ProjectFilter(statusFilter: "active"))
        #expect(names.contains("statusFilter"))
        #expect(!names.contains("completed"), "a nil field must not encode")
    }

    @Test func identicalFiltersFingerprintIdentically() throws {
        let a = try FilterCacheIdentity.fingerprint(ProjectFilter(statusFilter: "active", search: "x"))
        let b = try FilterCacheIdentity.fingerprint(ProjectFilter(statusFilter: "active", search: "x"))
        #expect(a == b)
    }

    @Test func anyFieldChangeChangesTheFingerprint() throws {
        let base = try FilterCacheIdentity.fingerprint(ProjectFilter(statusFilter: "active"))
        for changed in [
            ProjectFilter(statusFilter: "done"),
            ProjectFilter(rootOnly: true, statusFilter: "active"),
            ProjectFilter(statusFilter: "active", includeTaskCounts: true),
            ProjectFilter(statusFilter: "active", search: "x"),
            ProjectFilter(matchLimitPerSearch: 5, statusFilter: "active")
        ] {
            #expect(try FilterCacheIdentity.fingerprint(changed) != base)
        }
    }
}
