import FocusRelayVersion
import Foundation
import OmniFocusCore

public final class OmniFocusBridgeService: OmniFocusService {
    private let client: BridgeClient
    private let cache: CatalogCache
    private let runtime: BridgeRuntime
    private let cacheTTL: TimeInterval = 300

    public init() {
        self.client = BridgeClient()
        self.cache = CatalogCache()
        self.runtime = .shared
    }

    init(client: BridgeClient, cache: CatalogCache, runtime: BridgeRuntime) {
        self.client = client
        self.cache = cache
        self.runtime = runtime
    }

    public func setWarningsHandler(_ handler: (@Sendable (_ warnings: [String], _ op: String) -> Void)?) {
        client.onResponseWarnings = handler
    }

    public func listTasks(filter: TaskFilter, page: PageRequest, fields: [String]?) async throws -> Page<TaskItem> {
        var normalizedFilter = filter
        normalizedFilter.ids = try TaskIDSelection.normalize(filter.ids)
        let resolvedFilter = normalizedFilter

        if let ids = resolvedFilter.ids {
            // A bounded ID selection is one complete response: no cursor in,
            // no cursor out, and the caller's requested order is preserved.
            try TaskIDSelection.validatePaging(idCount: ids.count, limit: page.limit, cursor: page.cursor)
            let result = try await runtime.submit(category: .taskQuery) {
                try self.client.listTasks(filter: resolvedFilter, page: PageRequest(limit: page.limit), fields: fields)
            }
            let (ordered, unresolved) = TaskIDSelection.order(result.items, by: ids) { $0.id }
            return Page(
                items: ordered,
                nextCursor: nil,
                returnedCount: ordered.count,
                totalCount: result.totalCount,
                warnings: result.warnings,
                unresolvedIDs: unresolved
            )
        }

        let identity = try QueryBoundCursor.taskIdentity(for: resolvedFilter)
        let bridgePage = try QueryBoundCursor.bridgePage(from: page, identity: identity)
        let result = try await runtime.submit(category: .taskQuery) {
            try self.client.listTasks(filter: resolvedFilter, page: bridgePage, fields: fields)
        }
        return try QueryBoundCursor.publicPage(from: result, identity: identity)
    }

    public func getTask(id: String, fields: [String]?) async throws -> TaskItem {
        try await runtime.submit(category: .taskQuery) {
            try self.client.getTask(id: id, fields: fields)
        }
    }

    public func listProjects(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool,
        search: String? = nil,
        rootOnly: Bool,
        reviewDueBefore: Date?,
        reviewDueAfter: Date?,
        reviewPerspective: Bool,
        completed: Bool?,
        completedBefore: Date?,
        completedAfter: Date?,
        fields: [String]?
    ) async throws -> Page<ProjectItem> {
        let normalizedSearch = try Self.normalizeProjectSearch(search)
        let projectFilter = ProjectFilter(
            rootOnly: rootOnly ? true : nil,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            search: normalizedSearch,
            reviewDueBefore: reviewDueBefore,
            reviewDueAfter: reviewDueAfter,
            reviewPerspective: reviewPerspective,
            completed: completed,
            completedBefore: completedBefore,
            completedAfter: completedAfter
        )
        let identity = try QueryBoundCursor.queryIdentity(
            tool: "list_projects",
            input: projectFilter
        )
        let bridgePage = try QueryBoundCursor.bridgePage(from: page, identity: identity)
        let shouldBypassCache = reviewPerspective || reviewDueBefore != nil || reviewDueAfter != nil || completed != nil || completedBefore != nil || completedAfter != nil
        if !shouldBypassCache {
            let key = CacheKey.projects(
                page: bridgePage,
                fields: fields,
                statusFilter: statusFilter,
                includeTaskCounts: includeTaskCounts,
                search: normalizedSearch,
                rootOnly: rootOnly
            )
            if let cached = await cache.getProjects(key: key) {
                return try QueryBoundCursor.publicPage(from: cached, identity: identity)
            }
            let pageResult = try await runtime.submit(
                category: .projectQuery,
                bridge: {
                    try self.client.listProjects(
                        page: bridgePage,
                        statusFilter: statusFilter,
                        includeTaskCounts: includeTaskCounts,
                        search: normalizedSearch,
                        rootOnly: rootOnly,
                        reviewDueBefore: reviewDueBefore,
                        reviewDueAfter: reviewDueAfter,
                        reviewPerspective: reviewPerspective,
                        completed: completed,
                        completedBefore: completedBefore,
                        completedAfter: completedAfter,
                        fields: fields
                    )
                },
                finalize: { pageResult in
                    await self.cache.setProjects(pageResult, key: key, ttl: self.cacheTTL)
                    return pageResult
                }
            )
            return try QueryBoundCursor.publicPage(from: pageResult, identity: identity)
        }

        let pageResult = try await runtime.submit(category: .projectQuery) {
            try self.client.listProjects(
                page: bridgePage,
                statusFilter: statusFilter,
                includeTaskCounts: includeTaskCounts,
                search: normalizedSearch,
                rootOnly: rootOnly,
                reviewDueBefore: reviewDueBefore,
                reviewDueAfter: reviewDueAfter,
                reviewPerspective: reviewPerspective,
                completed: completed,
                completedBefore: completedBefore,
                completedAfter: completedAfter,
                fields: fields
            )
        }
        return try QueryBoundCursor.publicPage(from: pageResult, identity: identity)
    }

