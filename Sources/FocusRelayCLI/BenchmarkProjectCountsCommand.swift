#if DEBUG
import ArgumentParser
import Foundation
import OmniFocusAutomation
import OmniFocusCore

struct BenchmarkProjectCounts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark-project-counts",
        abstract: "Benchmark get_project_counts through the Bridge plugin.",
        aliases: ["benchmark_get_project_counts"]
    )

    @Option(name: .customLong("duration-hours"), help: "Measured phase duration in hours.")
    var durationHours: Double = 3.0

    @Option(name: .customLong("warmup-calls"), help: "Warmup calls before measured runs.")
    var warmupCalls: Int = 20

    @Option(name: .customLong("interval-ms"), help: "Minimum start-to-start interval between calls in milliseconds.")
    var intervalMS: Int = 1200

    @Option(name: .customLong("cooldown-ms"), help: "Cooldown delay after failed/timeout calls in milliseconds.")
    var cooldownMS: Int = 5000

    @Option(name: .customLong("memory-interval-seconds"), help: "RSS sample interval in seconds.")
    var memoryIntervalSeconds: Int = 30

    @Option(name: .customLong("completed-after"), help: "Fixed ISO8601 anchor for completed-date scenario.")
    var completedAfter: String = "2020-01-01T00:00:00Z"

    @Option(name: .customLong("output-dir"), help: "Output directory. Defaults to .build/benchmarks/<timestamp>.")
    var outputDir: String?

    @Flag(name: .customLong("run-preflight"), help: "Run process cleanup and OmniFocus restart before benchmarking.")
    var performPreflight: Bool = false

    func run() async throws {
        try validateBenchmarkArguments(
            durationHours: durationHours,
            warmupCalls: warmupCalls,
            intervalMS: intervalMS,
            cooldownMS: cooldownMS,
            memoryIntervalSeconds: memoryIntervalSeconds
        )
        let completedAfterDate = try ISO8601DateParser.parse(completedAfter, argumentName: "--completed-after")
        let scenarios = projectCountBenchmarkScenarios(completedAfter: completedAfterDate)
        let directoryURL = try benchmarkOutputDirectory(customPath: outputDir)
        let rawURL = directoryURL.appendingPathComponent("raw.jsonl")
        let memoryURL = directoryURL.appendingPathComponent("memory.csv")
        let summaryURL = directoryURL.appendingPathComponent("summary.md")
        let timeoutDiagnosticsURL = directoryURL.appendingPathComponent("timeout-diagnostics.jsonl")
        try initializeBenchmarkArtifacts(rawURL: rawURL, memoryURL: memoryURL, timeoutDiagnosticsURL: timeoutDiagnosticsURL)

        print("Benchmark output directory: \(directoryURL.path)")
        print("Scenarios: \(scenarios.map(\.name).joined(separator: ", "))")
        if performPreflight {
            runBenchmarkPreflight()
        }

        let memoryTask = startBenchmarkMemorySampling(memoryURL: memoryURL, intervalSeconds: memoryIntervalSeconds)
        defer { memoryTask.cancel() }

        let service = OmniFocusBridgeService()
        var callIndex = 0
        if warmupCalls > 0 {
            print("Warmup phase: \(warmupCalls) calls")
            for index in 0..<warmupCalls {
                let scenario = scenarios[index % scenarios.count]
                let event: CountBenchmarkEvent<OmniFocusCore.ProjectCounts> = try await runCountBenchmarkCall(
                    scenario: scenario.name,
                    phase: "warmup",
                    timeoutDiagnosticsURL: timeoutDiagnosticsURL,
                    intervalMS: intervalMS,
                    cooldownMS: cooldownMS,
                    callIndex: &callIndex
                ) {
                    try await service.getProjectCounts(filter: scenario.filter)
                }
                try appendBenchmarkJSONLine(event, to: rawURL)
                if event.timeout {
                    await runBenchmarkTimeoutRecoveryGate()
                }
            }
        }

        let measuredStart = Date()
        let measuredEnd = measuredStart.addingTimeInterval(durationHours * 3600)
        print("Measured phase started at \(benchmarkISO8601(measuredStart)); ending at \(benchmarkISO8601(measuredEnd))")
        var overallStats = BenchmarkStats()
        var scenarioStats: [String: BenchmarkStats] = [:]
        var scenarioIndex = 0
        while Date() < measuredEnd {
            let scenario = scenarios[scenarioIndex % scenarios.count]
            scenarioIndex += 1
            let event: CountBenchmarkEvent<OmniFocusCore.ProjectCounts> = try await runCountBenchmarkCall(
                scenario: scenario.name,
                phase: "measured",
                timeoutDiagnosticsURL: timeoutDiagnosticsURL,
                intervalMS: intervalMS,
                cooldownMS: cooldownMS,
                callIndex: &callIndex
            ) {
                try await service.getProjectCounts(filter: scenario.filter)
            }
            try appendBenchmarkJSONLine(event, to: rawURL)
            ingestBenchmarkEvent(
                scenario: event.scenario,
                ok: event.ok,
                timeout: event.timeout,
                latencyMs: event.latencyMs,
                overall: &overallStats,
                scenarios: &scenarioStats
            )
            if event.timeout {
                await runBenchmarkTimeoutRecoveryGate()
            }
        }

        let summary = renderCountBenchmarkSummary(
            title: "get_project_counts",
            startedAt: measuredStart,
            endedAt: Date(),
            durationHours: durationHours,
            warmupCalls: warmupCalls,
            intervalMS: intervalMS,
            cooldownMS: cooldownMS,
            memoryIntervalSeconds: memoryIntervalSeconds,
            scenarioNames: scenarios.map(\.name),
            overall: overallStats,
            scenarios: scenarioStats,
            memoryURL: memoryURL,
            timeoutDiagnosticsURL: timeoutDiagnosticsURL
        )
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)

        print("Benchmark complete.")
        print("Raw data: \(rawURL.path)")
        print("Memory samples: \(memoryURL.path)")
        print("Summary: \(summaryURL.path)")
    }
}

private struct ProjectCountBenchmarkScenario {
    let name: String
    let filter: TaskFilter
}

private func projectCountBenchmarkScenarios(completedAfter: Date) -> [ProjectCountBenchmarkScenario] {
    [
        ProjectCountBenchmarkScenario(name: "project_view_remaining", filter: TaskFilter(projectView: "remaining")),
        ProjectCountBenchmarkScenario(name: "project_view_active", filter: TaskFilter(projectView: "active")),
        ProjectCountBenchmarkScenario(name: "project_view_available", filter: TaskFilter(projectView: "available")),
        ProjectCountBenchmarkScenario(name: "project_view_everything", filter: TaskFilter(projectView: "everything")),
        ProjectCountBenchmarkScenario(
            name: "completed_after_anchor",
            filter: TaskFilter(completed: true, completedAfter: completedAfter)
        )
    ]
}
#endif
