import Foundation
import Testing
@testable import FocusRelayServer
import FocusRelayOutput
import FocusRelayVersion
import MCP
@testable import OmniFocusAutomation
import OmniFocusCore

@Test
func mcpArgumentBoundaryDecodesSparseTaskFieldPatches() throws {
    let flagged = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: ["taskPatch": .object(["flagged": .bool(true)])],
        key: "taskPatch"
    )
    #expect(flagged?.flagged == true)
    #expect(flagged?.clearDueDate == false)
    #expect(flagged?.clearDeferDate == false)

    let dueDate = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: ["taskPatch": .object(["dueDate": .string("2026-07-15T09:00:00Z")])],
        key: "taskPatch"
    )
    #expect(dueDate?.dueDate != nil)
}

@Test
func mcpArgumentBoundaryDecodesFractionalISO8601Dates() throws {
    let fractional = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: ["taskPatch": .object(["dueDate": .string("2026-07-15T09:00:00.000Z")])],
        key: "taskPatch"
    )
    let standard = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: ["taskPatch": .object(["dueDate": .string("2026-07-15T09:00:00Z")])],
        key: "taskPatch"
    )
    let fractionalDue = try #require(fractional?.dueDate)
    let standardDue = try #require(standard?.dueDate)
    #expect(abs(fractionalDue.timeIntervalSince(standardDue)) < 0.001)

    let filter = try FocusRelayServer.decodeArgument(
        TaskFilter.self,
        from: [
            "filter": .object([
                "completedAfter": .string("2026-01-31T00:00:00.123Z"),
                "completedBefore": .string("2026-02-01T00:00:00.456Z")
            ])
        ],
        key: "filter"
    )
    #expect(filter?.completedAfter != nil)
    #expect(filter?.completedBefore != nil)
}

@Test
func everyPublicSparseTaskPatchSurvivesMCPValueDecoding() throws {
    let cases: [[String: Value]] = [
        ["name": .string("Renamed")],
        ["note": .string("Replacement")],
        ["noteAppend": .string("Append")],
        ["flagged": .bool(false)],
        ["estimatedMinutes": .int(15)],
        ["dueDate": .string("2026-07-16T09:00:00Z")],
        ["clearDueDate": .bool(true)],
        ["deferDate": .string("2026-07-16T08:00:00Z")],
        ["clearDeferDate": .bool(true)],
        ["tags": .object(["clear": .bool(true)])]
    ]

    for value in cases {
        let decoded = try FocusRelayServer.decodeArgument(
            TaskPatchMutation.self,
            from: ["taskPatch": .object(value)],
            key: "taskPatch"
        )
        let patch = try #require(decoded)
        #expect(!patch.isEmpty)
        try patch.validate()
    }
}

@Test
func mcpArgumentBoundaryDecodesSparseProjectAndTagPatches() throws {
    let project = try FocusRelayServer.decodeArgument(
        ProjectPatchMutation.self,
        from: ["projectPatch": .object(["sequential": .bool(true)])],
        key: "projectPatch"
    )
    #expect(project?.sequential == true)
    #expect(project?.clearDueDate == false)
    #expect(project?.clearDeferDate == false)

    let task = try FocusRelayServer.decodeArgument(
        TaskPatchMutation.self,
        from: [
            "taskPatch": .object([
                "tags": .object(["add": .array([.string("tag-1")])])
            ])
        ],
        key: "taskPatch"
    )
    #expect(task?.tags == TagMutation(add: ["tag-1"]))
}

@Test
func everyPublicSparseProjectPatchSurvivesMCPValueDecoding() throws {
    let cases: [[String: Value]] = [
        ["name": .string("Renamed")],
        ["note": .string("Replacement")],
        ["noteAppend": .string("Append")],
        ["flagged": .bool(true)],
        ["dueDate": .string("2026-07-16T09:00:00Z")],
        ["clearDueDate": .bool(true)],
        ["deferDate": .string("2026-07-16T08:00:00Z")],
        ["clearDeferDate": .bool(true)],
        ["sequential": .bool(true)],
        ["reviewInterval": .object(["steps": .int(2), "unit": .string("weeks")])],
        ["reviewedNow": .bool(true)]
    ]

    for value in cases {
        let decoded = try FocusRelayServer.decodeArgument(
            ProjectPatchMutation.self,
            from: ["projectPatch": .object(value)],
            key: "projectPatch"
        )
        let patch = try #require(decoded)
        #expect(!patch.isEmpty)
        try patch.validate()
    }
}

@Test
func mcpServerReportsEmbeddedBuildVersion() {
    #expect(FocusRelayServer.version == FocusRelayBuildVersion.current)
}

@Test
func mcpLogOutputUsesStandardError() {
    switch FocusRelayServer.mcpLogOutputTarget {
    case .standardError:
        #expect(Bool(true))
    case .standardOutput:
        #expect(Bool(false))
    }
}

@Test
func publicMCPToolSurfaceExcludesInternalDiagnostics() {
    #expect(FocusRelayServer.publicToolNames == [
        "list_tasks",
        "get_task",
        "list_projects",
        "list_tags",
        "list_folders",
        "edit_tasks",
        "edit_projects",
        "get_task_counts",
        "get_project_counts"
    ])
    #expect(!FocusRelayServer.publicToolNames.contains("debug_inbox_probe"))
    #expect(!FocusRelayServer.publicToolNames.contains("debug_inbox_probe_alt"))
    #expect(!FocusRelayServer.publicToolNames.contains("bridge_health_check"))
}

