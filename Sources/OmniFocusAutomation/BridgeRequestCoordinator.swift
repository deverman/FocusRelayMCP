import Dispatch
import Foundation
import OSLog
import Synchronization

public enum BridgeAdmissionError: Error, Equatable, LocalizedError, Sendable {
    case busy(retryAfterMilliseconds: Int)
    case queueTimeout(retryAfterMilliseconds: Int)

    public var code: String {
        switch self {
        case .busy:
            "bridge_busy"
        case .queueTimeout:
            "bridge_queue_timeout"
        }
    }

    public var retryAfterMilliseconds: Int {
        switch self {
        case .busy(let retryAfterMilliseconds), .queueTimeout(let retryAfterMilliseconds):
            retryAfterMilliseconds
        }
    }

    public var errorDescription: String? {
        switch self {
        case .busy:
            "OmniFocus Bridge is busy. Retry after \(retryAfterMilliseconds) ms."
        case .queueTimeout:
            "OmniFocus Bridge queue wait expired. Retry after \(retryAfterMilliseconds) ms."
        }
    }
}

enum BridgeOperationCategory: String, Sendable {
    case taskQuery = "task_query"
    case projectQuery = "project_query"
    case tagQuery = "tag_query"
    case folderQuery = "folder_query"
    case countsQuery = "counts_query"
    case mutationPreview = "mutation_preview"
    case mutationApply = "mutation_apply"
    case health
}

struct BridgeCoordinatorPolicy: Equatable, Sendable {
    let maximumAcceptedRequests: Int
    let maximumQueueWait: Duration
    let retryAfterMilliseconds: Int

    // Calibrated from the sanitized completion-preview baseline recorded in #170.
    static let production = BridgeCoordinatorPolicy(
        maximumAcceptedRequests: 7,
        maximumQueueWait: .seconds(43),
        retryAfterMilliseconds: 6_750
    )
}

private enum BridgeJobLifecycle: Sendable {
    case queued
    case dispatchCommitted
    case finished
}

private enum BridgeCancellationOutcome: Sendable {
    case queued
    case dispatchCommitted
    case alreadyFinished
}

private final class BridgeJobState<Value: Sendable>: Sendable {
    private struct Storage {
        var lifecycle = BridgeJobLifecycle.queued
        var continuation: CheckedContinuation<Value, any Error>?
        var callerResult: Result<Value, any Error>?
    }

    // The actor owns queue membership. This mutex decides the smaller
    // cancellation-vs-dispatch race without waiting for another actor hop.
    private let storage = Mutex(Storage())

    var isQueued: Bool {
        storage.withLock { $0.lifecycle == .queued }
    }

    func installContinuation(_ continuation: CheckedContinuation<Value, any Error>) {
        let result = storage.withLock { state -> Result<Value, any Error>? in
            if let callerResult = state.callerResult {
                return callerResult
            }
            state.continuation = continuation
            return nil
        }
        if let result {
            continuation.resume(with: result)
        }
    }

    func commitDispatch() -> Bool {
        storage.withLock { state in
            guard state.lifecycle == .queued else {
                return false
            }
            state.lifecycle = .dispatchCommitted
            return true
        }
    }

    func cancelCaller() -> BridgeCancellationOutcome {
        let cancellation = Result<Value, any Error>.failure(CancellationError())
        let outcome = storage.withLock {
            state -> (BridgeCancellationOutcome, CheckedContinuation<Value, any Error>?) in
            switch state.lifecycle {
            case .queued:
                state.lifecycle = .finished
                state.callerResult = cancellation
                let continuation = state.continuation
                state.continuation = nil
                return (.queued, continuation)
            case .dispatchCommitted:
                guard state.callerResult == nil else {
                    return (.dispatchCommitted, nil)
                }
                state.callerResult = cancellation
                let continuation = state.continuation
                state.continuation = nil
                return (.dispatchCommitted, continuation)
            case .finished:
                return (.alreadyFinished, nil)
            }
        }
        outcome.1?.resume(with: cancellation)
        return outcome.0
    }

    @discardableResult
    func failBeforeDispatch(_ error: any Error) -> Bool {
        let failure = Result<Value, any Error>.failure(error)
        let outcome = storage.withLock {
            state -> (Bool, CheckedContinuation<Value, any Error>?) in
            guard state.lifecycle == .queued else {
                return (false, nil)
            }
            state.lifecycle = .finished
            state.callerResult = failure
            let continuation = state.continuation
            state.continuation = nil
            return (true, continuation)
        }
        outcome.1?.resume(with: failure)
        return outcome.0
    }

