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
func bridgeTaskCountsRespectsProjectViewLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let filter = TaskFilter(
        completed: false,
        availableOnly: false,
        projectView: "active",
        includeTotalCount: true
    )

    let counts = try client.getTaskCounts(filter: filter)
    #expect(counts.total >= 0)
}

@Test
func bridgeCompletedInboxFilterDoesNotDefaultToAvailableOnlyLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()

    // Get a stable baseline of completed inbox items.
    let everythingCounts = try client.getTaskCounts(filter: TaskFilter(inboxView: "everything", inboxOnly: true))
    guard everythingCounts.completed > 0 else {
        return
    }

    // This query previously defaulted availableOnly=true and incorrectly returned zero.
    let completedDefault = try client.getTaskCounts(filter: TaskFilter(completed: true, inboxOnly: true))
    #expect(completedDefault.total == everythingCounts.completed)

    let completedPage = try client.listTasks(
        filter: TaskFilter(completed: true, inboxOnly: true, includeTotalCount: true),
        page: PageRequest(limit: 100),
        fields: ["id", "completed", "completionDate"]
    )
    #expect((completedPage.totalCount ?? -1) == everythingCounts.completed)
}

@Test
func bridgeCompletedFalseRetainsAvailableDefaultLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let filter = TaskFilter(completed: false, inboxOnly: true, includeTotalCount: true)
    let page = try client.listTasks(filter: filter, page: PageRequest(limit: 100), fields: ["id", "completed", "available"])

    #expect(page.items.allSatisfy { $0.completed == false })
    #expect(page.items.allSatisfy { $0.available == true })

    let counts = try client.getTaskCounts(filter: filter)
    if let totalCount = page.totalCount {
        #expect(counts.total == totalCount)
    }
}

@Test
func bridgeCompletedTasksRespectDateRangeAndSortLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let filter = TaskFilter(
        completed: true,
        completedAfter: Date(timeIntervalSince1970: 0),
        includeTotalCount: true
    )
    let page = try client.listTasks(
        filter: filter,
        page: PageRequest(limit: 100),
        fields: ["id", "completed", "completionDate"]
    )

    #expect(page.items.allSatisfy { $0.completed == true })
    #expect(page.items.allSatisfy { $0.completionDate != nil })

    if page.items.count > 1 {
        for index in 1..<page.items.count {
            let previous = page.items[index - 1].completionDate ?? .distantPast
            let current = page.items[index].completionDate ?? .distantFuture
            #expect(previous >= current, "Completed tasks should be sorted newest-first")
        }
    }
}

@Test
func bridgeCompletedInboxTasksRespectDateRangeAndSortLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let filter = TaskFilter(
        completed: true,
        completedAfter: Date(timeIntervalSince1970: 0),
        inboxOnly: true,
        includeTotalCount: true
    )
    let page = try client.listTasks(
        filter: filter,
        page: PageRequest(limit: 100),
        fields: ["id", "completed", "completionDate"]
    )

    #expect(page.items.allSatisfy { $0.completed == true })
    #expect(page.items.allSatisfy { $0.completionDate != nil })

    if page.items.count > 1 {
        for index in 1..<page.items.count {
            let previous = page.items[index - 1].completionDate ?? .distantPast
            let current = page.items[index].completionDate ?? .distantFuture
            #expect(previous >= current, "Completed inbox tasks should be sorted newest-first")
        }
    }
}

@Test
func bridgeInboxViewWithoutInboxOnlyIsNotInboxScopedLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    let inboxScoped = try client.getTaskCounts(filter: TaskFilter(inboxView: "available", inboxOnly: true))
    let globalView = try client.getTaskCounts(filter: TaskFilter(inboxView: "available"))

    // Contract for current behavior: inboxView controls view mode, inboxOnly controls scope.
    #expect(globalView.total >= inboxScoped.total)
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
func bridgeListTasksRespectsProjectViewLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    guard let onHoldProjectID = env["FOCUS_RELAY_ONHOLD_PROJECT_ID"], !onHoldProjectID.isEmpty else {
        return
    }

    let client = BridgeClient()
    let filter = TaskFilter(completed: false, availableOnly: false, project: onHoldProjectID, projectView: "onHold")
    let page = PageRequest(limit: 5)
    let result = try client.listTasks(filter: filter, page: page, fields: ["id", "name"])
    #expect(result.items.count >= 0)

    let activeFilter = TaskFilter(completed: false, availableOnly: false, project: onHoldProjectID, projectView: "active")
    let activeResult = try client.listTasks(filter: activeFilter, page: page, fields: ["id", "name"])
    #expect(activeResult.items.isEmpty)
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
func bridgeProjectTaskCountsIncludedLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    // Emulate server default field behavior (id/name) while includeTaskCounts is enabled.
    let page = try client.listProjects(
        page: PageRequest(limit: 10),
        statusFilter: "active",
        includeTaskCounts: true,
        reviewDueBefore: nil,
        reviewDueAfter: nil,
        reviewPerspective: false,
        completed: nil,
        completedBefore: nil,
        completedAfter: nil,
        fields: ["id", "name"]
    )

    guard !page.items.isEmpty else {
        return
    }

    #expect(page.items.allSatisfy { $0.availableTasks != nil })
    #expect(page.items.allSatisfy { $0.remainingTasks != nil })
    #expect(page.items.allSatisfy { $0.completedTasks != nil })
    #expect(page.items.allSatisfy { $0.droppedTasks != nil })
    #expect(page.items.allSatisfy { $0.totalTasks != nil })
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