@Test
func outputFieldCatalogAcceptsEverySupportedReadField() throws {
    for toolName in ["list_tasks", "get_task", "list_projects", "list_folders"] {
        let fields = try #require(OutputFieldCatalog.fields(for: toolName))
        try OutputFieldCatalog.validate(fields, for: toolName)
    }
}

@Test
func outputFieldCatalogRejectsUnknownAndMixedFieldsDeterministically() {
    #expect(throws: OutputFieldValidationError.self) {
        try OutputFieldCatalog.validate(["id", "notAField"], for: "list_tasks")
    }

    do {
        try OutputFieldCatalog.validate(
            ["id", "unknownSecond", "unknownFirst", "unknownSecond"],
            for: "list_projects"
        )
        Issue.record("Expected unsupported project fields to fail")
    } catch {
        #expect(
            error.localizedDescription
                .contains("list_projects.fields contains unsupported field(s): unknownSecond, unknownFirst")
        )
    }
}

@Test
func mutationToolCatalogIsExplicitlySeparatedFromReadTools() {
    #expect(FocusRelayServer.mutationToolNames == [
        "edit_tasks",
        "edit_projects"
    ])
    #expect(FocusRelayServer.mutationToolNames.isSubset(of: Set(FocusRelayServer.publicToolNames)))
    #expect(FocusRelayServer.publicToolNames.count - FocusRelayServer.mutationToolNames.count == 7)

    let annotations = FocusRelayServer.mutationToolAnnotations
    #expect(annotations.readOnlyHint == false)
    #expect(annotations.destructiveHint == true)
    #expect(annotations.idempotentHint == false)
    #expect(annotations.openWorldHint == false)
}

@Test
func processInboxPromptContractIsStableAndInstructionFirst() throws {
    let workflow = try #require(FocusRelayServer.workflow(named: "process_inbox"))
    #expect(FocusRelayServer.workflows == [workflow])
    #expect(workflow.title == "Process OmniFocus Inbox")
    #expect(workflow.description == "Safely process a bounded batch of unresolved OmniFocus inbox items.")

    let prompt = FocusRelayServer.processInboxPrompt
    #expect(prompt.name == workflow.name)
    #expect(prompt.title == workflow.title)
    #expect(prompt.arguments == nil)

    let result = try FocusRelayServer.prompt(named: prompt.name)
    #expect(result.description == workflow.description)
    #expect(result.messages.count == 1)
    #expect(result.messages[0].role == .user)

    guard case .text(let text) = result.messages[0].content else {
        Issue.record("process_inbox must return one instruction-only text message")
        return
    }
    #expect(text == workflow.instructions)
    #expect(text.contains("filter.inboxOnly=true"))
    #expect(text.contains(#"filter.inboxView="remaining""#))
    #expect(text.contains("10–20 item decision batch"))
    #expect(text.contains("Initially request only id and name"))
    #expect(text.contains("before following nextCursor"))
    #expect(text.contains("Ambiguity is not evidence that an item should be dropped"))
    #expect(text.contains("Before recommending any disposition for an ambiguous capture"))
    #expect(text.contains("desired outcome"))
    #expect(text.contains("physical, visible next action"))
    #expect(text.contains("under two minutes"))
    #expect(text.contains("Waiting For"))
    #expect(text.contains("Someday/Maybe or reference"))
    #expect(text.contains("Reserve due dates for genuine deadlines"))
    #expect(text.contains("does not manage calendar events"))
    #expect(text.contains("Do not impose a project or tag taxonomy"))
    #expect(text.contains("filter.ids"))
    #expect(text.contains("same inboxOnly=true and inboxView=\"remaining\" scope"))
    #expect(text.contains("list_projects.searches and list_tags.searches"))
    #expect(text.contains("Use FocusRelay tools only for this workflow"))
    #expect(text.contains("edit_tasks operation=move with verify=true"))
    #expect(text.contains("instead of switching tools or retrying by name"))
    #expect(text.contains("Keep each displayed number bound to its task ID when regrouping"))
    #expect(text.contains("grouped by shared action or destination"))
    #expect(text.contains("obtain explicit approval"))
    #expect(text.contains("fewest supported calls"))
    #expect(text.contains("Never run mutation calls concurrently"))
    #expect(text.contains("Preview, apply, and verify one mutation group"))
    #expect(text.contains("Do not launch a large parallel fan-out"))
    #expect(text.contains("Recount after the approved mutation groups finish"))
    #expect(text.contains("cannot yet create tasks, subtasks, or projects"))
    #expect(!text.contains("taskID"))
    #expect(!text.contains("projectID"))

    #expect(throws: MCPError.self) {
        try FocusRelayServer.prompt(named: "unknown_prompt")
    }
}

