import Foundation
import OmniFocusCore
import Testing
@testable import OmniFocusAutomation

/// Cache correctness for the rootOnly scope. A cached full-catalogue page must
/// never satisfy a root-only request (or the reverse): the two ask different
/// questions of the same status filter, and #88's whole point is not having to
/// fetch the full catalogue to find unfiled projects.
@Suite("rootOnly cache keying")
struct RootOnlyCacheKeyTests {
    private func key(rootOnly: Bool, statusFilter: String = "active") -> CacheKey {
        try! CacheKey.projects(
            page: PageRequest(limit: 150),
            fields: ["id", "name"],
            filter: ProjectFilter(rootOnly: rootOnly ? true : nil, statusFilter: statusFilter, includeTaskCounts: false)
        )
    }

    @Test func rootOnlyChangesTheCacheKey() {
        #expect(key(rootOnly: true) != key(rootOnly: false),
                "a root-only page must not be served from the full-catalogue cache entry")
    }

    @Test func matchingRootOnlyReusesTheSameKey() {
        #expect(key(rootOnly: true) == key(rootOnly: true))
    }

    @Test func rootOnlyComposesWithStatusFilterInTheKey() {
        #expect(key(rootOnly: true, statusFilter: "active") != key(rootOnly: true, statusFilter: "all"))
    }

    @Test func cachedRootOnlyPageIsNotReturnedForAFullCatalogueRequest() async {
        let cache = CatalogCache()
        let rootPage = Page(
            items: [ProjectItem(id: "root-1", name: "Root project", status: "active", flagged: false)],
            returnedCount: 1
        )
        await cache.setProjects(rootPage, key: key(rootOnly: true), ttl: 300)

        let leaked = await cache.getProjects(key: key(rootOnly: false))
        #expect(leaked == nil, "the full-catalogue request must miss and fetch its own page")

        let hit = await cache.getProjects(key: key(rootOnly: true))
        #expect(hit?.items.first?.id == "root-1")
    }
}

/// Folder membership shape. A root project reports null membership; a filed
/// project reports its direct parent plus a root-first ancestor chain so
/// repeated folder names stay distinguishable.
@Suite("Project folder membership modelling")
struct ProjectFolderMembershipTests {
    private func project(
        id: String,
        folderID: String? = nil,
        folderName: String? = nil,
        folderPath: [FolderPathElement]? = nil
    ) -> ProjectItem {
        ProjectItem(
            id: id,
            name: "Project \(id)",
            status: "active",
            flagged: false,
            folderID: folderID,
            folderName: folderName,
            folderPath: folderPath
        )
    }

    @Test func rootProjectReportsNoFolderMembership() {
        let item = project(id: "p1")
        #expect(item.folderID == nil)
        #expect(item.folderName == nil)
        #expect(item.folderPath == nil)
    }

    @Test func filedProjectCarriesDirectParentAndAncestorChain() {
        let item = project(
            id: "p2",
            folderID: "f-child",
            folderName: "Clients",
            folderPath: [
                FolderPathElement(id: "f-root", name: "Work"),
                FolderPathElement(id: "f-child", name: "Clients")
            ]
        )
        #expect(item.folderID == "f-child")
        #expect(item.folderPath?.first?.name == "Work", "path is root-first")
        #expect(item.folderPath?.last?.id == item.folderID, "path ends at the direct parent")
    }

    @Test func duplicateFolderNamesRemainDistinguishableByPath() {
        // Two folders both named "Archive" under different roots: the direct
        // name alone is ambiguous, the path is not.
        let underWork = project(
            id: "a",
            folderID: "f-1",
            folderName: "Archive",
            folderPath: [FolderPathElement(id: "w", name: "Work"), FolderPathElement(id: "f-1", name: "Archive")]
        )
        let underHome = project(
            id: "b",
            folderID: "f-2",
            folderName: "Archive",
            folderPath: [FolderPathElement(id: "h", name: "Home"), FolderPathElement(id: "f-2", name: "Archive")]
        )
        #expect(underWork.folderName == underHome.folderName)
        #expect(underWork.folderID != underHome.folderID)
        #expect(underWork.folderPath != underHome.folderPath,
                "path must disambiguate identically named folders")
    }

    @Test func rootOnlyIsCarriedOnTheProjectFilter() {
        #expect(ProjectFilter(rootOnly: true).rootOnly == true)
        #expect(ProjectFilter().rootOnly == nil, "absent means unscoped, not false")
    }

    @Test func rootOnlyChangesTheQueryIdentitySoCursorsCannotCross() throws {
        let unscoped = try QueryBoundCursor.queryIdentity(tool: "list_projects", input: ProjectFilter(statusFilter: "active"))
        let scoped = try QueryBoundCursor.queryIdentity(tool: "list_projects", input: ProjectFilter(rootOnly: true, statusFilter: "active"))
        #expect(unscoped.fingerprint != scoped.fingerprint,
                "a cursor issued for the full catalogue must not resume a root-only query")
    }
}
