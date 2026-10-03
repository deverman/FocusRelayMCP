import Foundation
import MCP
import OmniFocusCore
import Testing
@testable import FocusRelayServer

@Suite("Partial Forecast MCP boundary")
struct ForecastWireTests {
    @Test func acceptsExplicitScopeAndRejectsAmbiguousExactForecast() throws {
        let schema = closingObjectSchemas(FocusRelayServer.makeTaskFilterSchema())
        try FocusRelayServer.validateToolArguments(toolName: "get_task_counts.filter",
            arguments: ["forecast": .string("past-and-today")], schema: schema)
        guard case let .object(object) = schema,
              case let .object(properties)? = object["properties"],
              case let .object(forecast)? = properties["forecast"] else {
            Issue.record("Missing Forecast schema"); return
        }
        #expect(forecast["enum"] == .array([.string("past-and-today")]))
        for invalid: Value in [.bool(true), .string("exact"), .string("today")] {
            #expect(throws: (any Error).self) {
                _ = try FocusRelayServer.decodeArgument(TaskFilter.self,
                    from: ["filter": .object(["forecast": invalid])], key: "filter")
            }
        }
        let filter = try #require(try FocusRelayServer.decodeArgument(TaskFilter.self,
            from: ["filter": .object(["forecast": .string("past-and-today"), "inboxOnly": .bool(true)])], key: "filter"))
        #expect(filter.forecast == .pastAndToday)
        #expect(filter.inboxOnly == true)
    }

    @Test func countLimitationsSurviveResponseEncoding() throws {
        let counts = TaskCounts(total: 8, completed: 0, available: 3, flagged: 2,
                                warnings: ["Partial task-only Forecast; calendar events excluded"])
        let decoded = try JSONDecoder().decode(TaskCounts.self, from: JSONEncoder().encode(counts))
        #expect(decoded.total == 8)
        #expect(decoded.warnings == counts.warnings)
    }
}