@Test
func promptProtocolAdvertisesListsAndRetrievesWithoutChangingTools() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let executable = packageRoot.appendingPathComponent(".build/debug/focusrelay")
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))

    let process = Process()
    let standardInput = Pipe()
    let standardOutput = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", "alarm 10; exec @ARGV", executable.path, "serve"]
    process.currentDirectoryURL = packageRoot
    process.standardInput = standardInput
    process.standardOutput = standardOutput
    process.standardError = Pipe()
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
        }
    }

    let requests = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"prompt-test","version":"1"}}}"#,
        #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"prompts/list"}"#,
        #"{"jsonrpc":"2.0","id":4,"method":"prompts/list","params":{}}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"prompts/get","params":{"name":"process_inbox"}}"#,
        #"{"jsonrpc":"2.0","id":6,"method":"prompts/get","params":{"name":"unknown_prompt"}}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/list","params":{}}"#
    ].joined(separator: "\n") + "\n"
    try standardInput.fileHandleForWriting.write(contentsOf: Data(requests.utf8))

    var responses: [Int: [String: Any]] = [:]
    var buffered = Data()
    while responses.count < 7 {
        let chunk = standardOutput.fileHandleForReading.availableData
        guard !chunk.isEmpty else {
            Issue.record("MCP server exited before returning prompt protocol responses")
            break
        }
        buffered.append(chunk)
        while let newline = buffered.firstIndex(of: 0x0A) {
            let line = buffered[..<newline]
            buffered.removeSubrange(...newline)
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? Int else {
                continue
            }
            responses[id] = object
        }
    }

    let initialize = try #require(responses[1]?["result"] as? [String: Any])
    let capabilities = try #require(initialize["capabilities"] as? [String: Any])
    let promptsCapability = try #require(capabilities["prompts"] as? [String: Any])
    #expect(promptsCapability["listChanged"] as? Bool == false)

    let omittedList = try #require(responses[3]?["result"] as? [String: Any])
    let emptyList = try #require(responses[4]?["result"] as? [String: Any])
    #expect(NSDictionary(dictionary: omittedList).isEqual(to: emptyList))
    let prompts = try #require(omittedList["prompts"] as? [[String: Any]])
    #expect(prompts.count == 1)
    #expect(prompts[0]["name"] as? String == "process_inbox")
    #expect(prompts[0]["arguments"] == nil)
    #expect(omittedList["nextCursor"] == nil)

    let getResult = try #require(responses[5]?["result"] as? [String: Any])
    let messages = try #require(getResult["messages"] as? [[String: Any]])
    #expect(messages.count == 1)
    #expect(messages[0]["role"] as? String == "user")
    let content = try #require(messages[0]["content"] as? [String: Any])
    #expect(content["type"] as? String == "text")
    #expect(content["text"] as? String == FocusRelayServer.workflow(named: "process_inbox")?.instructions)

    let unknownError = try #require(responses[6]?["error"] as? [String: Any])
    #expect((unknownError["message"] as? String)?.contains("Unknown prompt: unknown_prompt") == true)

    let toolsBefore = try #require(
        (responses[2]?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
    )
    let toolsAfter = try #require(
        (responses[7]?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
    )
    #expect(toolsBefore.compactMap { $0["name"] as? String } == FocusRelayServer.publicToolNames)
    #expect(NSArray(array: toolsBefore).isEqual(to: toolsAfter))
}

@Test
func productionToolsListMatchesGoldenPublicCatalog() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let executable = packageRoot.appendingPathComponent(".build/debug/focusrelay")
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))

    let process = Process()
    let standardInput = Pipe()
    let standardOutput = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", "alarm 10; exec @ARGV", executable.path, "serve"]
    process.currentDirectoryURL = packageRoot
    process.standardInput = standardInput
    process.standardOutput = standardOutput
    process.standardError = Pipe()
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
        }
    }

    let requests = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"catalog-test","version":"1"}}}"#,
        #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#
    ].joined(separator: "\n") + "\n"
    try standardInput.fileHandleForWriting.write(contentsOf: Data(requests.utf8))

    var buffered = Data()
    var response: [String: Any]?
    while response == nil {
        let chunk = standardOutput.fileHandleForReading.availableData
        guard !chunk.isEmpty else {
            Issue.record("MCP server exited before returning tools/list")
            break
        }
        buffered.append(chunk)
        while let newline = buffered.firstIndex(of: 0x0A) {
            let line = buffered[..<newline]
            buffered.removeSubrange(...newline)
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["id"] as? Int == 2 else {
                continue
            }
            response = object
            break
        }
    }

    let result = try #require(response?["result"] as? [String: Any])
    let tools = try #require(result["tools"] as? [[String: Any]])
    #expect(tools.compactMap { $0["name"] as? String } == FocusRelayServer.publicToolNames)

    for tool in tools {
        let schema = try #require(tool["inputSchema"] as? [String: Any])
        expectClosedObjectSchemas(schema)

        if let name = tool["name"] as? String,
           let expectedFields = OutputFieldCatalog.fields(for: name) {
            let properties = try #require(schema["properties"] as? [String: Any])
            let fields = try #require(properties["fields"] as? [String: Any])
            let items = try #require(fields["items"] as? [String: Any])
            #expect(items["enum"] as? [String] == expectedFields)
        }
    }

    for name in FocusRelayServer.mutationToolNames {
        let tool = try #require(tools.first { $0["name"] as? String == name })
        let description = try #require(tool["description"] as? String)
        #expect(description.contains("Run edit_tasks and edit_projects calls sequentially"))
        #expect(description.contains("wait for each mutation response"))
        #expect(description.contains("bridge_busy or bridge_queue_timeout"))
        #expect(description.contains("wait at least retryAfterMilliseconds"))
        #expect(description.contains("retrying only that request"))
        #expect(description.contains("Do not automatically retry any other mutation failure"))

        let annotations = try #require(tool["annotations"] as? [String: Any])
        #expect(annotations["readOnlyHint"] as? Bool == false)
        #expect(annotations["destructiveHint"] as? Bool == true)
        #expect(annotations["idempotentHint"] as? Bool == false)
        #expect(annotations["openWorldHint"] as? Bool == false)

        let schema = try #require(tool["inputSchema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect((schema["oneOf"] as? [[String: Any]])?.isEmpty == false)
    }
}

