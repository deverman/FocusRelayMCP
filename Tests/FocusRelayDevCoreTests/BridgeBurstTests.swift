import Foundation
import FocusRelayDevCore
import Testing

@Test
func bridgeBurstProfilesAreExplicitAndBounded() {
    #expect(BridgeBurstProfile.allCases.map(\.rawValue) == [
        "canary", "smoke", "release", "stress"
    ])
    #expect(BridgeBurstProfile.canary.targetBurstDuration == nil)
    #expect(BridgeBurstProfile.smoke.targetBurstDuration == .seconds(600))
    #expect(BridgeBurstProfile.release.targetBurstDuration == .seconds(5_400))
    #expect(BridgeBurstProfile.stress.targetBurstDuration == .seconds(10_800))
    #expect(BridgeBurstProfile.canary.burstSizes == [2, 4, 7, 12])
    #expect(BridgeBurstScenario.taskCounts.sequentialSampleCount(for: .canary) == 12)
    #expect(BridgeBurstScenario.completionPreview.sequentialSampleCount(for: .canary) == 3)
}

@Test
func bridgeBurstResponseDeadlineDefaultsToFifteenSecondsAndAcceptsSixty() throws {
    let defaultDeadline = try BridgeBurstResponseDeadline()
    let coordinatorDeadline = try BridgeBurstResponseDeadline(seconds: 60)

    #expect(defaultDeadline.milliseconds == 15_000)
    #expect(defaultDeadline.duration == .seconds(15))
    #expect(coordinatorDeadline.milliseconds == 60_000)
    #expect(coordinatorDeadline.duration == .seconds(60))
}

@Test
func bridgeBurstResponseDeadlineRejectsInvalidValues() {
    for seconds in [0, -1, 120.1, .infinity, -.infinity, .nan] {
        #expect(throws: BridgeBurstConfigurationError.self) {
            try BridgeBurstResponseDeadline(seconds: seconds)
        }
    }
}

@Test
func completionBurstRequiresFixtureAndRemainsPreviewOnly() throws {
    #expect(throws: BridgeBurstConfigurationError.self) {
        try BridgeBurstScenario.completionPreview.arguments(fixtureTaskID: nil)
    }

    let arguments = try BridgeBurstScenario.completionPreview.arguments(
        fixtureTaskID: "private-fixture"
    )
    let encoded = try JSONEncoder().encode(arguments)
    let object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    #expect(object["operation"] as? String == "set_completion")
    #expect(object["targetIDs"] as? [String] == ["private-fixture"])
    #expect(object["previewOnly"] as? Bool == true)
    #expect(object["verify"] == nil)
}

@Test
func responseClassifierSeparatesToolAndProtocolErrors() {
    #expect(MCPResponseClassifier.classify(
        Data(#"{"jsonrpc":"2.0","id":1,"result":{"content":[],"isError":false}}"#.utf8)
    ) == .success)
    #expect(MCPResponseClassifier.classify(
        Data(#"{"jsonrpc":"2.0","id":1,"result":{"content":[],"isError":true}}"#.utf8)
    ) == .toolError)
    #expect(MCPResponseClassifier.classify(
        Data(#"{"jsonrpc":"2.0","id":1,"error":{"code":-32603}}"#.utf8)
    ) == .protocolError)
    #expect(MCPResponseClassifier.classify(Data("not-json".utf8)) == .protocolError)
}

@Test
func responseBrokerCorrelatesOutOfOrderLines() async throws {
    let broker = MCPResponseBroker()
    try await broker.expect(1)
    try await broker.expect(2)

    async let first = broker.response(for: 1, timeout: .seconds(1))
    async let second = broker.response(for: 2, timeout: .seconds(1))

    await broker.receive(chunk: Data(
        """
        {"jsonrpc":"2.0","id":2,"result":{"content":[]}}
        {"jsonrpc":"2.0","id":1,"result":{"content":[]}}

        """.utf8
    ))

    let firstObject = try #require(
        JSONSerialization.jsonObject(with: try await first) as? [String: Any]
    )
    let secondObject = try #require(
        JSONSerialization.jsonObject(with: try await second) as? [String: Any]
    )
    #expect(firstObject["id"] as? Int == 1)
    #expect(secondObject["id"] as? Int == 2)
}

