import Foundation
import Logging
import MCP
import OmniFocusCore
import Testing
@testable import FocusRelayServer

@Suite("Task creation MCP wire boundary")
struct TaskCreationWireTests {
    @Test(arguments: ["__proto__", "__destination__"])
    func specialButValidClientIDsReachSharedService(identifier: String) async throws {
        try await withCreationClient { client, service in
            let call: RequestContext<CallTool.Result> = try await client.callTool(name: "add_tasks", arguments: [
                "tasks": .array([.object(["clientID": .string(identifier), "name": .string("Synthetic")])])
            ])
            #expect(try await call.value.isError != true)
            #expect(await service.requests.first?.tasks.first?.clientID == identifier)
        }
    }

    @Test func sparseApplyAndExplicitPreviewReachSharedService() async throws {
        try await withCreationClient { client, service in
            let arguments: [String: Value] = [
                "tasks": .array([.object(["clientID": .string("one"), "name": .string("Synthetic")])])
            ]
            let call: RequestContext<CallTool.Result> = try await client.callTool(name: "add_tasks", arguments: arguments)
            let response = try await call.value
            #expect(response.isError != true)
            let recorded = await service.requests
            #expect(recorded.count == 1)
            #expect(recorded.first?.previewOnly == false)
            #expect(recorded.first?.destination.kind == .inbox)
            var apply = arguments
            apply["previewOnly"] = .bool(true)
            let second: RequestContext<CallTool.Result> = try await client.callTool(name: "add_tasks", arguments: apply)
            let previewResponse = try await second.value
            #expect(previewResponse.isError != true)
            let envelope = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(previewResponse)) as? [String: Any])
            let text = try #require((envelope["content"] as? [[String: Any]])?.first?["text"] as? String)
            let decoded = try JSONDecoder().decode(TaskCreationResponse.self, from: Data(text.utf8))
            let applyRequest = try #require(decoded.applyRequest)
            #expect(!applyRequest.previewOnly)
            try applyRequest.validate()
            #expect(applyRequest.tasks.first?.clientID == "one")
            #expect(await service.requests.last?.previewOnly == true)
        }
    }

    @Test(arguments: ["unknownNested", "removedApproval", "removedKey", "dateOnlyApply", "ambiguousDate", "wrongType", "sixLevels"])
    func invalidWireArgumentsDoNotReachService(kind: String) async throws {
        try await withCreationClient { client, service in
            var node: [String: Value] = ["clientID": .string("one"), "name": .string("Synthetic")]
            if kind == "unknownNested" { node["notes"] = .string("Typo") }
            if kind == "wrongType" { node["flagged"] = .string("true") }
            if kind == "ambiguousDate" {
                node["due"] = .object(["at": .string("2026-12-31T00:00:00Z"), "on": .string("2026-12-31")])
            }
            if kind == "dateOnlyApply" {
                node["due"] = .object(["on": .string("2026-12-31"),
                    "time": .object(["policy": .string("omnifocus_default")])])
            }
            if kind == "sixLevels" {
                for index in 0..<5 {
                    node = ["clientID": .string("level\(index)"), "name": .string("Synthetic"), "children": .array([.object(node)])]
                }
            }
            var arguments: [String: Value] = [
                "tasks": .array([.object(node)])
            ]
            if kind == "removedApproval" { arguments["approvedPreviewID"] = .string("removed") }
            if kind == "removedKey" { arguments["creationKey"] = .string("removed") }
            let call: RequestContext<CallTool.Result> = try await client.callTool(name: "add_tasks", arguments: arguments)
            #expect(try await call.value.isError == true)
            #expect(await service.requests.isEmpty)
        }
    }

    @Test(arguments: [TaskCreationResponse.Status.partial, .uncertain])
    func incompleteOutcomeIsNotWireSuccess(status: TaskCreationResponse.Status) async throws {
        try await withCreationClient { client, service in
            await service.useFailureResult(status)
            let call: RequestContext<CallTool.Result> = try await client.callTool(name: "add_tasks", arguments: [
                "tasks": .array([.object(["clientID": .string("one"), "name": .string("Synthetic")])])
            ])
            #expect(try await call.value.isError == true)
        }
    }
}

private func withCreationClient(_ body: @Sendable (Client, CreationWireService) async throws -> Void) async throws {
    let logger = Logger(label: "focusrelay.creation-wire-test")
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair(logger: logger)
    let service = CreationWireService()
    let server = await FocusRelayServer.configuredServer(service: service, logger: logger)
    let client = Client(name: "CreationWireTest", version: "1")
    try await server.start(transport: serverTransport)
    do {
        _ = try await client.connect(transport: clientTransport)
        try await body(client, service)
        await client.disconnect(); await server.stop()
    } catch {
        await client.disconnect(); await server.stop(); throw error
    }
}

private actor CreationWireService: OmniFocusService {
    var requests: [TaskCreationRequest] = []
    var failureStatus: TaskCreationResponse.Status?
    func useFailureResult(_ status: TaskCreationResponse.Status) { failureStatus = status }
    func addTasks(_ request: TaskCreationRequest) async throws -> TaskCreationResponse {
        requests.append(request)
        return TaskCreationResponse(status: failureStatus ?? (request.previewOnly ? .previewed : .completed),
            destination: request.destination, results: [], message: "Synthetic response",
            applyRequest: request.previewOnly ? TaskCreationRequest(destination: request.destination,
                tasks: request.tasks, returnFields: request.returnFields) : nil)
    }
    func listTasks(filter: TaskFilter, page: PageRequest, fields: [String]?) async throws -> Page<TaskItem> { throw unsupported() }
    func getTask(id: String, fields: [String]?) async throws -> TaskItem { throw unsupported() }
    func listProjects(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool, search: String?, rootOnly: Bool, reviewDueBefore: Date?, reviewDueAfter: Date?, reviewPerspective: Bool, completed: Bool?, completedBefore: Date?, completedAfter: Date?, fields: [String]?) async throws -> Page<ProjectItem> { throw unsupported() }
    func listTags(page: PageRequest, statusFilter: String?, includeTaskCounts: Bool, search: String?, fields: [String]?) async throws -> Page<TagItem> { throw unsupported() }
    func listFolders(page: PageRequest, fields: [String]?) async throws -> Page<FolderItem> { throw unsupported() }
    func resolveProjectNames(searches: [String], matchLimitPerSearch: Int, statusFilter: String?, fields: [String]?) async throws -> [NameSearchGroup<ProjectItem>] { throw unsupported() }
    func resolveTagNames(searches: [String], matchLimitPerSearch: Int, statusFilter: String?, fields: [String]?) async throws -> [NameSearchGroup<TagItem>] { throw unsupported() }
    func getTaskCounts(filter: TaskFilter) async throws -> TaskCounts { throw unsupported() }
    func getProjectCounts(filter: TaskFilter) async throws -> ProjectCounts { throw unsupported() }
    func performMutation(_ request: MutationRequest) async throws -> MutationResponse { throw unsupported() }
    private func unsupported() -> MutationValidationError { MutationValidationError("Unexpected non-creation call.") }
}
