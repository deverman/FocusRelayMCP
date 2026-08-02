import Foundation
import Logging
import MCP
import OmniFocusCore
import Synchronization
import Testing
@testable import FocusRelayServer
@testable import OmniFocusAutomation

private actor CancellationBoundaryGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

private actor CancellationBoundaryService: OmniFocusService {
    struct Snapshot: Sendable {
        let invocations: Int
        let finalizations: Int
    }

    private let coordinator = BridgeRequestCoordinator(logger: nil)
    private let operationGate = CancellationBoundaryGate()
    private var invocations = 0
    private var finalizations = 0

    func getTaskCounts(filter: TaskFilter) async throws -> TaskCounts {
        try await coordinator.submit(category: .countsQuery) {
            await self.recordInvocation()
            await self.operationGate.wait()
            await self.recordFinalization()
            return TaskCounts(total: 1, completed: 0, available: 1, flagged: 0)
        }
    }

    func openOperations() async {
        await operationGate.open()
    }

    func coordinatorSnapshot() async -> (running: Int, queued: Int, accepted: Int) {
        await coordinator.snapshot()
    }

    func snapshot() -> Snapshot {
        Snapshot(invocations: invocations, finalizations: finalizations)
    }

    private func recordInvocation() {
        invocations += 1
    }

    private func recordFinalization() {
        finalizations += 1
    }

    func listTasks(
        filter: TaskFilter,
        page: PageRequest,
        fields: [String]?
    ) async throws -> Page<TaskItem> {
        throw CancellationBoundaryTestError.unexpectedTool
    }

    func getTask(id: String, fields: [String]?) async throws -> TaskItem {
        throw CancellationBoundaryTestError.unexpectedTool
    }

    func listProjects(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool,
        search: String?,
        rootOnly: Bool,
        reviewDueBefore: Date?,
        reviewDueAfter: Date?,
        reviewPerspective: Bool,
        completed: Bool?,
        completedBefore: Date?,
        completedAfter: Date?,
        fields: [String]?
    ) async throws -> Page<ProjectItem> {
        throw CancellationBoundaryTestError.unexpectedTool
    }

    func listTags(
        page: PageRequest,
        statusFilter: String?,
        includeTaskCounts: Bool,
        search: String?,
        fields: [String]?
    ) async throws -> Page<TagItem> {
        throw CancellationBoundaryTestError.unexpectedTool
    }

    func listFolders(page: PageRequest, fields: [String]?) async throws -> Page<FolderItem> {
        throw CancellationBoundaryTestError.unexpectedTool
    }

    func getProjectCounts(filter: TaskFilter) async throws -> ProjectCounts {
        throw CancellationBoundaryTestError.unexpectedTool
    }

    func performMutation(_ request: MutationRequest) async throws -> MutationResponse {
        throw CancellationBoundaryTestError.unexpectedTool
    }
}

private enum CancellationBoundaryTestError: Error {
    case unexpectedTool
}

private final class CancellationBoundaryLogStore: Sendable {
    private let messages = Mutex<[String]>([])

    func append(_ message: String) {
        messages.withLock { $0.append(message) }
    }

    var snapshot: [String] {
        messages.withLock { $0 }
    }
}

private struct CancellationBoundaryLogHandler: LogHandler {
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .trace
    let store: CancellationBoundaryLogStore

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        store.append("\(message)")
    }
}

private func waitForCancellationBoundary(
    timeout: Duration = .seconds(2),
    _ condition: @escaping @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Timed out waiting for MCP cancellation boundary state")
}

private func expectMCPRequestCancellation<Value: Sendable>(
    _ context: RequestContext<Value>
) async {
    do {
        _ = try await context.value
        Issue.record("Expected MCP request cancellation")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Expected CancellationError, received \(error)")
    }
}

private func withCancellationBoundary(
    _ body: @escaping @Sendable (
        _ client: Client,
        _ service: CancellationBoundaryService,
        _ logStore: CancellationBoundaryLogStore
    ) async throws -> Void
) async throws {
    let logStore = CancellationBoundaryLogStore()
    let logger = Logger(label: "focus.relay.mcp.cancellation-test") { _ in
        CancellationBoundaryLogHandler(store: logStore)
    }
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair(
        logger: logger
    )
    let service = CancellationBoundaryService()
    let server = await FocusRelayServer.configuredServer(service: service, logger: logger)
    let client = Client(name: "FocusRelayCancellationTest", version: "1")

    try await server.start(transport: serverTransport)
    do {
        _ = try await client.connect(transport: clientTransport)
        try await body(client, service, logStore)
        await client.disconnect()
        await server.stop()
    } catch {
        await client.disconnect()
        await server.stop()
        throw error
    }
}

