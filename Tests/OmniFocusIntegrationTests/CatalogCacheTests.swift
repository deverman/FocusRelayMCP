import Foundation
import Testing
@testable import OmniFocusAutomation
import OmniFocusCore

@Test
func projectCacheKeyMatchesForSameInputs() {
    let page = PageRequest(limit: 10, cursor: "cursor")
    let lhs = CacheKey.projects(
        page: page,
        fields: ["id", "name"],
        statusFilter: "active",
        includeTaskCounts: true
    )
    let rhs = CacheKey.projects(
        page: page,
        fields: ["id", "name"],
        statusFilter: "active",
        includeTaskCounts: true
    )

    #expect(lhs == rhs)
}

@Test
func projectCacheKeySeparatesStatusFilter() {
    let page = PageRequest(limit: 10, cursor: "cursor")
    let active = CacheKey.projects(
        page: page,
        fields: ["id", "name"],
        statusFilter: "active",
        includeTaskCounts: false
    )
    let done = CacheKey.projects(
        page: page,
        fields: ["id", "name"],
        statusFilter: "done",
        includeTaskCounts: false
    )

    #expect(active != done)
}

@Test
func projectCacheKeySeparatesIncludeTaskCounts() {
    let page = PageRequest(limit: 10, cursor: "cursor")
    let withoutCounts = CacheKey.projects(
        page: page,
        fields: ["id", "name"],
        statusFilter: "active",
        includeTaskCounts: false
    )
    let withCounts = CacheKey.projects(
        page: page,
        fields: ["id", "name"],
        statusFilter: "active",
        includeTaskCounts: true
    )

    #expect(withoutCounts != withCounts)
}

@Test
func tagCacheKeySeparatesStatusFilter() {
    let page = PageRequest(limit: 10, cursor: "cursor")
    let active = CacheKey.tags(
        page: page,
        statusFilter: "active",
        includeTaskCounts: false
    )
    let onHold = CacheKey.tags(
        page: page,
        statusFilter: "onHold",
        includeTaskCounts: false
    )

    #expect(active != onHold)
}

@Test
func tagCacheKeySeparatesIncludeTaskCounts() {
    let page = PageRequest(limit: 10, cursor: "cursor")
    let withoutCounts = CacheKey.tags(
        page: page,
        statusFilter: "active",
        includeTaskCounts: false
    )
    let withCounts = CacheKey.tags(
        page: page,
        statusFilter: "active",
        includeTaskCounts: true
    )

    #expect(withoutCounts != withCounts)
}

@Test
func catalogCacheSeparatesProjectEntriesByKey() async {
    let cache = CatalogCache()
    let page = PageRequest(limit: 10)
    let summary = ProjectTaskSummary(id: "task-1", name: "Next")
    let activeKey = CacheKey.projects(
        page: page,
        fields: ["id", "name"],
        statusFilter: "active",
        includeTaskCounts: false
    )
    let doneKey = CacheKey.projects(
        page: page,
        fields: ["id", "name"],
        statusFilter: "done",
        includeTaskCounts: false
    )
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
    let plainKey = CacheKey.tags(
        page: page,
        statusFilter: "active",
        includeTaskCounts: false
    )
    let countedKey = CacheKey.tags(
        page: page,
        statusFilter: "active",
        includeTaskCounts: true
    )
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
    let projectKey = CacheKey.projects(
        page: PageRequest(limit: 10),
        fields: ["id"],
        statusFilter: "active",
        includeTaskCounts: false
    )
    let tagKey = CacheKey.tags(
        page: PageRequest(limit: 10),
        statusFilter: "active",
        includeTaskCounts: false
    )

    await cache.setProjects(
        Page(items: [ProjectItem(id: "project-1", name: "Project", status: "active", flagged: false)], returnedCount: 1, totalCount: 1),
        key: projectKey,
        ttl: 60
    )
    await cache.setTags(
        Page(items: [TagItem(id: "tag-1", name: "Tag", status: "active")], returnedCount: 1, totalCount: 1),
        key: tagKey,
        ttl: 60
    )

    await cache.invalidateAll()

    let cachedProject = await cache.getProjects(key: projectKey)
    let cachedTag = await cache.getTags(key: tagKey)

    #expect(cachedProject == nil)
    #expect(cachedTag == nil)
}
