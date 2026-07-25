import Foundation
import OmniFocusCore
import Testing
@testable import OmniFocusAutomation

@Test
func queryBoundCursorContinuesIdenticalQueryAndPreservesLimit() throws {
    let identity = try QueryBoundCursor.taskIdentity(
        for: TaskFilter(search: "drop test")
    )
    let publicPage = try QueryBoundCursor.publicPage(
        from: Page<TaskItem>(
            items: [],
            nextCursor: "50",
            returnedCount: 50,
            totalCount: 120
        ),
        identity: identity
    )
    let cursor = try #require(publicPage.nextCursor)
    #expect(cursor != "50")

    let bridgePage = try QueryBoundCursor.bridgePage(
        from: PageRequest(limit: 75, cursor: cursor),
        identity: identity
    )
    #expect(bridgePage.limit == 75)
    #expect(bridgePage.cursor == "50")
}

@Test
func queryBoundCursorRejectsChangedQueryBeforeBridgePaging() throws {
    let reviewIdentity = try QueryBoundCursor.queryIdentity(
        tool: "list_projects",
        input: ProjectFilter(statusFilter: "active", reviewPerspective: true)
    )
    let ordinaryIdentity = try QueryBoundCursor.queryIdentity(
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
            identity: reviewIdentity
        ).nextCursor
    )

    do {
        _ = try QueryBoundCursor.bridgePage(
            from: PageRequest(limit: 100, cursor: cursor),
            identity: ordinaryIdentity
        )
        Issue.record("Expected a changed query to reject its cursor")
    } catch {
        let message = error.localizedDescription
        #expect(message.contains("cursorVersion=2"))
        #expect(message.contains("tool=list_projects"))
        #expect(message.contains("cursorFingerprint="))
        #expect(message.contains("currentFingerprint="))
        #expect(message.contains("changedDimensions=reviewPerspective"))
        #expect(!message.contains("active"))
    }
}

@Test(arguments: ["100", "not-a-cursor", versionOneCursor()])
func queryBoundCursorRejectsMalformedAndUnsupportedTokens(cursor: String) throws {
    let identity = try QueryBoundCursor.queryIdentity(
        tool: "list_folders",
        input: "stable-folder-order-v1"
    )
    #expect(throws: AutomationError.self) {
        try QueryBoundCursor.bridgePage(
            from: PageRequest(limit: 150, cursor: cursor),
            identity: identity
        )
    }
}

@Test
func queryBoundCursorDoesNotExposeRawFilterValues() throws {
    let privateProjectID = "private-project-identifier"
    let privateSearch = "private search phrase"
    let identity = try QueryBoundCursor.taskIdentity(
        for: TaskFilter(
            completed: false,
            availableOnly: false,
            project: privateProjectID,
            search: privateSearch,
            includeTotalCount: true
        )
    )
    let cursor = try #require(
        QueryBoundCursor.publicPage(
            from: Page<TaskItem>(
                items: [],
                nextCursor: "50",
                returnedCount: 50,
                totalCount: 100
            ),
            identity: identity
        ).nextCursor
    )
    let decodedCursor = try #require(Data(base64URLTestString: cursor))
    let cursorText = String(decoding: decodedCursor, as: UTF8.self)

    #expect(!cursorText.contains(privateProjectID))
    #expect(!cursorText.contains(privateSearch))
    #expect(!cursorText.contains("queryKey"))
    #expect(cursorText.contains("queryFingerprint"))
    #expect(cursorText.contains("dimensionFingerprints"))
}

@Test
func compoundTaskFilterIdentityIsStableAndNamesChangedDimensions() throws {
    let first = TaskFilter(
        completed: false,
        availableOnly: false,
        project: "project-fixture",
        includeTotalCount: true
    )
    let identical = TaskFilter(
        completed: false,
        availableOnly: false,
        project: "project-fixture",
        includeTotalCount: true
    )
    let changedCountSemantics = TaskFilter(
        completed: false,
        availableOnly: false,
        project: "project-fixture",
        includeTotalCount: false
    )

    let firstIdentity = try QueryBoundCursor.taskIdentity(for: first)
    let identicalIdentity = try QueryBoundCursor.taskIdentity(for: identical)
    let changedIdentity = try QueryBoundCursor.taskIdentity(for: changedCountSemantics)

    #expect(firstIdentity == identicalIdentity)
    #expect(firstIdentity.fingerprint != changedIdentity.fingerprint)
    #expect(
        firstIdentity.dimensionFingerprints["includeTotalCount"]
            != changedIdentity.dimensionFingerprints["includeTotalCount"]
    )
}

@Test
func taskCursorIdentityNormalizesProvenBridgeDefaults() throws {
    let omittedDefaults = try QueryBoundCursor.taskIdentity(for: TaskFilter())
    let explicitDefaults = try QueryBoundCursor.taskIdentity(
        for: TaskFilter(
            inboxView: "available",
            inboxOnly: false,
            includeTotalCount: false
        )
    )
    let meaningfulChange = try QueryBoundCursor.taskIdentity(
        for: TaskFilter(availableOnly: false)
    )

    #expect(omittedDefaults == explicitDefaults)
    #expect(omittedDefaults != meaningfulChange)
}

@Test
func everyPublicListToolUsesASeparateQueryNamespace() throws {
    let keys = try [
        QueryBoundCursor.taskIdentity(for: TaskFilter()),
        QueryBoundCursor.queryIdentity(tool: "list_projects", input: ProjectFilter()),
        QueryBoundCursor.queryIdentity(tool: "list_tags", input: TagFilter()),
        QueryBoundCursor.queryIdentity(tool: "list_folders", input: "stable-folder-order-v1")
    ]
    #expect(Set(keys.map(\.fingerprint)).count == 4)
}

private func versionOneCursor() -> String {
    let data = try! JSONSerialization.data(
        withJSONObject: [
            "version": 1,
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

private extension Data {
    init?(base64URLTestString: String) {
        var base64 = base64URLTestString
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: base64)
    }
}