    func finish(_ result: Result<Value, any Error>) {
        let continuation = storage.withLock { state -> CheckedContinuation<Value, any Error>? in
            guard state.lifecycle == .dispatchCommitted else {
                return nil
            }
            state.lifecycle = .finished
            guard state.callerResult == nil else {
                return nil
            }
            state.callerResult = result
            let continuation = state.continuation
            state.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}

private struct BridgeQueuedJob: Sendable {
    let id: UUID
    let category: BridgeOperationCategory
    let enqueuedAt: Date
    let isQueued: @Sendable () -> Bool
    let commitDispatch: @Sendable () -> Bool
    let failBeforeDispatch: @Sendable (any Error) -> Bool
    let run: @Sendable () async -> Void
    var timeoutTask: Task<Void, Never>?
}

private struct BridgeCoordinatorShutdownError: Error, LocalizedError, Sendable {
    var errorDescription: String? {
        "OmniFocus Bridge coordinator is shutting down."
    }
}

actor BridgeRequestCoordinator {
    private let policy: BridgeCoordinatorPolicy
    private let logger: Logger?
    private var queue: [BridgeQueuedJob] = []
    private var runningJobID: UUID?
    private var acceptingRequests = true

    init(
        policy: BridgeCoordinatorPolicy = .production,
        logger: Logger? = Logger(
            subsystem: "com.focusrelay.mcp",
            category: "bridge-coordinator"
        )
    ) {
        precondition(policy.maximumAcceptedRequests > 0)
        precondition(policy.maximumQueueWait > .zero)
        self.policy = policy
        self.logger = logger
    }

    func submit<Value: Sendable>(
        category: BridgeOperationCategory,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        removeFinishedQueuedJobs()

        guard acceptingRequests else {
            throw BridgeCoordinatorShutdownError()
        }
        guard acceptedRequestCount < policy.maximumAcceptedRequests else {
            logger?.notice(
                "event=bridge_busy operation=\(category.rawValue, privacy: .public) accepted=\(self.acceptedRequestCount, privacy: .public)"
            )
            throw BridgeAdmissionError.busy(
                retryAfterMilliseconds: policy.retryAfterMilliseconds
            )
        }

        let id = UUID()
        let enqueuedAt = Date()
        let state = BridgeJobState<Value>()
        let jobLogger = logger
        var job = BridgeQueuedJob(
            id: id,
            category: category,
            enqueuedAt: enqueuedAt,
            isQueued: { state.isQueued },
            commitDispatch: { state.commitDispatch() },
            failBeforeDispatch: { error in state.failBeforeDispatch(error) },
            run: {
                let workerStartedAt = Date()
                do {
                    let value = try await operation()
                    state.finish(.success(value))
                    let finishedAt = Date()
                    let workerMilliseconds = finishedAt.timeIntervalSince(workerStartedAt) * 1_000
                    let totalMilliseconds = finishedAt.timeIntervalSince(enqueuedAt) * 1_000
                    jobLogger?.info(
                        "event=bridge_finished operation=\(category.rawValue, privacy: .public) result=success workerMilliseconds=\(workerMilliseconds, privacy: .public) totalMilliseconds=\(totalMilliseconds, privacy: .public)"
                    )
                } catch {
                    state.finish(.failure(error))
                    let finishedAt = Date()
                    let workerMilliseconds = finishedAt.timeIntervalSince(workerStartedAt) * 1_000
                    let totalMilliseconds = finishedAt.timeIntervalSince(enqueuedAt) * 1_000
                    jobLogger?.error(
                        "event=bridge_finished operation=\(category.rawValue, privacy: .public) result=failure workerMilliseconds=\(workerMilliseconds, privacy: .public) totalMilliseconds=\(totalMilliseconds, privacy: .public)"
                    )
                }
            },
            timeoutTask: nil
        )

        queue.append(job)
        let maximumQueueWait = policy.maximumQueueWait
        let timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: maximumQueueWait)
                await self?.expireQueuedJob(id: id)
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
        job.timeoutTask = timeoutTask
        if let index = queue.firstIndex(where: { $0.id == id }) {
            queue[index] = job
        } else {
            timeoutTask.cancel()
        }

        logger?.info(
            "event=bridge_accepted operation=\(category.rawValue, privacy: .public) queueDepth=\(self.queue.count, privacy: .public)"
        )
        startNextIfNeeded()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.installContinuation(continuation)
            }
        } onCancel: {
            let outcome = state.cancelCaller()
            Task { [weak self] in
                await self?.callerCanceled(jobID: id, category: category, outcome: outcome)
            }
        }
    }

    func shutdown() {
        acceptingRequests = false
        let queued = queue
        queue.removeAll(keepingCapacity: false)
        for job in queued {
            job.timeoutTask?.cancel()
            _ = job.failBeforeDispatch(BridgeCoordinatorShutdownError())
        }
    }

    func snapshot() -> (running: Int, queued: Int, accepted: Int) {
        removeFinishedQueuedJobs()
        return (
            running: runningJobID == nil ? 0 : 1,
            queued: queue.count,
            accepted: acceptedRequestCount
        )
    }

    private var acceptedRequestCount: Int {
        (runningJobID == nil ? 0 : 1) + queue.count
    }

    private func startNextIfNeeded() {
        guard runningJobID == nil else {
            return
        }

        while !queue.isEmpty {
            let job = queue.removeFirst()
            job.timeoutTask?.cancel()
            guard job.commitDispatch() else {
                continue
            }

            runningJobID = job.id
            let queueWaitMilliseconds = Date().timeIntervalSince(job.enqueuedAt) * 1_000
            logger?.info(
                "event=bridge_dispatch_committed operation=\(job.category.rawValue, privacy: .public) queueWaitMilliseconds=\(queueWaitMilliseconds, privacy: .public) remainingQueueDepth=\(self.queue.count, privacy: .public)"
            )
            Task { @concurrent [job, weak self] in
                await job.run()
                await self?.jobFinished(id: job.id)
            }
            return
        }
    }

    private func jobFinished(id: UUID) {
        guard runningJobID == id else {
            return
        }
        runningJobID = nil
        startNextIfNeeded()
    }

    private func expireQueuedJob(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else {
            return
        }
        let job = queue.remove(at: index)
        let timeoutWon = job.failBeforeDispatch(
            BridgeAdmissionError.queueTimeout(
                retryAfterMilliseconds: policy.retryAfterMilliseconds
            )
        )
        if timeoutWon {
            logger?.notice(
                "event=bridge_queue_timeout operation=\(job.category.rawValue, privacy: .public) queueDepth=\(self.queue.count, privacy: .public)"
            )
        }
    }

    private func callerCanceled(
        jobID: UUID,
        category: BridgeOperationCategory,
        outcome: BridgeCancellationOutcome
    ) {
        switch outcome {
        case .queued:
            if let index = queue.firstIndex(where: { $0.id == jobID }) {
                let job = queue.remove(at: index)
                job.timeoutTask?.cancel()
            }
            logger?.info(
                "event=bridge_canceled_before_dispatch operation=\(category.rawValue, privacy: .public) queueDepth=\(self.queue.count, privacy: .public)"
            )
        case .dispatchCommitted:
            logger?.info(
                "event=bridge_canceled_after_commit operation=\(category.rawValue, privacy: .public)"
            )
        case .alreadyFinished:
            break
        }
    }

    private func removeFinishedQueuedJobs() {
        var retained: [BridgeQueuedJob] = []
        retained.reserveCapacity(queue.count)
        for job in queue {
            if job.isQueued() {
                retained.append(job)
            } else {
                job.timeoutTask?.cancel()
            }
        }
        queue = retained
    }
}