@Test
func responseBrokerCancellationRemovesPendingWaiter() async throws {
    let broker = MCPResponseBroker()
    try await broker.expect(7)
    let task = Task {
        try await broker.response(for: 7, timeout: .seconds(30))
    }
    await Task.yield()
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Expected cancellation")
    } catch is CancellationError {
        // Expected.
    }

    await broker.receive(chunk: Data(
        #"{"jsonrpc":"2.0","id":7,"result":{"content":[]}}"#.utf8
    ))
}

@Test
func responseBrokerEnforcesDeadline() async throws {
    let broker = MCPResponseBroker()
    try await broker.expect(9)
    do {
        _ = try await broker.response(for: 9, timeout: .zero)
        Issue.record("Expected timeout")
    } catch let error as BridgeBurstTransportError {
        #expect(error.classification == .timeout)
    }
}

@Test
func summaryUsesSuccessfulLatencyAndCountsEveryFailure() {
    let samples = [
        BridgeBurstSample(classification: .success, elapsedMilliseconds: 10),
        BridgeBurstSample(classification: .success, elapsedMilliseconds: 20),
        BridgeBurstSample(classification: .success, elapsedMilliseconds: 30),
        BridgeBurstSample(classification: .toolError, elapsedMilliseconds: 40),
        BridgeBurstSample(classification: .protocolError, elapsedMilliseconds: 50),
        BridgeBurstSample(classification: .processExit, elapsedMilliseconds: 60),
        BridgeBurstSample(classification: .timeout, elapsedMilliseconds: 70)
    ]
    let summary = BridgeBurstSummary(
        samples: samples,
        batchElapsedMilliseconds: [100, 200, 300]
    )
    #expect(summary.requestCount == 7)
    #expect(summary.successCount == 3)
    #expect(summary.toolErrorCount == 1)
    #expect(summary.protocolErrorCount == 1)
    #expect(summary.processExitCount == 1)
    #expect(summary.timeoutCount == 1)
    #expect(summary.successfulRequestP50Milliseconds == 20)
    #expect(summary.successfulRequestP95Milliseconds == 30)
    #expect(summary.batchP50Milliseconds == 200)
    #expect(summary.batchP95Milliseconds == 300)
}

@Test
func canaryRunnerInitializesBeforeUniqueConcurrentCalls() async throws {
    let transport = FakeBurstTransport()
    let runner = BridgeBurstRunner(transport: transport, responseTimeout: .seconds(1))
    let report = try await runner.run(
        profile: .canary,
        scenario: .taskCounts,
        fixtureTaskID: nil
    )

    let state = await transport.state()
    #expect(state.didStart)
    #expect(state.didInitialize)
    #expect(state.didStop)
    #expect(state.callIDs.count == 38)
    #expect(Set(state.callIDs).count == 38)
    #expect(state.maxActiveCalls == 12)
    #expect(report.sequential.requestCount == 12)
    #expect(report.bursts.map(\.concurrency) == [2, 4, 7, 12])
    #expect(report.bursts.map(\.summary.requestCount) == [2, 4, 7, 12])
    #expect(report.responseTimeoutMilliseconds == 1_000)
}

@Test
func runnerPassesSelectedSixtySecondDeadlineToEveryMCPCall() async throws {
    let transport = FakeBurstTransport()
    let runner = BridgeBurstRunner(
        transport: transport,
        responseTimeout: .seconds(60)
    )
    let report = try await runner.run(
        profile: .canary,
        scenario: .taskCounts,
        fixtureTaskID: nil
    )

    let state = await transport.state()
    #expect(report.responseTimeoutMilliseconds == 60_000)
    #expect(state.callTimeouts.count == 38)
    #expect(state.callTimeouts.allSatisfy { $0 == .seconds(60) })
}