// MARK: - Status Edge Case Tests

@Test
func bridgeTasksInOnHoldProjectNotAvailableLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    guard let onHoldProjectID = env["FOCUS_RELAY_ONHOLD_PROJECT_ID"], !onHoldProjectID.isEmpty else {
        return
    }

    let client = BridgeClient()
    // Query tasks in on-hold project with availableOnly=true
    let filter = TaskFilter(
        completed: false,
        availableOnly: true,
        project: onHoldProjectID,
        projectView: "onHold"
    )
    let page = PageRequest(limit: 50)
    let result = try client.listTasks(filter: filter, page: page, fields: ["id", "name", "available"])
    
    // No tasks in an on-hold project should be available
    #expect(result.items.isEmpty, "Tasks in on-hold projects should not be available")
}

@Test
func bridgeTasksInDroppedProjectNotAvailableLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    guard let droppedProjectID = env["FOCUS_RELAY_DROPPED_PROJECT_ID"], !droppedProjectID.isEmpty else {
        return
    }

    let client = BridgeClient()
    // Query tasks in dropped project with availableOnly=true
    let filter = TaskFilter(
        completed: false,
        availableOnly: true,
        project: droppedProjectID,
        projectView: "dropped"
    )
    let page = PageRequest(limit: 50)
    let result = try client.listTasks(filter: filter, page: page, fields: ["id", "name", "available"])
    
    // No tasks in a dropped project should be available
    #expect(result.items.isEmpty, "Tasks in dropped projects should not be available")
}

@Test
func bridgeTasksInDoneProjectNotAvailableLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    guard let doneProjectID = env["FOCUS_RELAY_DONE_PROJECT_ID"], !doneProjectID.isEmpty else {
        return
    }

    let client = BridgeClient()
    // Query tasks in done project with availableOnly=true
    let filter = TaskFilter(
        completed: false,
        availableOnly: true,
        project: doneProjectID,
        projectView: "done"
    )
    let page = PageRequest(limit: 50)
    let result = try client.listTasks(filter: filter, page: page, fields: ["id", "name", "available"])
    
    // No tasks in a done project should be available
    #expect(result.items.isEmpty, "Tasks in done projects should not be available")
}

@Test
func bridgeChildTasksWithCompletedParentNotAvailableLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    guard let completedParentTaskID = env["FOCUS_RELAY_COMPLETED_PARENT_TASK_ID"], !completedParentTaskID.isEmpty else {
        return
    }

    let client = BridgeClient()
    // Get the parent task first
    let parentTask = try client.getTask(id: completedParentTaskID, fields: ["id", "name", "completed"])
    #expect(parentTask.completed == true, "Parent task should be completed for this test")
    
    // Query available tasks - children of completed parents should not appear
    let filter = TaskFilter(availableOnly: true)
    let page = PageRequest(limit: 100)
    let result = try client.listTasks(filter: filter, page: page, fields: ["id", "name", "available"])
    
    // Ensure no child tasks of the completed parent are in available results
    // This is a heuristic - we can't easily query children directly
    // But we verify the filtering logic is working
    let childTaskIds = env["FOCUS_RELAY_CHILD_TASK_IDS"]?.split(separator: ",").map(String.init) ?? []
    for childId in childTaskIds {
        let found = result.items.contains { $0.id == childId }
        #expect(!found, "Child task \(childId) of completed parent should not be available")
    }
}

@Test
func bridgeTaskStatusValuesAreValidLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    // Query a sample of tasks and verify status values
    let filter = TaskFilter(completed: nil, inboxOnly: false)
    let page = PageRequest(limit: 20)
    let result = try client.listTasks(filter: filter, page: page, fields: ["id", "name", "taskStatus", "available", "completed"])
    
    // Verify that available tasks have valid status
    for task in result.items {
        if task.available == true {
            // Available tasks should not be completed
            #expect(task.completed != true, "Available task should not be completed: \(task.name ?? "unnamed")")
        }
    }
}

@Test
func bridgeAvailableTasksCountConsistencyLive() throws {
    let env = ProcessInfo.processInfo.environment
    guard env["FOCUS_RELAY_BRIDGE_TESTS"] == "1" else {
        return
    }

    let client = BridgeClient()
    
    // Get counts
    let counts = try client.getTaskCounts(filter: TaskFilter(availableOnly: true))
    
    // Get actual tasks
    let page = try client.listTasks(
        filter: TaskFilter(availableOnly: true, includeTotalCount: true),
        page: PageRequest(limit: 1000),
        fields: ["id"]
    )
    
    // The count should match the total returned
    // Note: We compare against totalCount from the response, not items.count
    // because items might be paginated
    if let totalCount = page.totalCount {
        #expect(counts.total == totalCount, 
                "Available task count (\(counts.total)) should match listTasks total (\(totalCount))")
    }
}
