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
        return try await Task.detached { try self.client.listTasks(filter: filter, page: page, fields: fields) }.value
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
        let shouldBypassCache = reviewPerspective || reviewDueBefore != nil || reviewDueAfter != nil || completed != nil || completedBefore != nil || completedAfter != nil
        if !shouldBypassCache {
            let key = CacheKey.projects(
                page: page,
                fields: fields,
                statusFilter: statusFilter,
                includeTaskCounts: includeTaskCounts
            )
            if let cached = await cache.getProjects(key: key) {
                return cached
            }
            let pageResult = try await Task.detached {
                try self.client.listProjects(
                    page: page,
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
            return pageResult
        }

        return try await Task.detached {
            try self.client.listProjects(
                page: page,
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
    }

    public func listTags(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool) async throws -> Page<TagItem> {
        let key = CacheKey.tags(
            page: page,
            statusFilter: statusFilter,
            includeTaskCounts: includeTaskCounts
        )
        if let cached = await cache.getTags(key: key) {
            return cached
        }
        let pageResult = try await Task.detached { try self.client.listTags(page: page, statusFilter: statusFilter, includeTaskCounts: includeTaskCounts) }.value
        await cache.setTags(pageResult, key: key, ttl: cacheTTL)
        return pageResult
    }

    public func listFolders(page: PageRequest, fields: [String]?) async throws -> Page<FolderItem> {
        return try await Task.detached { try self.client.listFolders(page: page, fields: fields) }.value
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
