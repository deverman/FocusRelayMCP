import Dispatch
import Foundation
import Synchronization
import Testing
@testable import OmniFocusAutomation

private actor CoordinatorGate {
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

private actor CoordinatorProbe {
    private(set) var active = 0
    private(set) var maximumActive = 0
    private(set) var starts: [String] = []
    private(set) var finishes: [String] = []

    func begin(_ label: String) {
        active += 1
        maximumActive = max(maximumActive, active)
        starts.append(label)
    }

    func finish(_ label: String) {
        finishes.append(label)
        active -= 1
    }

    func snapshot() -> (active: Int, maximumActive: Int, starts: [String], finishes: [String]) {
        (active, maximumActive, starts, finishes)
    }
}

private final class LockedCounter: Sendable {
    private let value = Mutex(0)

    func increment() {
        value.withLock { $0 += 1 }
    }

    var current: Int {
        value.withLock { $0 }
    }
}

private enum CoordinatorTestError: Error {
    case expected
}

private func waitForCoordinator(
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
    Issue.record("Timed out waiting for coordinator state")
}

private func expectCancellation<Value>(_ task: Task<Value, any Error>) async {
    do {
        _ = try await task.value
        Issue.record("Expected CancellationError")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Expected CancellationError, received \(error)")
    }
}

@Test
func productionBridgeAdmissionPolicyMatchesMeasuredBaseline() {
    let policy = BridgeCoordinatorPolicy.production
    #expect(policy.maximumAcceptedRequests == 7)
    #expect(policy.maximumQueueWait == .seconds(43))
    #expect(policy.retryAfterMilliseconds == 6_750)
}

@Test
func bridgeCoordinatorRunsMixedOperationsInFIFOOrderWithOneActiveJob() async throws {
    let coordinator = BridgeRequestCoordinator(logger: nil)
    let firstGate = CoordinatorGate()
    let probe = CoordinatorProbe()

    func makeTask(
        label: String,
        category: BridgeOperationCategory,
        gate: CoordinatorGate? = nil
    ) -> Task<String, any Error> {
        Task {
            try await coordinator.submit(category: category) {
                await probe.begin(label)
                if let gate {
                    await gate.wait()
                }
                await probe.finish(label)
                return label
            }
        }
    }

    let first = makeTask(label: "health", category: .health, gate: firstGate)
    try await waitForCoordinator {
        await coordinator.snapshot().running == 1
    }

    let second = makeTask(label: "read", category: .taskQuery)
    try await waitForCoordinator {
        await coordinator.snapshot().queued == 1
    }
    let third = makeTask(label: "preview", category: .mutationPreview)
    try await waitForCoordinator {
        await coordinator.snapshot().queued == 2
    }
    let fourth = makeTask(label: "apply", category: .mutationApply)
    try await waitForCoordinator {
        await coordinator.snapshot().queued == 3
    }

    await firstGate.open()
    #expect(try await first.value == "health")
    #expect(try await second.value == "read")
    #expect(try await third.value == "preview")
    #expect(try await fourth.value == "apply")

    let snapshot = await probe.snapshot()
    #expect(snapshot.starts == ["health", "read", "preview", "apply"])
    #expect(snapshot.finishes == ["health", "read", "preview", "apply"])
    #expect(snapshot.maximumActive == 1)
}

@Test
func failedBridgeJobReleasesLaneForNextQueuedRequest() async throws {
    let coordinator = BridgeRequestCoordinator(logger: nil)
    let gate = CoordinatorGate()

    let failing = Task<Int, any Error> {
        try await coordinator.submit(category: .taskQuery) {
            await gate.wait()
            throw CoordinatorTestError.expected
        }
    }
    try await waitForCoordinator {
        await coordinator.snapshot().running == 1
    }
    let next = Task {
        try await coordinator.submit(category: .health) { 2 }
    }
    try await waitForCoordinator {
        await coordinator.snapshot().queued == 1
    }

    await gate.open()
    do {
        _ = try await failing.value
        Issue.record("Expected Bridge job failure")
    } catch CoordinatorTestError.expected {
        // Expected.
    }
    #expect(try await next.value == 2)
    #expect(await coordinator.snapshot().accepted == 0)
}

@Test
func bridgeCoordinatorRejectsEighthRequestWithoutDispatch() async throws {
    let coordinator = BridgeRequestCoordinator(logger: nil)
    let gate = CoordinatorGate()
    let calls = LockedCounter()
    var accepted: [Task<Int, any Error>] = []

    for expectedAccepted in 1...7 {
        accepted.append(
            Task {
                try await coordinator.submit(category: .countsQuery) {
                    calls.increment()
                    await gate.wait()
                    return 1
                }
            }
        )
        try await waitForCoordinator {
            await coordinator.snapshot().accepted == expectedAccepted
        }
    }

    let startedAt = ContinuousClock().now
    do {
        _ = try await coordinator.submit(category: .countsQuery) {
            calls.increment()
            return 8
        }
        Issue.record("Expected bridge_busy")
    } catch let error as BridgeAdmissionError {
        #expect(error == .busy(retryAfterMilliseconds: 6_750))
    }
    let elapsed = startedAt.duration(to: ContinuousClock().now)
    #expect(elapsed < .milliseconds(250))
    #expect(calls.current == 1)

    await gate.open()
    for task in accepted {
        #expect(try await task.value == 1)
    }
    #expect(calls.current == 7)
}

@Test
func cancelingQueuedRequestPreventsBridgeInvocation() async throws {
    let coordinator = BridgeRequestCoordinator(logger: nil)
    let gate = CoordinatorGate()
    let queuedCalls = LockedCounter()

    let blocker = Task {
        try await coordinator.submit(category: .taskQuery) {
            await gate.wait()
            return 1
        }
    }
    try await waitForCoordinator {
        await coordinator.snapshot().running == 1
    }

    let queued = Task {
        try await coordinator.submit(category: .mutationApply) {
            queuedCalls.increment()
            return 2
        }
    }
    try await waitForCoordinator {
        await coordinator.snapshot().queued == 1
    }

    queued.cancel()
    await expectCancellation(queued)
    try await waitForCoordinator {
        await coordinator.snapshot().queued == 0
    }
    #expect(queuedCalls.current == 0)

    await gate.open()
    #expect(try await blocker.value == 1)
}

@Test
func expiringQueuedRequestPreventsBridgeInvocation() async throws {
    let coordinator = BridgeRequestCoordinator(
        policy: BridgeCoordinatorPolicy(
            maximumAcceptedRequests: 2,
            maximumQueueWait: .milliseconds(25),
            retryAfterMilliseconds: 50
        ),
        logger: nil
    )
    let gate = CoordinatorGate()
    let queuedCalls = LockedCounter()

    let blocker = Task {
        try await coordinator.submit(category: .taskQuery) {
            await gate.wait()
            return 1
        }
    }
    try await waitForCoordinator {
        await coordinator.snapshot().running == 1
    }

    do {
        _ = try await coordinator.submit(category: .projectQuery) {
            queuedCalls.increment()
            return 2
        }
        Issue.record("Expected bridge_queue_timeout")
    } catch let error as BridgeAdmissionError {
        #expect(error == .queueTimeout(retryAfterMilliseconds: 50))
    }
    #expect(queuedCalls.current == 0)

    await gate.open()
    #expect(try await blocker.value == 1)
}

@Test
func cancelingCommittedRequestLetsWorkerFinalizeExactlyOnce() async throws {
    let coordinator = BridgeRequestCoordinator(logger: nil)
    let committed = CoordinatorGate()
    let finishGate = CoordinatorGate()
    let invocations = LockedCounter()
    let finalizations = LockedCounter()

    let task = Task {
        try await coordinator.submit(category: .mutationApply) {
            invocations.increment()
            await committed.open()
            await finishGate.wait()
            finalizations.increment()
            return 1
        }
    }
    await committed.wait()

    task.cancel()
    await expectCancellation(task)
    #expect(invocations.current == 1)
    #expect(finalizations.current == 0)

    await finishGate.open()
    try await waitForCoordinator {
        await coordinator.snapshot().accepted == 0
    }
    #expect(invocations.current == 1)
    #expect(finalizations.current == 1)
}

@Test
func bridgeRuntimeFinalizerSurvivesCallerCancellation() async throws {
    let coordinator = BridgeRequestCoordinator(logger: nil)
    let executor = BridgeBlockingExecutor(logger: nil)
    let runtime = BridgeRuntime(coordinator: coordinator, executor: executor)
    let finalizeStarted = CoordinatorGate()
    let finishGate = CoordinatorGate()
    let finalizations = LockedCounter()

    let task = Task {
        try await runtime.submit(
            category: .mutationApply,
            bridge: { 1 },
            finalize: { value in
                await finalizeStarted.open()
                await finishGate.wait()
                finalizations.increment()
                return value
            }
        )
    }
    await finalizeStarted.wait()

    task.cancel()
    await expectCancellation(task)
    await finishGate.open()
    try await waitForCoordinator {
        await coordinator.snapshot().accepted == 0
    }
    #expect(finalizations.current == 1)
}

@Test
func bridgeBlockingExecutorRunsOperationOnConfiguredSerialQueue() async throws {
    let key = DispatchSpecificKey<String>()
    let queue = DispatchQueue(label: "bridge-executor-test")
    queue.setSpecific(key: key, value: "bridge-executor-test")
    let executor = BridgeBlockingExecutor(queue: queue, logger: nil)

    let observed = try await executor.run(category: .health) {
        DispatchQueue.getSpecific(key: key)
    }

    #expect(observed == "bridge-executor-test")
}

@Test
func shuttingDownCoordinatorResumesQueuedWaitersOnce() async throws {
    let coordinator = BridgeRequestCoordinator(logger: nil)
    let gate = CoordinatorGate()

    let blocker = Task {
        try await coordinator.submit(category: .health) {
            await gate.wait()
            return 1
        }
    }
    try await waitForCoordinator {
        await coordinator.snapshot().running == 1
    }
    let queued = Task {
        try await coordinator.submit(category: .taskQuery) { 2 }
    }
    try await waitForCoordinator {
        await coordinator.snapshot().queued == 1
    }

    await coordinator.shutdown()
    do {
        _ = try await queued.value
        Issue.record("Expected shutdown error")
    } catch {
        #expect(error.localizedDescription.contains("shutting down"))
    }

    await gate.open()
    #expect(try await blocker.value == 1)
}

@Test
func bridgeCoordinatorCompletesTenThousandShortJobsWithoutStranding() async throws {
    let coordinator = BridgeRequestCoordinator(logger: nil)
    let completed = LockedCounter()

    for batchStart in stride(from: 0, to: 10_000, by: 7) {
        let batchEnd = min(batchStart + 7, 10_000)
        let tasks = (batchStart..<batchEnd).map { value in
            Task {
                try await coordinator.submit(category: .countsQuery) {
                    completed.increment()
                    return value
                }
            }
        }
        for (offset, task) in tasks.enumerated() {
            #expect(try await task.value == batchStart + offset)
        }
    }

    let snapshot = await coordinator.snapshot()
    #expect(snapshot.accepted == 0)
    #expect(completed.current == 10_000)
}