@Test
func stdioServerExitsAfterInitializedClientClosesInput() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let executable = packageRoot.appendingPathComponent(".build/debug/focusrelay")
    #expect(FileManager.default.isExecutableFile(atPath: executable.path))

    for _ in 0..<3 {
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        process.executableURL = executable
        process.arguments = ["serve"]
        process.currentDirectoryURL = packageRoot
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = Pipe()
        try process.run()
        defer {
            if process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let initialize =
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"stdio-lifecycle-test","version":"1"}}}"#
            + "\n"
        try standardInput.fileHandleForWriting.write(contentsOf: Data(initialize.utf8))

        var buffered = Data()
        var initialized = false
        while !initialized {
            let chunk = standardOutput.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
                Issue.record("MCP server exited before returning initialize")
                break
            }
            buffered.append(chunk)
            while let newline = buffered.firstIndex(of: 0x0A) {
                let line = buffered[..<newline]
                buffered.removeSubrange(...newline)
                guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["id"] as? Int == 1 else {
                    continue
                }
                initialized = object["result"] != nil
                break
            }
        }
        try #require(initialized)

        try standardInput.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }

        #expect(!process.isRunning, "FocusRelay must exit when its initialized stdio client closes input")
        if !process.isRunning {
            #expect(process.terminationReason == .exit)
            #expect(process.terminationStatus == 0)
        }
    }
}

@Test
func mcpWireRejectsUnknownTopLevelAndNestedArgumentsBeforeDispatch() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let executable = packageRoot.appendingPathComponent(".build/debug/focusrelay")

    let process = Process()
    let standardInput = Pipe()
    let standardOutput = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
    process.arguments = ["-e", "alarm 10; exec @ARGV", executable.path, "serve"]
    process.currentDirectoryURL = packageRoot
    process.standardInput = standardInput
    process.standardOutput = standardOutput
    process.standardError = Pipe()
    try process.run()
    defer {
        if process.isRunning {
            process.terminate()
        }
    }

    let reviewIdentity = try QueryBoundCursor.queryIdentity(
        tool: "list_projects",
        input: ProjectFilter(statusFilter: "active", reviewPerspective: true)
    )
    let reviewCursor = try #require(
        QueryBoundCursor.publicPage(
            from: Page<ProjectItem>(
                items: [],
                nextCursor: "100",
                returnedCount: 100
            ),
            identity: reviewIdentity
        ).nextCursor
    )

    let requests = [
        #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"validation-test","version":"1"}}}"#,
        #"{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"list_tasks","arguments":{"search":"drop test"}}}"#,
        #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_projects","arguments":{"query":"drop test","statusFilter":"all"}}}"#,
        #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_tasks","arguments":{"filter":{"unexpected":true}}}}"#,
        #"{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"list_tasks","arguments":{"page":{"offset":"50"}}}}"#,
        #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"edit_tasks","arguments":{"operation":"set_completion","targetIDs":["real-task"],"completion":{"state":"completed","unexpected":true}}}}"#,
        #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"list_projects","arguments":{"statusFilter":"active","page":{"cursor":"100"}}}}"#,
        #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"list_projects","arguments":{"statusFilter":"active","reviewPerspective":false,"page":{"cursor":"\#(reviewCursor)"}}}}"#,
        #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"list_tasks","arguments":{"fields":["id","notAField"]}}}"#,
        #"{"jsonrpc":"2.0","id":10,"method":"tools/call","params":{"name":"get_task","arguments":{"id":"unused","fields":["unknownTaskField"]}}}"#,
        #"{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"list_projects","arguments":{"fields":["status","unknownProjectField"]}}}"#,
        #"{"jsonrpc":"2.0","id":12,"method":"tools/call","params":{"name":"list_folders","arguments":{"fields":["id","unknownFolderField"]}}}"#,
        #"{"jsonrpc":"2.0","id":13,"method":"tools/call","params":{"name":"list_tags","arguments":{"fields":["id","unknownTagField"]}}}"#,
        #"{"jsonrpc":"2.0","id":14,"method":"tools/call","params":{"name":"list_tags","arguments":{"search":"   ","fields":["id","name","path"]}}}"#
    ].joined(separator: "\n") + "\n"
    try standardInput.fileHandleForWriting.write(contentsOf: Data(requests.utf8))

    var responses: [Int: [String: Any]] = [:]
    var buffered = Data()
    while responses.count < 14 {
        let chunk = standardOutput.fileHandleForReading.availableData
        guard !chunk.isEmpty else {
            Issue.record("MCP server exited before returning argument-validation responses")
            break
        }
        buffered.append(chunk)
        while let newline = buffered.firstIndex(of: 0x0A) {
            let line = buffered[..<newline]
            buffered.removeSubrange(...newline)
            guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? Int else {
                continue
            }
            responses[id] = object
        }
    }

    #expect(toolErrorText(responses[2]).contains("list_tasks.search is unsupported; use list_tasks.filter.search"))
    #expect(toolErrorText(responses[3]).contains("list_projects.query is unsupported"))
    #expect(toolErrorText(responses[4]).contains("list_tasks.filter.unexpected is unsupported"))
    #expect(toolErrorText(responses[5]).contains("list_tasks.page.offset is unsupported"))
    #expect(toolErrorText(responses[6]).contains("edit_tasks.completion.unexpected is unsupported"))
    #expect(toolErrorText(responses[7]).contains("Pagination cursor is malformed or unsupported"))
    #expect(toolErrorText(responses[8]).contains("Pagination cursor is for a different query"))
    #expect(toolErrorText(responses[9]).contains("list_tasks.fields contains unsupported field(s): notAField"))
    #expect(toolErrorText(responses[10]).contains("get_task.fields contains unsupported field(s): unknownTaskField"))
    #expect(toolErrorText(responses[11]).contains("list_projects.fields contains unsupported field(s): unknownProjectField"))
    #expect(toolErrorText(responses[12]).contains("list_folders.fields contains unsupported field(s): unknownFolderField"))
    #expect(toolErrorText(responses[13]).contains("list_tags.fields contains unsupported field(s): unknownTagField"))
    #expect(toolErrorText(responses[14]).contains("Tag search must contain at least one non-whitespace character"))
}