@Test
func canaryStopsSequentialBaselineAfterTwoInfrastructureFailures() async throws {
    let transport = FailingAfterWarmupTransport()
    let runner = BridgeBurstRunner(transport: transport, responseTimeout: .seconds(1))
    let report = try await runner.run(
        profile: .canary,
        scenario: .taskCounts,
        fixtureTaskID: nil
    )

    #expect(report.sequential.requestCount == 2)
    #expect(report.sequential.timeoutCount == 2)
    #expect(report.bursts.map(\.summary.requestCount) == [2, 4, 7, 12])
    #expect(report.bursts.map(\.summary.timeoutCount) == [2, 4, 7, 12])
}

@Test
func artifactContainsOnlySanitizedAggregateFields() throws {
    let report = BridgeBurstReport(
        profile: .canary,
        scenario: .completionPreview,
        responseTimeoutMilliseconds: 60_000,
        elapsedSeconds: 1,
        sequential: BridgeBurstSummary(samples: [
            BridgeBurstSample(classification: .success, elapsedMilliseconds: 1)
        ]),
        bursts: []
    )
    let artifact = BridgeBurstArtifact(
        generatedAt: "2026-07-28T00:00:00Z",
        gitCommit: "commit",
        productionFingerprint: "fingerprint",
        serverBinarySHA256: "hash",
        report: report
    )
    let data = try JSONEncoder().encode(artifact)
    let decoded = try JSONDecoder().decode(BridgeBurstArtifact.self, from: data)
    let text = String(decoding: data, as: UTF8.self)
    #expect(artifact.schemaVersion == 2)
    #expect(decoded == artifact)
    #expect(decoded.report.responseTimeoutMilliseconds == 60_000)
    #expect(text.contains(#""responseTimeoutMilliseconds":60000"#))
    #expect(!text.contains("private-fixture"))
    #expect(!text.contains("/Users/"))
    #expect(!text.contains("targetIDs"))
    #expect(!text.contains("arguments"))
    #expect(!text.contains("content"))
}

private actor FailingAfterWarmupTransport: BridgeBurstTransport {
    private var callCount = 0

    func start() {}
    func initialize(timeout _: Duration) {}

    func call(
        _: BridgeBurstRequest,
        timeout _: Duration
    ) -> BridgeBurstClassification {
        defer { callCount += 1 }
        return callCount == 0 ? .success : .timeout
    }

    func stop() {}
}

private actor FakeBurstTransport: BridgeBurstTransport {
    struct State: Sendable {
        let didStart: Bool
        let didInitialize: Bool
        let didStop: Bool
        let callIDs: [Int]
        let callTimeouts: [Duration]
        let maxActiveCalls: Int
    }

    private var didStart = false
    private var didInitialize = false
    private var didStop = false
    private var callIDs: [Int] = []
    private var callTimeouts: [Duration] = []
    private var activeCalls = 0
    private var maxActiveCalls = 0

    func start() {
        didStart = true
    }

    func initialize(timeout _: Duration) throws {
        guard didStart else { throw BridgeBurstTransportError.protocolError }
        didInitialize = true
    }

    func call(
        _ request: BridgeBurstRequest,
        timeout: Duration
    ) async throws -> BridgeBurstClassification {
        guard didInitialize else { throw BridgeBurstTransportError.protocolError }
        callIDs.append(request.id)
        callTimeouts.append(timeout)
        activeCalls += 1
        maxActiveCalls = max(maxActiveCalls, activeCalls)
        await Task.yield()
        activeCalls -= 1
        return .success
    }

    func stop() {
        didStop = true
    }

    func state() -> State {
        State(
            didStart: didStart,
            didInitialize: didInitialize,
            didStop: didStop,
            callIDs: callIDs,
            callTimeouts: callTimeouts,
            maxActiveCalls: maxActiveCalls
        )
    }
}
