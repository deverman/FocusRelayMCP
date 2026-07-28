import Foundation

public enum BridgeBurstProfile: String, Codable, CaseIterable, Sendable {
    case canary
    case smoke
    case release
    case stress

    public var warmupCount: Int { 1 }
    public var sequentialSampleCount: Int { 12 }
    public var burstSizes: [Int] { [2, 4, 7, 12] }

    public var targetBurstDuration: Duration? {
        switch self {
        case .canary: nil
        case .smoke: .seconds(600)
        case .release: .seconds(5_400)
        case .stress: .seconds(10_800)
        }
    }
}

public enum BridgeBurstScenario: String, Codable, CaseIterable, Sendable {
    case taskCounts = "task-counts"
    case completionPreview = "completion-preview"

    public var toolName: String {
        switch self {
        case .taskCounts: "get_task_counts"
        case .completionPreview: "edit_tasks"
        }
    }

    public func sequentialSampleCount(for profile: BridgeBurstProfile) -> Int {
        switch self {
        case .taskCounts: profile.sequentialSampleCount
        case .completionPreview: 3
        }
    }

    public func arguments(fixtureTaskID: String?) throws -> BurstJSONValue {
        switch self {
        case .taskCounts:
            return .object([
                "filter": .object([
                    "inboxOnly": .bool(true),
                    "inboxView": .string("remaining"),
                ]),
            ])
        case .completionPreview:
            guard let fixtureTaskID,
                  !fixtureTaskID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BridgeBurstConfigurationError.missingFixtureTaskID
            }
            return .object([
                "operation": .string("set_completion"),
                "targetIDs": .array([.string(fixtureTaskID)]),
                "completion": .object(["state": .string("completed")]),
                "previewOnly": .bool(true),
            ])
        }
    }
}

public enum BridgeBurstConfigurationError: Error, LocalizedError, Sendable {
    case missingFixtureTaskID
    case invalidServerBinary
    case invalidResponseTimeoutSeconds

    public var errorDescription: String? {
        switch self {
        case .missingFixtureTaskID:
            "completion-preview requires --fixture-task-id."
        case .invalidServerBinary:
            "The server binary is missing or is not executable."
        case .invalidResponseTimeoutSeconds:
            "Response timeout must be a finite value from 1 through 120 seconds."
        }
    }
}

public struct BridgeBurstResponseDeadline: Equatable, Sendable {
    public static let defaultSeconds = 15.0
    public let milliseconds: Int

    public init(seconds: Double = defaultSeconds) throws {
        guard seconds.isFinite, (1...120).contains(seconds) else {
            throw BridgeBurstConfigurationError.invalidResponseTimeoutSeconds
        }
        milliseconds = Int((seconds * 1_000).rounded())
    }

    public var duration: Duration {
        .milliseconds(milliseconds)
    }
}