@Test
func editToolSchemasRequireExactlyOneMatchingPayload() throws {
    let common: [String: Value] = [
        "operation": .object(["type": .string("string")]),
        "targetIDs": .object(["type": .string("array")])
    ]
    let taskSchema = FocusRelayServer.makeTaskEditSchema(properties: common.merging([
        "taskPatch": .object(["type": .string("object")]),
        "taskStatus": .object(["type": .string("object")]),
        "completion": .object(["type": .string("object")]),
        "move": .object(["type": .string("object")])
    ]) { _, new in new })
    let projectSchema = FocusRelayServer.makeProjectEditSchema(properties: common.merging([
        "projectPatch": .object(["type": .string("object")]),
        "projectStatus": .object(["type": .string("object")]),
        "completion": .object(["type": .string("object")]),
        "move": .object(["type": .string("object")])
    ]) { _, new in new })

    try expectDiscriminatedSchema(
        taskSchema,
        operationPayloads: [
            "update": "taskPatch",
            "set_status": "taskStatus",
            "set_completion": "completion",
            "move": "move"
        ]
    )
    try expectDiscriminatedSchema(
        projectSchema,
        operationPayloads: [
            "update": "projectPatch",
            "set_status": "projectStatus",
            "set_completion": "completion",
            "move": "move"
        ]
    )
}

private func expectClosedObjectSchemas(_ schema: [String: Any]) {
    if schema["type"] as? String == "object", schema["properties"] != nil {
        #expect(schema["additionalProperties"] as? Bool == false)
    }
    if let properties = schema["properties"] as? [String: Any] {
        for child in properties.values {
            if let childSchema = child as? [String: Any] {
                expectClosedObjectSchemas(childSchema)
            }
        }
    }
    if let items = schema["items"] as? [String: Any] {
        expectClosedObjectSchemas(items)
    }
}

private func toolErrorText(_ response: [String: Any]?) -> String {
    guard let result = response?["result"] as? [String: Any],
          result["isError"] as? Bool == true,
          let content = result["content"] as? [[String: Any]],
          let text = content.first?["text"] as? String else {
        return ""
    }
    return text
}

@Test
func bridgeAdmissionErrorsEncodeAsStructuredMCPToolFailures() throws {
    let cases: [(BridgeAdmissionError, String)] = [
        (.busy(retryAfterMilliseconds: 6_750), "bridge_busy"),
        (.queueTimeout(retryAfterMilliseconds: 6_750), "bridge_queue_timeout")
    ]

    for (error, expectedCode) in cases {
        let result = FocusRelayServer.bridgeAdmissionErrorResult(error)
        #expect(result.isError == true)

        guard case .object(let structured) = result.structuredContent else {
            Issue.record("Expected structured Bridge admission content")
            continue
        }
        #expect(structured["code"] == .string(expectedCode))
        #expect(structured["retryable"] == .bool(true))
        #expect(structured["retryAfterMilliseconds"] == .int(6_750))

        let encoded = try JSONEncoder().encode(result)
        let wire = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(wire["isError"] as? Bool == true)
        let wireStructured = try #require(wire["structuredContent"] as? [String: Any])
        #expect(wireStructured["code"] as? String == expectedCode)
        #expect(wireStructured["retryable"] as? Bool == true)
        #expect(wireStructured["retryAfterMilliseconds"] as? Int == 6_750)

        let wireText = String(decoding: encoded, as: UTF8.self)
        #expect(!wireText.contains("targetIDs"))
        #expect(!wireText.contains("arguments"))
        #expect(!wireText.contains("/Users/"))
    }
}

@Test
func taskEditWireArgumentsDispatchEveryOperation() throws {
    let update = try FocusRelayServer.decodeTaskEditRequest(from: [
        "operation": .string("update"),
        "targetIDs": .array([.string("task-1")]),
        "taskPatch": .object(["flagged": .bool(true)])
    ])
    #expect(update.operation.kind == .updateTasks)
    #expect(update.operation.taskPatch?.flagged == true)

    let status = try FocusRelayServer.decodeTaskEditRequest(from: [
        "operation": .string("set_status"),
        "targetIDs": .array([.string("task-1")]),
        "taskStatus": .object([
            "status": .string("dropped"),
            "recurrenceScope": .string("series")
        ])
    ])
    #expect(status.operation.kind == .setTasksStatus)
    #expect(status.operation.taskStatus == TaskStatusMutation(status: .dropped, recurrenceScope: .series))

    let completion = try FocusRelayServer.decodeTaskEditRequest(from: [
        "operation": .string("set_completion"),
        "targetIDs": .array([.string("task-1")]),
        "completion": .object(["state": .string("completed")])
    ])
    #expect(completion.operation.kind == .setTasksCompletion)

    let move = try FocusRelayServer.decodeTaskEditRequest(from: [
        "operation": .string("move"),
        "targetIDs": .array([.string("task-1")]),
        "move": .object(["destinationKind": .string("inbox")])
    ])
    #expect(move.operation.kind == .moveTasks)
}

