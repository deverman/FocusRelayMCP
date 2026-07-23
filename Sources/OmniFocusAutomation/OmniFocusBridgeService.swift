import Foundation
import OmniFocusCore

public final class OmniFocusBridgeService: OmniFocusService {
    private let client: BridgeClient
    private let cache = CatalogCache()
    private let cacheTTL: TimeInterval = 300

    public init() {
        self.client = BridgeClient()
    }

    public func setWarningsHandler(_ handler: (@Sendable (_ warnings: [String], _ op: String) -> Void)?) {
        client.onResponseWarnings = handler
    }

    public func listTasks(filter: TaskFilter, page: PageRequest, fields: [String]?) async throws -> Page<TaskItem> {
        let queryKey = try QueryBoundCursor.queryKey(tool: "list_tasks", input: filter)
        let bridgePage = try QueryBoundCursor.bridgePage(from: page, queryKey: queryKey)
        let result = try await Task.detached {
            try self.client.listTasks(filter: filter, page: bridgePage, fields: fields)
        }.value
        return try QueryBoundCursor.publicPage(from: result, queryKey: queryKey)
    }

    public func getTask(id: String, fields: [String]?) async throws -> TaskItem {
        return try await Task.detached { try self.client.getTask(id: id, fields: fields) }.value
    }

    public func listProjects(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool,
        reviewDueBefore: Date?,
        reviewDueAfter: Date?,
        reviewPerspective: Bool,
        completed: Bool?,
        completedBefore: Date?,
        completedAfter: Date?,
        fields: [String]?
    ) async throws -> Page<ProjectItem> {
        let projectFilter = ProjectFilter(
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts,
            reviewDueBefore: reviewDueBefore,
            reviewDueAfter: reviewDueAfter,
            reviewPerspective: reviewPerspective,
            completed: completed,
            completedBefore: completedBefore,
            completedAfter: completedAfter
        )
        let queryKey = try QueryBoundCursor.queryKey(
            tool: "list_projects",
            input: projectFilter
        )
        let bridgePage = try QueryBoundCursor.bridgePage(from: page, queryKey: queryKey)
        let shouldBypassCache = reviewPerspective || reviewDueBefore != nil || reviewDueAfter != nil || completed != nil || completedBefore != nil || completedAfter != nil
        if !shouldBypassCache {
            let key = CacheKey.projects(
                page: bridgePage,
                fields: fields,
                statusFilter: statusFilter,
                includeTaskCounts: includeTaskCounts
            )
            if let cached = await cache.getProjects(key: key) {
                return try QueryBoundCursor.publicPage(from: cached, queryKey: queryKey)
            }
            let pageResult = try await Task.detached {
                try self.client.listProjects(
                    page: bridgePage,
                    statusFilter: statusFilter,
                    includeTaskCounts: includeTaskCounts,
                    reviewDueBefore: reviewDueBefore,
                    reviewDueAfter: reviewDueAfter,
                    reviewPerspective: reviewPerspective,
                    completed: completed,
                    completedBefore: completedBefore,
                    completedAfter: completedAfter,
                    fields: fields
                )
            }.value
            await cache.setProjects(pageResult, key: key, ttl: cacheTTL)
            return try QueryBoundCursor.publicPage(from: pageResult, queryKey: queryKey)
        }

        let pageResult = try await Task.detached {
            try self.client.listProjects(
                page: bridgePage,
                statusFilter: statusFilter,
                includeTaskCounts: includeTaskCounts,
                reviewDueBefore: reviewDueBefore,
                reviewDueAfter: reviewDueAfter,
                reviewPerspective: reviewPerspective,
                completed: completed,
                completedBefore: completedBefore,
                completedAfter: completedAfter,
                fields: fields
            )
        }.value
        return try QueryBoundCursor.publicPage(from: pageResult, queryKey: queryKey)
    }

    public func listTags(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool) async throws -> Page<TagItem> {
        let filter = TagFilter(
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts
        )
        let queryKey = try QueryBoundCursor.queryKey(tool: "list_tags", input: filter)
        let bridgePage = try QueryBoundCursor.bridgePage(from: page, queryKey: queryKey)
        let key = CacheKey.tags(
            page: bridgePage,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts
        )
        if let cached = await cache.getTags(key: key) {
            return try QueryBoundCursor.publicPage(from: cached, queryKey: queryKey)
        }
        let pageResult = try await Task.detached {
            try self.client.listTags(
                page: bridgePage,
                statusFilter: statusFilter,
                includeTaskCounts: includeTaskCounts
            )
        }.value
        await cache.setTags(pageResult, key: key, ttl: cacheTTL)
        return try QueryBoundCursor.publicPage(from: pageResult, queryKey: queryKey)
    }

    public func listFolders(page: PageRequest, fields: [String]?) async throws -> Page<FolderItem> {
        let queryKey = try QueryBoundCursor.queryKey(
            tool: "list_folders",
            input: "stable-folder-order-v1"
        )
        let bridgePage = try QueryBoundCursor.bridgePage(from: page, queryKey: queryKey)
        let result = try await Task.detached {
            try self.client.listFolders(page: bridgePage, fields: fields)
        }.value
        return try QueryBoundCursor.publicPage(from: result, queryKey: queryKey)
    }

    public func getTaskCounts(filter: TaskFilter) async throws -> TaskCounts {
        return try await Task.detached { try self.client.getTaskCounts(filter: filter) }.value
    }

    public func getProjectCounts(filter: TaskFilter) async throws -> ProjectCounts {
        return try await Task.detached { try self.client.getProjectCounts(filter: filter) }.value
    }

    public func performMutation(_ request: MutationRequest) async throws -> MutationResponse {
        let response = try await Task.detached { try self.client.performMutation(request) }.value
        if !request.previewOnly && response.successCount > 0 {
            await cache.invalidateAll()
        }
        return response
    }

    public func healthCheck() throws -> BridgeHealthResult {
        let response = try client.ping()
        return BridgeHealthResult(
            ok: response.ok,
            plugin: response.data?.plugin,
            version: response.data?.version,
            error: response.error?.message
        )
    }
}

public struct BridgeHealthResult: Codable, Sendable {
    public let ok: Bool
    public let plugin: String?
    public let version: String?
    public let error: String?
}
