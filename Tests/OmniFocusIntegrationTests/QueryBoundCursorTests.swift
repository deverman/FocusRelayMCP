import Foundation
import OmniFocusCore
import Testing
@testable import OmniFocusAutomation

@Test
func queryBoundCursorContinuesIdenticalQueryAndPreservesLimit() throws {
    let key = try QueryBoundCursor.queryKey(
        tool: "list_tasks",
        input: TaskFilter(search: "drop test")
    )
    let publicPage = try QueryBoundCursor.publicPage(
        from: Page<TaskItem>(
            items: [],
            nextCursor: "50",
            returnedCount: 50,
            totalCount: 120
        ),
        queryKey: key
    )
    let cursor = try #require(publicPage.nextCursor)
    #expect(cursor != "50")

    let bridgePage = try QueryBoundCursor.bridgePage(
        from: PageRequest(limit: 75, cursor: cursor),
        queryKey: key
    )
    #expect(bridgePage.limit == 75)
    #expect(bridgePage.cursor == "50")
}

@Test
func queryBoundCursorRejectsChangedQueryBeforeBridgePaging() throws {
    let reviewKey = try QueryBoundCursor.queryKey(
        tool: "list_projects",
        input: ProjectFilter(statusFilter: "active", reviewPerspective: true)
    )
    let ordinaryKey = try QueryBoundCursor.queryKey(
        tool: "list_projects",
        input: ProjectFilter(statusFilter: "active", reviewPerspective: false)
    )
    let cursor = try #require(
        QueryBoundCursor.publicPage(
            from: Page<ProjectItem>(
                items: [],
                nextCursor: "100",
                returnedCount: 100
            ),
            queryKey: reviewKey
        ).nextCursor
    )

    #expect(throws: AutomationError.self) {
        try QueryBoundCursor.bridgePage(
            from: PageRequest(limit: 100, cursor: cursor),
            queryKey: ordinaryKey
        )
    }
}

@Test(arguments: ["100", "not-a-cursor", versionTwoCursor()])
func queryBoundCursorRejectsMalformedAndUnsupportedTokens(cursor: String) throws {
    let key = try QueryBoundCursor.queryKey(
        tool: "list_folders",
        input: "stable-folder-order-v1"
    )
    #expect(throws: AutomationError.self) {
        try QueryBoundCursor.bridgePage(
            from: PageRequest(limit: 150, cursor: cursor),
            queryKey: key
        )
    }
}

@Test
func everyPublicListToolUsesASeparateQueryNamespace() throws {
    let keys = try [
        QueryBoundCursor.queryKey(tool: "list_tasks", input: TaskFilter()),
        QueryBoundCursor.queryKey(tool: "list_projects", input: ProjectFilter()),
        QueryBoundCursor.queryKey(tool: "list_tags", input: TagFilter()),
        QueryBoundCursor.queryKey(tool: "list_folders", input: "stable-folder-order-v1")
    ]
    #expect(Set(keys).count == 4)
}

private func versionTwoCursor() -> String {
    let data = try! JSONSerialization.data(
        withJSONObject: [
            "version": 2,
            "offset": "50",
            "queryKey": "list_tasks:any"
        ],
        options: [.sortedKeys]
    )
    return data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
