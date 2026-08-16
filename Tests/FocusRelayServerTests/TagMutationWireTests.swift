import MCP
import Testing
@testable import FocusRelayServer

@Suite("Tag mutation MCP wire contract")
struct TagMutationWireTests {
    @Test
    func schemaDistinguishesAddFromDestructiveReplacement() throws {
        let tools = FocusRelayServer.makeToolsForTesting()
        let editTasks = try #require(tools.first { $0.name == "edit_tasks" })
        guard case let .object(schema) = editTasks.inputSchema,
              case let .object(properties)? = schema["properties"],
              case let .object(taskPatch)? = properties["taskPatch"],
              case let .object(taskPatchProperties)? = taskPatch["properties"],
              case let .object(tags)? = taskPatchProperties["tags"],
              case let .string(tagsDescription)? = tags["description"],
              case let .object(tagProperties)? = tags["properties"],
              case let .object(add)? = tagProperties["add"],
              case let .string(addDescription)? = add["description"],
              case let .object(set)? = tagProperties["set"],
              case let .string(setDescription)? = set["description"] else {
            Issue.record("Expected edit_tasks.taskPatch.tags wire guidance")
            return
        }

        #expect(tagsDescription.contains("Use add for ordinary tagging"))
        #expect(tagsDescription.contains("set replaces all existing tags"))
        #expect(addDescription.contains("preserving every existing tag"))
        #expect(setDescription.contains("Replace all existing tags"))
        #expect(setDescription.contains("only when the user explicitly requests replacement"))
    }
}