final class BridgeBlockingExecutor: Sendable {
    private let queue: DispatchQueue
    private let logger: Logger?

    init(
        queue: DispatchQueue = DispatchQueue(
            label: "com.focusrelay.mcp.bridge-executor",
            qos: .userInitiated
        ),
        logger: Logger? = Logger(
            subsystem: "com.focusrelay.mcp",
            category: "bridge-executor"
        )
    ) {
        self.queue = queue
        self.logger = logger
    }

    func run<Value: Sendable>(
        category: BridgeOperationCategory,
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let submittedAt = Date()
        return try await withTaskExecutorPreference(queue) {
            let startedAt = Date()
            let handoffMilliseconds = startedAt.timeIntervalSince(submittedAt) * 1_000
            defer {
                let executionMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
                logger?.info(
                    "event=bridge_executor_finished operation=\(category.rawValue, privacy: .public) handoffMilliseconds=\(handoffMilliseconds, privacy: .public) executionMilliseconds=\(executionMilliseconds, privacy: .public)"
                )
            }
            return try operation()
        }
    }
}

final class BridgeRuntime: Sendable {
    // Every service instance in one server process shares the same admission
    // lane and blocking executor. Catalog caches remain service-owned.
    static let shared = BridgeRuntime()

    let coordinator: BridgeRequestCoordinator
    let executor: BridgeBlockingExecutor

    init(
        coordinator: BridgeRequestCoordinator = BridgeRequestCoordinator(),
        executor: BridgeBlockingExecutor = BridgeBlockingExecutor()
    ) {
        self.coordinator = coordinator
        self.executor = executor
    }

    func submit<Value: Sendable>(
        category: BridgeOperationCategory,
        bridge: @escaping @Sendable () throws -> Value,
        finalize: @escaping @Sendable (Value) async throws -> Value = { $0 }
    ) async throws -> Value {
        try await coordinator.submit(category: category) {
            let value = try await self.executor.run(category: category, bridge)
            return try await finalize(value)
        }
    }
}
