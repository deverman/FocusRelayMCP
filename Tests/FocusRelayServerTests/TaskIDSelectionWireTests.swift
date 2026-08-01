import Foundation
import MCP
import OmniFocusCore
import Testing
@testable import FocusRelayServer

/// Direct MCP wire coverage for the bounded stable-ID selection surface:
/// the schema clients actually read, and the closed-property validation that
/// rejects misuse before any Bridge dispatch.
@Suite("filter.ids MCP wire contract")
struct TaskIDSelectionWireTests {
    private func filterProperties(includeTaskIDSelection: Bool) throws -> [String: Value] {
        guard case let .object(schema) = FocusRelayServer.makeTaskFilterSchema(
            includeTaskIDSelection: includeTaskIDSelection
        ),
        case let .object(properties)? = schema["properties"] else {
            Issue.record("Expected an object task-filter schema with object properties")
            return [:]
        }
        return properties
    }

    @Test func listTasksFilterExposesBoundedIDSelection() throws {
        let properties = try filterProperties(includeTaskIDSelection: true)
        guard case let .object(idsSchema)? = properties["ids"] else {
            Issue.record("list_tasks filter must expose ids")
            return
        }
        #expect(idsSchema["type"] == .string("array"))
        #expect(idsSchema["items"] == .object(["type": .string("string")]))
        #expect(idsSchema["minItems"] == .int(1))
        #expect(idsSchema["maxItems"] == .int(TaskIDSelection.maximumCount),
                "the advertised bound must match the enforced bound")
    }

    @Test func idSelectionDescriptionStatesTheContractClientsDependOn() throws {
        let properties = try filterProperties(includeTaskIDSelection: true)
        guard case let .object(idsSchema)? = properties["ids"],
              case let .string(description)? = idsSchema["description"] else {
            Issue.record("ids must document its contract")
            return
        }
        #expect(description.contains("unresolvedIDs"), "clients must know how absent IDs are reported")
        #expect(description.contains("intersection"), "other filters still apply")
        #expect(description.contains("cursor"), "pagination is rejected, not silently ignored")
        #expect(description.contains("get_task"), "the point is replacing per-item get_task calls")
    }

    @Test func countsFilterDoesNotOfferIDSelection() throws {
        let properties = try filterProperties(includeTaskIDSelection: false)
        #expect(properties["ids"] == nil,
                "get_task_counts returns scalars; selecting specific tasks there has no meaning")
    }

    @Test func countsRejectsIDSelectionAtTheWireBoundary() throws {
        // Close the schema the way the tool definition does, so this asserts
        // the shape clients are actually validated against.
        let schema = closingObjectSchemas(FocusRelayServer.makeTaskFilterSchema(includeTaskIDSelection: false))
        #expect(throws: MutationValidationError.self) {
            try FocusRelayServer.validateToolArguments(
                toolName: "get_task_counts.filter",
                arguments: ["ids": .array([.string("some-id")])],
                schema: schema
            )
        }
    }

    @Test func listTasksAcceptsIDSelectionAtTheWireBoundary() throws {
        let schema = closingObjectSchemas(FocusRelayServer.makeTaskFilterSchema(includeTaskIDSelection: true))
        try FocusRelayServer.validateToolArguments(
            toolName: "list_tasks.filter",
            arguments: [
                "ids": .array([.string("id-1"), .string("id-2")]),
                "inboxOnly": .bool(true),
                "inboxView": .string("remaining")
            ],
            schema: schema
        )
    }

    @Test func idSelectionDecodesIntoTheSharedTaskFilter() throws {
        let arguments: [String: Value] = [
            "filter": .object([
                "ids": .array([.string("id-1"), .string("id-2")]),
                "inboxOnly": .bool(true)
            ])
        ]
        let filter = try FocusRelayServer.decodeArgument(TaskFilter.self, from: arguments, key: "filter")
        #expect(filter?.ids == ["id-1", "id-2"])
        #expect(filter?.inboxOnly == true)
    }

    @Test func ordinaryFilterDecodingLeavesIDSelectionAbsent() throws {
        let arguments: [String: Value] = ["filter": .object(["inboxOnly": .bool(true)])]
        let filter = try FocusRelayServer.decodeArgument(TaskFilter.self, from: arguments, key: "filter")
        #expect(filter?.ids == nil, "existing list_tasks callers must be unaffected")
    }
}