@Test
func projectEditWireArgumentsDispatchEveryOperation() throws {
    let cases: [(String, String, Value, MutationOperationKind)] = [
        ("update", "projectPatch", .object(["flagged": .bool(true)]), .updateProjects),
        ("set_status", "projectStatus", .object(["status": .string("on_hold")]), .setProjectsStatus),
        ("set_completion", "completion", .object(["state": .string("completed")]), .setProjectsCompletion),
        ("move", "move", .object(["destinationKind": .string("folder")]), .moveProjects)
    ]

    for (operation, payloadName, payload, expectedKind) in cases {
        let request = try FocusRelayServer.decodeProjectEditRequest(from: [
            "operation": .string(operation),
            "targetIDs": .array([.string("project-1")]),
            payloadName: payload
        ])
        #expect(request.operation.kind == expectedKind)
    }
}

@Test
func projectReviewedNowWireArgumentsUseUpdatePatch() throws {
    let request = try FocusRelayServer.decodeProjectEditRequest(from: [
        "operation": .string("update"),
        "targetIDs": .array([.string("project-1"), .string("project-2")]),
        "projectPatch": .object(["reviewedNow": .bool(true)]),
        "previewOnly": .bool(true),
        "verify": .bool(true),
        "returnFields": .array([.string("id"), .string("lastReviewDate"), .string("nextReviewDate")])
    ])

    #expect(request.operation.projectPatch?.reviewedNow == true)
    #expect(request.previewOnly)
    #expect(request.verify)
}

@Test
func editWireArgumentsRejectMissingMismatchedAndContradictoryPayloads() {
    #expect(throws: MutationValidationError.self) {
        try FocusRelayServer.decodeTaskEditRequest(from: [
            "operation": .string("update"),
            "targetIDs": .array([.string("task-1")])
        ])
    }
    #expect(throws: MutationValidationError.self) {
        try FocusRelayServer.decodeTaskEditRequest(from: [
            "operation": .string("move"),
            "targetIDs": .array([.string("task-1")]),
            "completion": .object(["state": .string("completed")])
        ])
    }
    #expect(throws: MutationValidationError.self) {
        try FocusRelayServer.decodeProjectEditRequest(from: [
            "operation": .string("set_status"),
            "targetIDs": .array([.string("project-1")]),
            "projectStatus": .object(["status": .string("active")]),
            "completion": .object(["state": .string("active")])
        ])
    }
}

@Test
func taskEditStatusRequiresTaskStatusPayload() {
    #expect(throws: MutationValidationError.self) {
        try FocusRelayServer.decodeTaskEditRequest(from: [
            "operation": .string("set_status"),
            "targetIDs": .array([.string("task-1")]),
            "projectStatus": .object(["status": .string("dropped")])
        ])
    }
}

private func expectDiscriminatedSchema(
    _ value: Value,
    operationPayloads: [String: String]
) throws {
    guard case let .object(schema) = value else {
        Issue.record("Expected an object schema")
        return
    }
    #expect(schema["additionalProperties"] == .bool(false))
    #expect(schema["required"] == .array([.string("operation"), .string("targetIDs")]))

    guard case let .array(alternatives)? = schema["oneOf"] else {
        Issue.record("Expected oneOf operation alternatives")
        return
    }
    #expect(alternatives.count == operationPayloads.count)

    for (operation, payload) in operationPayloads {
        let alternative = try #require(alternatives.first { value in
            guard case let .object(branch) = value,
                  case let .object(properties)? = branch["properties"],
                  case let .object(operationSchema)? = properties["operation"] else {
                return false
            }
            return operationSchema["const"] == .string(operation)
        })
        guard case let .object(branch) = alternative else { continue }
        #expect(branch["required"] == .array([.string(payload)]))

        guard case let .object(notSchema)? = branch["not"],
              case let .array(forbidden)? = notSchema["anyOf"] else {
            Issue.record("Expected forbidden payload alternatives for \(operation)")
            continue
        }
        #expect(forbidden.count == operationPayloads.count - 1)
        #expect(!forbidden.contains(.object(["required": .array([.string(payload)])])))
    }
}

@Test
func projectDefaultsIncludeStatusWhenCountsOrHistoricalStatusesNeedInterpretation() {
    #expect(FocusRelayServer.resolvedProjectFields(
        requestedFields: [],
        statusFilter: "active",
        includeTaskCounts: false
    ) == ["id", "name"])

    #expect(FocusRelayServer.resolvedProjectFields(
        requestedFields: [],
        statusFilter: "all",
        includeTaskCounts: false
    ) == ["id", "name", "status"])

    #expect(FocusRelayServer.resolvedProjectFields(
        requestedFields: [],
        statusFilter: "active",
        includeTaskCounts: true
    ) == ["id", "name", "status"])

    #expect(FocusRelayServer.resolvedProjectFields(
        requestedFields: ["id", "name", "completionDate"],
        statusFilter: "all",
        includeTaskCounts: true
    ) == ["id", "name", "completionDate"])
}

@Test
func tagDefaultsPreserveExistingShapeAndExplicitFieldsStayCompact() {
    #expect(FocusRelayServer.resolvedTagFields(
        requestedFields: [],
        statusFilter: "active",
        includeTaskCounts: false
    ) == ["id", "name", "status"])

    #expect(FocusRelayServer.resolvedTagFields(
        requestedFields: [],
        statusFilter: "all",
        includeTaskCounts: false
    ) == ["id", "name", "status"])

    #expect(FocusRelayServer.resolvedTagFields(
        requestedFields: [],
        statusFilter: "active",
        includeTaskCounts: true
    ) == ["id", "name", "status"])

    #expect(FocusRelayServer.resolvedTagFields(
        requestedFields: ["id", "path"],
        statusFilter: "all",
        includeTaskCounts: true
    ) == ["id", "path"])
}