    static func normalizeProjectSearch(_ search: String?) throws -> String? {
        guard let search else { return nil }
        let normalized = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AutomationError.executionFailed(
                "Project search must contain at least one non-whitespace character."
            )
        }
        return normalized
    }

    public func listTags(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool,
        search: String?,
        fields: [String]?
    ) async throws -> Page<TagItem> {
        let normalizedSearch = try Self.normalizeTagSearch(search)
        let filter = TagFilter(
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            search: normalizedSearch
        )
        let identity = try QueryBoundCursor.queryIdentity(tool: "list_tags", input: filter)
        let bridgePage = try QueryBoundCursor.bridgePage(from: page, identity: identity)
        let key = CacheKey.tags(
            page: bridgePage,
            fields: fields,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            search: normalizedSearch
        )
        if let cached = await cache.getTags(key: key) {
            return try QueryBoundCursor.publicPage(from: cached, identity: identity)
        }
        let pageResult = try await runtime.submit(
            category: .tagQuery,
            bridge: {
                try self.client.listTags(
                    page: bridgePage,
                    statusFilter: statusFilter,
                    includeTaskCounts: includeTaskCounts,
                    search: normalizedSearch,
                    fields: fields
                )
            },
            finalize: { pageResult in
                await self.cache.setTags(pageResult, key: key, ttl: self.cacheTTL)
                return pageResult
            }
        )
        return try QueryBoundCursor.publicPage(from: pageResult, identity: identity)
    }

    static func normalizeTagSearch(_ search: String?) throws -> String? {
        guard let search else { return nil }
        let normalized = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw AutomationError.executionFailed(
                "Tag search must contain at least one non-whitespace character."
            )
        }
        return normalized
    }

    public func listFolders(page: PageRequest, fields: [String]?) async throws -> Page<FolderItem> {
        let identity = try QueryBoundCursor.queryIdentity(
            tool: "list_folders",
            input: "stable-folder-order-v1"
        )
        let bridgePage = try QueryBoundCursor.bridgePage(from: page, identity: identity)
        let result = try await runtime.submit(category: .folderQuery) {
            try self.client.listFolders(page: bridgePage, fields: fields)
        }
        return try QueryBoundCursor.publicPage(from: result, identity: identity)
    }

    public func getTaskCounts(filter: TaskFilter) async throws -> TaskCounts {
        try await runtime.submit(category: .countsQuery) {
            try self.client.getTaskCounts(filter: filter)
        }
    }

    public func getProjectCounts(filter: TaskFilter) async throws -> ProjectCounts {
        try await runtime.submit(category: .countsQuery) {
            try self.client.getProjectCounts(filter: filter)
        }
    }

    public func performMutation(_ request: MutationRequest) async throws -> MutationResponse {
        let category: BridgeOperationCategory = request.previewOnly ? .mutationPreview : .mutationApply
        return try await runtime.submit(
            category: category,
            bridge: {
                try self.client.performMutation(request)
            },
            finalize: { response in
                if !request.previewOnly && response.successCount > 0 {
                    await self.cache.invalidateAll()
                }
                return response
            }
        )
    }

    public func healthCheck() async throws -> BridgeHealthResult {
        try await runtime.submit(category: .health) {
            let response = try self.client.ping()
            if response.ok, let version = response.data?.version {
                // A plugin-only reinstall changes the observed version without
                // a binary upgrade; invalidate the IPC directory once.
                self.client.recordObservedPluginVersion(version)
            }
            let bundles = installedFocusRelayPluginBundles()
            return BridgeHealthResult(
                ok: response.ok,
                plugin: response.data?.plugin,
                version: response.data?.version,
                error: response.error?.message,
                installedPlugins: bundles,
                pluginWarning: pluginConsistencyWarning(
                    loadedVersion: response.data?.version,
                    binaryVersion: FocusRelayBuildVersion.current,
                    bundles: bundles
                )
            )
        }
    }
}

public struct BridgeHealthResult: Codable, Sendable {
    public let ok: Bool
    public let plugin: String?
    public let version: String?
    public let error: String?
    /// Every plug-in bundle found on disk, so a stale copy in a directory the
    /// user did not update is visible without manual filesystem inspection.
    public let installedPlugins: [InstalledPluginBundle]?
    /// Set when the loaded plug-in disagrees with an installed copy or with
    /// the binary; nil when everything lines up.
    public let pluginWarning: String?

    public init(
        ok: Bool,
        plugin: String?,
        version: String?,
        error: String?,
        installedPlugins: [InstalledPluginBundle]? = nil,
        pluginWarning: String? = nil
    ) {
        self.ok = ok
        self.plugin = plugin
        self.version = version
        self.error = error
        self.installedPlugins = installedPlugins
        self.pluginWarning = pluginWarning
    }
}
