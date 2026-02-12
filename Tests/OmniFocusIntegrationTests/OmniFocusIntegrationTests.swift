import Foundation
import Testing
@testable import OmniFocusAutomation
@testable import OmniFocusCore

@Test
func listInboxTasksLive() async throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_LIVE_TESTS"] == "1" else {
        return
    }

    let service = OmniAutomationService()
    let filter = TaskFilter(inboxOnly: true)
    let page = PageRequest(limit: 10)
    let result = try await service.listTasks(filter: filter, page: page, fields: nil)

    #expect(result.items.count <= 10)

    if env["FOCUS_RELAY_DUMP_INBOX"] == "1" {
        print("Inbox sample (up to \(result.items.count)):")
        for item in result.items {
            print("- [\(item.id)] \(item.name)")
        }
    }

    if let expectedName = env["FOCUS_RELAY_EXPECT_INBOX_TASK"], !expectedName.isEmpty {
        let matches = result.items.contains { $0.name == expectedName }
        #expect(matches)
    }
}

@Test
func bridgeHealthCheckLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let response = try client.ping()
    #expect(response.ok)
}

@Test
func bridgeListInboxLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let filter = TaskFilter(inboxOnly: true)
    let page = PageRequest(limit: 5)
    let result = try client.listTasks(filter: filter, page: page, fields: ["id", "name"])
    #expect(result.items.count <= 5)
}

@Test
func bridgeTaskCountsLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let counts = try client.getTaskCounts(filter: TaskFilter(inboxOnly: true))
    #expect(counts.total >= 0)
}

@Test
func bridgeInboxViewCountsMatchListTasksLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let views = ["remaining", "available", "everything"]
    for view in views {
        let filter = TaskFilter(inboxView: view, inboxOnly: true, includeTotalCount: true)
        let counts = try client.getTaskCounts(filter: filter)
        let page = try client.listTasks(filter: filter, page: PageRequest(limit: 50), fields: ["id"])
        #expect(counts.total == (page.totalCount ?? -1))
    }
}

@Test
func bridgeProjectCountsLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let counts = try client.getProjectCounts(filter: TaskFilter(projectView: "remaining"))
    #expect(counts.projects >= 0)
    #expect(counts.actions >= 0)
}

@Test
func bridgeProjectsPagingLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let first = try client.listProjects(
        page: PageRequest(limit: 2),
        statusFilter: "active",
        includeTaskCounts: false,
        reviewDueBefore: nil,
        reviewDueAfter: nil,
        reviewPerspective: false,
        completed: nil,
        completedBefore: nil,
        completedAfter: nil,
        fields: ["id", "name"]
    )
    #expect(first.items.count <= 2)
    #expect((first.totalCount ?? 0) >= first.items.count)
    if let cursor = first.nextCursor {
        let second = try client.listProjects(
            page: PageRequest(limit: 2, cursor: cursor),
            statusFilter: "active",
            includeTaskCounts: false,
            reviewDueBefore: nil,
            reviewDueAfter: nil,
            reviewPerspective: false,
            completed: nil,
            completedBefore: nil,
            completedAfter: nil,
            fields: ["id", "name"]
        )
        #expect(second.items.count <= 2)
    }
}

@Test
func bridgeTagsPagingLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let first = try client.listTags(page: PageRequest(limit: 2), statusFilter: nil, includeTaskCounts: false)
    #expect(first.items.count <= 2)
    #expect((first.totalCount ?? 0) >= first.items.count)
    if let cursor = first.nextCursor {
        let second = try client.listTags(page: PageRequest(limit: 2, cursor: cursor), statusFilter: nil, includeTaskCounts: false)
        #expect(second.items.count <= 2)
    }
}