@Test
func projectToolDescriptionGuardsCompletionAndStalledRecommendations() {
    let description = FocusRelayServer.listProjectsToolDescription
    #expect(description.contains("start with statusFilter='active'"))
    #expect(description.contains("remainingTasks=0 is not automatically a completion candidate"))
    #expect(description.contains("totalTasks=0 means the project is empty or unplanned"))
    #expect(description.contains("If all child tasks are dropped, treat it as a drop/review candidate"))
    #expect(description.contains("availableTasks=0 does not mean a project is stalled"))
    #expect(description.contains("default statusFilter='active' is ignored"))
    #expect(description.contains("statusFilter remains active inside Review queries"))
    #expect(description.contains("trimmed, literal, case-insensitive substring"))
    #expect(description.contains("Follow nextCursor"))
    #expect(description.contains("inclusive"))
}

@Test
func taskToolDescriptionGuidesBoundedInboxProcessing() {
    let description = FocusRelayServer.listTasksToolDescription
    #expect(description.contains("inboxView='remaining'"))
    #expect(description.contains("every unresolved capture"))
    #expect(description.contains("inboxView='available'"))
    #expect(description.contains("inboxView='everything' only"))
    #expect(description.contains("includes completed and dropped records"))
    #expect(description.contains("bounded page of 10-20 items"))
    #expect(description.contains("use get_task_counts instead"))
    #expect(description.contains("filter.includeTotalCount=true inside the filter object"))
}

@Test
func sharedTaskFilterSchemaCoversCompleteModelSurface() {
    let expectedPropertyNames: Set<String> = [
        "completed",
        "flagged",
        "availableOnly",
        "inboxView",
        "project",
        "tags",
        "dueBefore",
        "dueAfter",
        "deferBefore",
        "deferAfter",
        "plannedBefore",
        "plannedAfter",
        "completedBefore",
        "completedAfter",
        "search",
        "inboxOnly",
        "projectView",
        "maxEstimatedMinutes",
        "minEstimatedMinutes",
        "includeTotalCount"
    ]

    #expect(FocusRelayServer.taskFilterPropertyNames == expectedPropertyNames)

    guard case let .object(schema) = FocusRelayServer.makeTaskFilterSchema(),
          case let .object(properties)? = schema["properties"] else {
        Issue.record("Expected an object task-filter schema with object properties")
        return
    }

    #expect(Set(properties.keys) == expectedPropertyNames)

    guard case let .object(flaggedSchema)? = properties["flagged"],
          case let .string(flaggedDescription)? = flaggedSchema["description"] else {
        Issue.record("Expected a flagged filter description")
        return
    }
    #expect(flaggedDescription.contains("effective flagged state"))
    #expect(flaggedDescription.contains("inherited"))

    guard case let .object(inboxViewSchema)? = properties["inboxView"],
          case let .string(inboxViewDescription)? = inboxViewSchema["description"],
          case let .object(inboxOnlySchema)? = properties["inboxOnly"],
          case let .string(inboxOnlyDescription)? = inboxOnlySchema["description"] else {
        Issue.record("Expected inbox view and scope descriptions")
        return
    }
    #expect(inboxViewSchema["default"] == .string("available"))
    #expect(inboxViewDescription.contains("remaining for inbox processing"))
    #expect(inboxViewDescription.contains("everything only for explicitly requested history"))
    #expect(inboxViewDescription.contains("includes completed and dropped records"))
    #expect(inboxOnlyDescription.contains("inboxView=remaining"))
    guard case let .string(filterDescription)? = schema["description"],
          case let .object(includeTotalCountSchema)? = properties["includeTotalCount"],
          case let .string(includeTotalCountDescription)? = includeTotalCountSchema["description"] else {
        Issue.record("Expected filter placement guidance")
        return
    }
    #expect(filterDescription.contains("must be nested inside this filter object"))
    #expect(includeTotalCountDescription.contains("not a top-level tool argument"))

    guard case let .object(maximumEstimate)? = properties["maxEstimatedMinutes"],
          case let .object(minimumEstimate)? = properties["minEstimatedMinutes"] else {
        Issue.record("Expected estimate filter schemas")
        return
    }
    #expect(maximumEstimate["minimum"] == .int(0))
    #expect(minimumEstimate["minimum"] == .int(0))

    guard case let .object(includeTotalCount)? = properties["includeTotalCount"] else {
        Issue.record("Expected includeTotalCount filter schema")
        return
    }
    #expect(includeTotalCount["default"] == .bool(false))
}

@Test
func pageRequestValidationRejectsNonPositiveLimits() throws {
    #expect(throws: (any Error).self) {
        try FocusRelayServer.decodePageRequest(
            from: ["page": .object(["limit": .int(-5)])],
            defaultLimit: 50
        )
    }
    #expect(throws: (any Error).self) {
        try FocusRelayServer.decodePageRequest(
            from: ["page": .object(["limit": .int(0)])],
            defaultLimit: 50
        )
    }
}

@Test
func pageRequestValidationAcceptsOmittedAndPositiveLimits() throws {
    let defaulted = try FocusRelayServer.decodePageRequest(from: [:], defaultLimit: 150)
    #expect(defaulted.limit == 150)
    #expect(defaulted.cursor == nil)

    let explicit = try FocusRelayServer.decodePageRequest(
        from: ["page": .object(["limit": .int(25), "cursor": .string("50")])],
        defaultLimit: 150
    )
    #expect(explicit.limit == 25)
    #expect(explicit.cursor == "50")
}