@Test
func mcpServerLifecycleCancellationStopsTheTransport() async throws {
    let logger = Logger(label: "focus.relay.mcp.lifecycle-cancellation-test")
    let (_, serverTransport) = await InMemoryTransport.createConnectedPair(logger: logger)
    let service = CancellationBoundaryService()
    let server = await FocusRelayServer.configuredServer(service: service, logger: logger)
    try await server.start(transport: serverTransport)

    let lifecycle = Task {
        try await FocusRelayServer.waitUntilTransportCompletes(server)
    }
    lifecycle.cancel()

    do {
        try await lifecycle.value
        Issue.record("Expected lifecycle cancellation")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Expected CancellationError, received \(error)")
    }
}

@Test
func mcpCancellationRemovesQueuedBridgeRequestBeforeInvocation() async throws {
    try await withCancellationBoundary { client, service, logStore in
        let running: RequestContext<CallTool.Result> = try await client.callTool(
            name: "get_task_counts",
            arguments: [:]
        )
        try await waitForCancellationBoundary {
            let state = await service.coordinatorSnapshot()
            let probe = await service.snapshot()
            return state.running == 1 && probe.invocations == 1
        }

        let queued: RequestContext<CallTool.Result> = try await client.callTool(
            name: "get_task_counts",
            arguments: [:]
        )
        try await waitForCancellationBoundary {
            await service.coordinatorSnapshot().queued == 1
        }

        try await client.cancelRequest(queued.requestID, reason: "test queued cancellation")
        await expectMCPRequestCancellation(queued)
        try await waitForCancellationBoundary {
            await service.coordinatorSnapshot().queued == 0
        }
        try await waitForCancellationBoundary {
            logStore.snapshot.contains("Request cancelled")
        }
        #expect(await service.snapshot().invocations == 1)

        await service.openOperations()
        let runningResult = try await running.value
        #expect(runningResult.isError != true)
        try await waitForCancellationBoundary {
            await service.coordinatorSnapshot().accepted == 0
        }

        let final = await service.snapshot()
        #expect(final.invocations == 1)
        #expect(final.finalizations == 1)

        let sentinel: RequestContext<CallTool.Result> = try await client.callTool(
            name: "get_task_counts",
            arguments: [:]
        )
        #expect(try await sentinel.value.isError != true)
        #expect(
            !logStore.snapshot.contains(
                "Attempted to handle response for already removed request"
            )
        )
    }
}

@Test
func mcpCancellationAfterDispatchLetsWorkerFinalizeExactlyOnce() async throws {
    try await withCancellationBoundary { client, service, logStore in
        let committed: RequestContext<CallTool.Result> = try await client.callTool(
            name: "get_task_counts",
            arguments: [:]
        )
        try await waitForCancellationBoundary {
            let state = await service.coordinatorSnapshot()
            let probe = await service.snapshot()
            return state.running == 1 && probe.invocations == 1
        }

        try await client.cancelRequest(committed.requestID, reason: "test committed cancellation")
        await expectMCPRequestCancellation(committed)
        #expect(await service.snapshot().finalizations == 0)
        try await waitForCancellationBoundary {
            logStore.snapshot.contains("Request cancelled")
        }

        await service.openOperations()
        try await waitForCancellationBoundary {
            let state = await service.coordinatorSnapshot()
            let probe = await service.snapshot()
            return state.accepted == 0 && probe.finalizations == 1
        }

        let final = await service.snapshot()
        #expect(final.invocations == 1)
        #expect(final.finalizations == 1)

        let sentinel: RequestContext<CallTool.Result> = try await client.callTool(
            name: "get_task_counts",
            arguments: [:]
        )
        #expect(try await sentinel.value.isError != true)
        #expect(
            !logStore.snapshot.contains(
                "Attempted to handle response for already removed request"
            )
        )
    }
}