public enum BurstJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([BurstJSONValue])
    case object([String: BurstJSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([BurstJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: BurstJSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

public struct BridgeBurstRequest: Equatable, Sendable {
    public let id: Int
    public let toolName: String
    public let arguments: BurstJSONValue

    public init(id: Int, toolName: String, arguments: BurstJSONValue) {
        self.id = id
        self.toolName = toolName
        self.arguments = arguments
    }
}

public enum BridgeBurstClassification: String, Codable, CaseIterable, Sendable {
    case success
    case toolError
    case protocolError
    case processExit
    case timeout
}

public enum BridgeBurstTransportError: Error, LocalizedError, Sendable {
    case protocolError
    case processExit(Int32)
    case timeout

    public var classification: BridgeBurstClassification {
        switch self {
        case .protocolError: .protocolError
        case .processExit: .processExit
        case .timeout: .timeout
        }
    }

    public var errorDescription: String? {
        switch self {
        case .protocolError:
            "The MCP server returned a malformed or unmatched response."
        case .processExit:
            "The MCP server exited before completing the request."
        case .timeout:
            "The MCP response deadline expired."
        }
    }
}

public protocol BridgeBurstTransport: Sendable {
    func start() async throws
    func initialize(timeout: Duration) async throws
    func call(
        _ request: BridgeBurstRequest,
        timeout: Duration
    ) async throws -> BridgeBurstClassification
    func stop() async
}

public struct BridgeBurstSample: Codable, Equatable, Sendable {
    public let classification: BridgeBurstClassification
    public let elapsedMilliseconds: Double

    public init(classification: BridgeBurstClassification, elapsedMilliseconds: Double) {
        self.classification = classification
        self.elapsedMilliseconds = elapsedMilliseconds
    }
}

public struct BridgeBurstSummary: Codable, Equatable, Sendable {
    public let requestCount: Int
    public let successCount: Int
    public let toolErrorCount: Int
    public let protocolErrorCount: Int
    public let processExitCount: Int
    public let timeoutCount: Int
    public let successfulRequestP50Milliseconds: Double?
    public let successfulRequestP95Milliseconds: Double?
    public let successfulRequestMaximumMilliseconds: Double?
    public let batchCount: Int
    public let batchP50Milliseconds: Double?
    public let batchP95Milliseconds: Double?
    public let batchMaximumMilliseconds: Double?

    public init(samples: [BridgeBurstSample], batchElapsedMilliseconds: [Double] = []) {
        requestCount = samples.count
        successCount = samples.count { $0.classification == .success }
        toolErrorCount = samples.count { $0.classification == .toolError }
        protocolErrorCount = samples.count { $0.classification == .protocolError }
        processExitCount = samples.count { $0.classification == .processExit }
        timeoutCount = samples.count { $0.classification == .timeout }

        let successful = samples
            .filter { $0.classification == .success }
            .map(\.elapsedMilliseconds)
        successfulRequestP50Milliseconds = Self.percentile(successful, percentile: 0.50)
        successfulRequestP95Milliseconds = Self.percentile(successful, percentile: 0.95)
        successfulRequestMaximumMilliseconds = successful.max()

        batchCount = batchElapsedMilliseconds.count
        batchP50Milliseconds = Self.percentile(batchElapsedMilliseconds, percentile: 0.50)
        batchP95Milliseconds = Self.percentile(batchElapsedMilliseconds, percentile: 0.95)
        batchMaximumMilliseconds = batchElapsedMilliseconds.max()
    }

    static func percentile(_ values: [Double], percentile: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
        return sorted[min(sorted.count - 1, rank - 1)]
    }
}

public struct BridgeBurstLevelReport: Codable, Equatable, Sendable {
    public let concurrency: Int
    public let summary: BridgeBurstSummary

    public init(concurrency: Int, summary: BridgeBurstSummary) {
        self.concurrency = concurrency
        self.summary = summary
    }
}

public struct BridgeBurstReport: Codable, Equatable, Sendable {
    public let profile: BridgeBurstProfile
    public let scenario: BridgeBurstScenario
    public let responseTimeoutMilliseconds: Int
    public let elapsedSeconds: Double
    public let sequential: BridgeBurstSummary
    public let bursts: [BridgeBurstLevelReport]

    public init(
        profile: BridgeBurstProfile,
        scenario: BridgeBurstScenario,
        responseTimeoutMilliseconds: Int,
        elapsedSeconds: Double,
        sequential: BridgeBurstSummary,
        bursts: [BridgeBurstLevelReport]
    ) {
        self.profile = profile
        self.scenario = scenario
        self.responseTimeoutMilliseconds = responseTimeoutMilliseconds
        self.elapsedSeconds = elapsedSeconds
        self.sequential = sequential
        self.bursts = bursts
    }
}

public struct BridgeBurstArtifact: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String
    public let gitCommit: String
    public let productionFingerprint: String
    public let serverBinarySHA256: String
    public let report: BridgeBurstReport

    public init(
        schemaVersion: Int = 2,
        generatedAt: String,
        gitCommit: String,
        productionFingerprint: String,
        serverBinarySHA256: String,
        report: BridgeBurstReport
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.gitCommit = gitCommit
        self.productionFingerprint = productionFingerprint
        self.serverBinarySHA256 = serverBinarySHA256
        self.report = report
    }
}

public enum BridgeBurstRunError: Error, LocalizedError, Sendable {
    case warmupFailed(BridgeBurstClassification)

    public var errorDescription: String? {
        switch self {
        case .warmupFailed(let classification):
            "Bridge burst warmup failed with \(classification.rawValue)."
        }
    }
}

public struct BridgeBurstRunner: Sendable {
    public let transport: any BridgeBurstTransport
    public let responseTimeout: Duration

    public init(
        transport: any BridgeBurstTransport,
        responseTimeout: Duration = .seconds(15)
    ) {
        self.transport = transport
        self.responseTimeout = responseTimeout
    }

    public func run(
        profile: BridgeBurstProfile,
        scenario: BridgeBurstScenario,
        fixtureTaskID: String?,
        progress: @Sendable (String) -> Void = { _ in }
    ) async throws -> BridgeBurstReport {
        let arguments = try scenario.arguments(fixtureTaskID: fixtureTaskID)
        let runClock = ContinuousClock()
        let runStarted = runClock.now

        try await transport.start()
        do {
            try await transport.initialize(timeout: .seconds(10))
            progress("MCP initialized")

            var nextRequestID = 100
            for _ in 0..<profile.warmupCount {
                let request = BridgeBurstRequest(
                    id: nextRequestID,
                    toolName: scenario.toolName,
                    arguments: arguments
                )
                nextRequestID += 1
                let sample = await measure(request)
                guard sample.classification == .success else {
                    throw BridgeBurstRunError.warmupFailed(sample.classification)
                }
            }
            progress("Warmup complete")

            var sequentialSamples: [BridgeBurstSample] = []
            var consecutiveInfrastructureFailures = 0
            let sequentialSampleCount = scenario.sequentialSampleCount(for: profile)
            for sampleNumber in 1...sequentialSampleCount {
                try Task.checkCancellation()
                let request = BridgeBurstRequest(
                    id: nextRequestID,
                    toolName: scenario.toolName,
                    arguments: arguments
                )
                nextRequestID += 1
                let sample = await measure(request)
                sequentialSamples.append(sample)
                progress(
                    "Sequential sample \(sampleNumber)/\(sequentialSampleCount) "
                        + "\(sample.classification.rawValue) "
                        + "\(String(format: "%.2f", sample.elapsedMilliseconds))ms"
                )
                if sample.classification == .success {
                    consecutiveInfrastructureFailures = 0
                } else if sample.classification != .toolError {
                    consecutiveInfrastructureFailures += 1
                }
                if consecutiveInfrastructureFailures >= 2 {
                    progress("Sequential baseline stopped after two infrastructure failures")
                    break
                }
            }
            progress("Sequential baseline complete")

            var samplesByBurst = Dictionary(
                uniqueKeysWithValues: profile.burstSizes.map { ($0, [BridgeBurstSample]()) }
            )
            var batchDurationsByBurst = Dictionary(
                uniqueKeysWithValues: profile.burstSizes.map { ($0, [Double]()) }
            )
            let burstPhaseStarted = runClock.now

            repeat {
                for burstSize in profile.burstSizes {
                    try Task.checkCancellation()
                    let requests = (0..<burstSize).map { _ -> BridgeBurstRequest in
                        defer { nextRequestID += 1 }
                        return BridgeBurstRequest(
                            id: nextRequestID,
                            toolName: scenario.toolName,
                            arguments: arguments
                        )
                    }
                    let batchStarted = runClock.now
                    let samples = await withTaskGroup(of: BridgeBurstSample.self) { group in
                        for request in requests {
                            group.addTask {
                                await measure(request)
                            }
                        }
                        var collected: [BridgeBurstSample] = []
                        for await sample in group {
                            collected.append(sample)
                        }
                        return collected
                    }
                    samplesByBurst[burstSize, default: []].append(contentsOf: samples)
                    let batchElapsed = batchStarted.duration(to: runClock.now).milliseconds
                    batchDurationsByBurst[burstSize, default: []].append(batchElapsed)
                    let successes = samples.count { $0.classification == .success }
                    progress(
                        "Burst \(burstSize) complete success=\(successes)/\(samples.count) "
                            + "elapsed=\(String(format: "%.2f", batchElapsed))ms"
                    )
                }
            } while shouldContinueBurstPhase(
                targetDuration: profile.targetBurstDuration,
                elapsed: burstPhaseStarted.duration(to: runClock.now)
            )

            let report = BridgeBurstReport(
                profile: profile,
                scenario: scenario,
                responseTimeoutMilliseconds: Int(responseTimeout.milliseconds.rounded()),
                elapsedSeconds: runStarted.duration(to: runClock.now).seconds,
                sequential: BridgeBurstSummary(samples: sequentialSamples),
                bursts: profile.burstSizes.map { burstSize in
                    BridgeBurstLevelReport(
                        concurrency: burstSize,
                        summary: BridgeBurstSummary(
                            samples: samplesByBurst[burstSize, default: []],
                            batchElapsedMilliseconds: batchDurationsByBurst[burstSize, default: []]
                        )
                    )
                }
            )
            await transport.stop()
            return report
        } catch {
            await transport.stop()
            throw error
        }
    }

    private func measure(_ request: BridgeBurstRequest) async -> BridgeBurstSample {
        let clock = ContinuousClock()
        let started = clock.now
        let classification: BridgeBurstClassification
        do {
            classification = try await transport.call(request, timeout: responseTimeout)
        } catch let error as BridgeBurstTransportError {
            classification = error.classification
        } catch is CancellationError {
            classification = .timeout
        } catch {
            classification = .protocolError
        }
        return BridgeBurstSample(
            classification: classification,
            elapsedMilliseconds: started.duration(to: clock.now).milliseconds
        )
    }

    private func shouldContinueBurstPhase(
        targetDuration: Duration?,
        elapsed: Duration
    ) -> Bool {
        guard let targetDuration else { return false }
        return elapsed < targetDuration
    }
}

public enum MCPResponseClassifier {
    public static func classify(_ data: Data) -> BridgeBurstClassification {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .protocolError
        }
        if object["error"] != nil {
            return .protocolError
        }
        guard let result = object["result"] as? [String: Any] else {
            return .protocolError
        }
        return result["isError"] as? Bool == true ? .toolError : .success
    }
}

public actor MCPResponseBroker {
    private var expectedIDs = Set<Int>()
    private var bufferedResponses: [Int: Data] = [:]
    private var waiters: [Int: CheckedContinuation<Data, any Error>] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]
    private var lineBuffer = Data()
    private var terminalError: BridgeBurstTransportError?

    public init() {}

    public func expect(_ id: Int) throws {
        if let terminalError {
            throw terminalError
        }
        expectedIDs.insert(id)
    }

    public func receive(chunk: Data) {
        guard terminalError == nil else { return }
        lineBuffer.append(chunk)
        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = Data(lineBuffer[..<newline])
            lineBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            receive(line: line)
        }
    }

    public func response(for id: Int, timeout: Duration) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let terminalError {
                    continuation.resume(throwing: terminalError)
                    return
                }
                if let buffered = bufferedResponses.removeValue(forKey: id) {
                    expectedIDs.remove(id)
                    continuation.resume(returning: buffered)
                    return
                }
                waiters[id] = continuation
                timeoutTasks[id] = Task { @concurrent [weak self] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    await self?.expire(id)
                }
            }
        } onCancel: {
            Task { @concurrent in
                await cancel(id)
            }
        }
    }

    public func finish(_ error: BridgeBurstTransportError) {
        guard terminalError == nil else { return }
        terminalError = error
        lineBuffer.removeAll(keepingCapacity: false)
        bufferedResponses.removeAll(keepingCapacity: false)
        expectedIDs.removeAll(keepingCapacity: false)
        for task in timeoutTasks.values {
            task.cancel()
        }
        timeoutTasks.removeAll(keepingCapacity: false)
        let pending = waiters.values
        waiters.removeAll(keepingCapacity: false)
        for continuation in pending {
            continuation.resume(throwing: error)
        }
    }

    private func receive(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let id = object["id"] as? Int else {
            finish(.protocolError)
            return
        }
        guard expectedIDs.contains(id) else { return }
        timeoutTasks.removeValue(forKey: id)?.cancel()
        if let continuation = waiters.removeValue(forKey: id) {
            expectedIDs.remove(id)
            continuation.resume(returning: line)
        } else {
            bufferedResponses[id] = line
        }
    }

    private func expire(_ id: Int) {
        timeoutTasks.removeValue(forKey: id)?.cancel()
        expectedIDs.remove(id)
        bufferedResponses.removeValue(forKey: id)
        waiters.removeValue(forKey: id)?.resume(throwing: BridgeBurstTransportError.timeout)
    }

    private func cancel(_ id: Int) {
        timeoutTasks.removeValue(forKey: id)?.cancel()
        expectedIDs.remove(id)
        bufferedResponses.removeValue(forKey: id)
        waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }
}

extension Duration {
    fileprivate var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }

    fileprivate var seconds: Double {
        milliseconds / 1_000
    }
}