@Test
func pageRequestAppliesToolDefaultLimitWhenCursorSentAlone() throws {
    let taskPage = try FocusRelayServer.decodePageRequest(
        from: ["page": .object(["cursor": .string("50")])],
        defaultLimit: 50
    )
    #expect(taskPage.limit == 50)
    #expect(taskPage.cursor == "50")

    let projectPage = try FocusRelayServer.decodePageRequest(
        from: ["page": .object(["cursor": .string("150")])],
        defaultLimit: 150
    )
    #expect(projectPage.limit == 150)
    #expect(projectPage.cursor == "150")
}

@Test
func cursorOnlyPagesApplyDefaultsAtMCPWireBoundary() throws {
    let cases = [
        (tool: "list_tasks", cursor: "50", expectedLimit: 50),
        (tool: "list_projects", cursor: "150", expectedLimit: 150)
    ]

    for testCase in cases {
        let data = Data(
            """
            {
              "jsonrpc": "2.0",
              "id": 1,
              "method": "tools/call",
              "params": {
                "name": "\(testCase.tool)",
                "arguments": {"page": {"cursor": "\(testCase.cursor)"}}
              }
            }
            """.utf8
        )
        let request = try JSONDecoder().decode(Request<CallTool>.self, from: data)
        let page = try FocusRelayServer.decodePageRequest(from: request.params)

        #expect(request.method == CallTool.name)
        #expect(page.limit == testCase.expectedLimit)
        #expect(page.cursor == testCase.cursor)
    }
}

@Test
func compoundTaskPaginationSurvivesSeparateMCPArgumentDecoding() throws {
    let firstData = Data(
        #"""
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "tools/call",
          "params": {
            "name": "list_tasks",
            "arguments": {
              "filter": {
                "project": "project-fixture",
                "completed": false,
                "availableOnly": false,
                "includeTotalCount": true
              },
              "fields": ["id", "name", "note"],
              "page": {"limit": 50}
            }
          }
        }
        """#.utf8
    )
    let firstRequest = try JSONDecoder().decode(Request<CallTool>.self, from: firstData)
    let decodedFirstFilter = try FocusRelayServer.decodeArgument(
        TaskFilter.self,
        from: firstRequest.params.arguments,
        key: "filter"
    )
    let firstFilter = try #require(decodedFirstFilter)
    let firstIdentity = try QueryBoundCursor.taskIdentity(for: firstFilter)
    let cursor = try #require(
        QueryBoundCursor.publicPage(
            from: Page<TaskItem>(
                items: [],
                nextCursor: "50",
                returnedCount: 50,
                totalCount: 69
            ),
            identity: firstIdentity
        ).nextCursor
    )

    let continuationData = Data(
        #"""
        {
          "jsonrpc": "2.0",
          "id": 2,
          "method": "tools/call",
          "params": {
            "name": "list_tasks",
            "arguments": {
              "page": {"cursor": "\#(cursor)", "limit": 20},
              "fields": ["note", "name", "id"],
              "filter": {
                "includeTotalCount": true,
                "availableOnly": false,
                "completed": false,
                "project": "project-fixture"
              }
            }
          }
        }
        """#.utf8
    )
    let continuationRequest = try JSONDecoder().decode(
        Request<CallTool>.self,
        from: continuationData
    )
    let decodedContinuationFilter = try FocusRelayServer.decodeArgument(
        TaskFilter.self,
        from: continuationRequest.params.arguments,
        key: "filter"
    )
    let continuationFilter = try #require(decodedContinuationFilter)
    let continuationIdentity = try QueryBoundCursor.taskIdentity(
        for: continuationFilter
    )
    let continuationPage = try FocusRelayServer.decodePageRequest(
        from: continuationRequest.params
    )
    let bridgePage = try QueryBoundCursor.bridgePage(
        from: continuationPage,
        identity: continuationIdentity
    )

    #expect(firstIdentity == continuationIdentity)
    #expect(bridgePage.limit == 20)
    #expect(bridgePage.cursor == "50")
}

@Test
func reviewPerspectiveAndStatusFilterDecodeTogetherAtMCPWireBoundary() throws {
    let data = Data(
        #"""
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "tools/call",
          "params": {
            "name": "list_projects",
            "arguments": {
              "statusFilter": "onHold",
              "reviewPerspective": true
            }
          }
        }
        """#.utf8
    )
    let request = try JSONDecoder().decode(Request<CallTool>.self, from: data)

    #expect(
        try FocusRelayServer.decodeArgument(
            String.self,
            from: request.params.arguments,
            key: "statusFilter"
        ) == "onHold"
    )
    #expect(
        try FocusRelayServer.decodeArgument(
            Bool.self,
            from: request.params.arguments,
            key: "reviewPerspective"
        ) == true
    )
}

@Test
func projectSearchDecodesAtMCPWireBoundary() throws {
    let data = Data(
        #"""
        {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "tools/call",
          "params": {
            "name": "list_projects",
            "arguments": {
              "search": "drop test",
              "statusFilter": "all"
            }
          }
        }
        """#.utf8
    )
    let request = try JSONDecoder().decode(Request<CallTool>.self, from: data)

    #expect(
        try FocusRelayServer.decodeArgument(
            String.self,
            from: request.params.arguments,
            key: "search"
        ) == "drop test"
    )
    #expect(
        try FocusRelayServer.decodeArgument(
            String.self,
            from: request.params.arguments,
            key: "statusFilter"
        ) == "all"
    )
}
