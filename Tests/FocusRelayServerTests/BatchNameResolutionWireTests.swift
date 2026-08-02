import Foundation
import FocusRelayOutput
import MCP
import OmniFocusCore
import Testing
@testable import FocusRelayServer

/// Direct MCP wire coverage for batch name resolution: the schema clients read,
/// and the response encoding they parse.
@Suite("Batch name resolution MCP wire contract")
struct BatchNameResolutionWireTests {
    private func toolProperties(_ toolName: String) throws -> [String: Value] {
        let tools = FocusRelayServer.makeToolsForTesting()
        guard let tool = tools.first(where: { $0.name == toolName }),
              case let .object(schema) = tool.inputSchema,
              case let .object(properties)? = schema["properties"] else {
            Issue.record("Expected an object input schema for \(toolName)")
            return [:]
        }
        return properties
    }

    @Test(arguments: ["list_projects", "list_tags"])
    func batchSurfaceIsExposedOnBothListTools(tool: String) throws {
        let properties = try toolProperties(tool)
        guard case let .object(searches)? = properties["searches"],
              case let .object(limit)? = properties["matchLimitPerSearch"] else {
            Issue.record("\(tool) must expose searches and matchLimitPerSearch")
            return
        }
        #expect(searches["type"] == .string("array"))
        #expect(searches["minItems"] == .int(1))
        #expect(searches["maxItems"] == .int(BatchNameResolution.maximumSearches),
                "advertised bound must match the enforced bound")
        #expect(limit["minimum"] == .int(1))
        #expect(limit["maximum"] == .int(BatchNameResolution.maximumMatchLimit))
        #expect(limit["default"] == .int(BatchNameResolution.defaultMatchLimit))
    }

    @Test(arguments: ["list_projects", "list_tags"])
    func schemaStatesTheExclusivityRulesClientsMustObey(tool: String) throws {
        let properties = try toolProperties(tool)
        guard case let .object(searches)? = properties["searches"],
              case let .string(description)? = searches["description"] else {
            Issue.record("searches must document its contract")
            return
        }
        #expect(description.contains("Mutually exclusive"))
        #expect(description.contains("cursor"))
        #expect(description.contains("includeTaskCounts"))
        #expect(description.contains("empty group"), "clients must know unmatched names still return a group")
    }

    @Test func truncationIsDocumentedRatherThanImplicit() throws {
        let properties = try toolProperties("list_projects")
        guard case let .object(limit)? = properties["matchLimitPerSearch"],
              case let .string(description)? = limit["description"] else {
            Issue.record("matchLimitPerSearch must document truncation")
            return
        }
        #expect(description.contains("truncated"))
    }

    @Test func batchResponseEncodesGroupsInOrderWithCounts() throws {
        let output = BatchSearchOutput(searchResults: [
            NameSearchGroupOutput(
                search: "work",
                items: [ProjectOutput(id: "p1", name: "Work", note: nil, status: "active", flagged: nil, lastReviewDate: nil, nextReviewDate: nil, reviewInterval: nil, availableTasks: nil, remainingTasks: nil, completedTasks: nil, droppedTasks: nil, totalTasks: nil, hasChildren: nil, nextTask: nil, containsSingletonActions: nil, isStalled: nil, completionDate: nil)],
                returnedCount: 1,
                truncated: true
            ),
            NameSearchGroupOutput(search: "missing", items: [ProjectOutput](), returnedCount: 0, truncated: false)
        ])

        let data = try JSONEncoder().encode(output)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let groups = json["searchResults"] as! [[String: Any]]

        #expect(groups.count == 2)
        #expect(groups[0]["search"] as? String == "work")
        #expect(groups[0]["truncated"] as? Bool == true)
        #expect(groups[1]["search"] as? String == "missing")
        #expect((groups[1]["items"] as? [Any])?.isEmpty == true,
                "an unmatched name encodes as an empty group, not a missing one")
        #expect(json["returnedCount"] as? Int == 1, "returnedCount sums matches across groups")
        #expect(json["nextCursor"] == nil, "batch responses are not paginated")
    }

    @Test(arguments: ["list_projects", "list_tags"])
    func batchArgumentsPassClosedSchemaValidation(tool: String) throws {
        let tools = FocusRelayServer.makeToolsForTesting()
        let schema = tools.first(where: { $0.name == tool })!.inputSchema
        try FocusRelayServer.validateToolArguments(
            toolName: tool,
            arguments: [
                "searches": .array([.string("work"), .string("home")]),
                "matchLimitPerSearch": .int(5),
                "statusFilter": .string("all")
            ],
            schema: schema
        )
    }
}
