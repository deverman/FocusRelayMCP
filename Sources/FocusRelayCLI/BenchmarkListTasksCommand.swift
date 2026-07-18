#if DEBUG
import ArgumentParser
import Foundation
import OmniFocusAutomation
import OmniFocusCore

struct BenchmarkListTasks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark-list-tasks",
        abstract: "Benchmark list_tasks through the Bridge plugin.",
        aliases: ["benchmark_list_tasks"]
    )

    @Option(name: .customLong("duration-hours"), help: "Measured phase duration in hours.")
    var durationHours: Double = 3.0

    @Option(name: .customLong("warmup-calls"), help: "Warmup calls before measured runs.")
    var warmupCalls: Int = 20

    @Option(name: .customLong("interval-ms"), help: "Minimum start-to-start interval between calls in milliseconds.")
    var intervalMS: Int = 1500

    @Option(name: .customLong("cooldown-ms"), help: "Cooldown delay after failed/timeout calls in milliseconds.")
    var cooldownMS: Int = 3000

    @Option(name: .customLong("completed-after"), help: "Fixed ISO8601 anchor for completed-date scenario.")
    var completedAfter: String = "2020-01-01T00:00:00Z"

    @Option(name: .customLong("output-dir"), help: "Output directory. Defaults to .build/benchmarks/<timestamp>.")
    var outputDir: String?

    func run() async throws {
        try validateBenchmarkArguments(
            durationHours: durationHours,
            warmupCalls: warmupCalls,
            intervalMS: intervalMS,
            cooldownMS: cooldownMS
        )
        let completedAfterDate = try ISO8601DateParser.parse(completedAfter, argumentName: "--completed-after")
        let scenarios = listTaskScenarios(completedAfter: completedAfterDate)
        let outputURL = try benchmarkOutputDirectory(customPath: outputDir, defaultPrefix: "list-tasks")
        let rawURL = outputURL.appendingPathComponent("raw.jsonl")
        let timeoutDiagnosticsURL = outputURL.appendingPathComponent("timeout-diagnostics.jsonl")
        let summaryURL = outputURL.appendingPathComponent("summary.md")
        try initializeBenchmarkArtifacts(rawURL: rawURL, memoryURL: nil, timeoutDiagnosticsURL: timeoutDiagnosticsURL)

        print("Benchmark output directory: \(outputURL.path)")
        print("Scenarios: \(scenarios.map(\.name).joined(separator: ", "))")

        let service = OmniFocusBridgeService()
        var callIndex = 0
        if warmupCalls > 0 {
            for index in 0..<warmupCalls {
                let scenario = scenarios[benchmarkScenarioIndex(callIndex: index, scenarioCount: scenarios.count)]
                let event = try await listTaskBenchCall(
                    scenario: scenario,
                    phase: "warmup",
                    service: service,
                    timeoutDiagnosticsURL: timeoutDiagnosticsURL,
                    intervalMS: intervalMS,
                    cooldownMS: cooldownMS,
                    callIndex: &callIndex,
                    rawURL: rawURL
                )
                if event.timeout {
                    await runBenchmarkTimeoutRecoveryGate()
                }
            }
        }

        let measuredStart = Date()
        let measuredEnd = measuredStart.addingTimeInterval(durationHours * 3600)
        print("Measured phase started at \(benchmarkISO8601(measuredStart)); ending at \(benchmarkISO8601(measuredEnd))")
        var scenarioStats: [String: BenchmarkStats] = [:]
        var scenarioIndex = 0
        while Date() < measuredEnd {
            let scenario = scenarios[benchmarkScenarioIndex(callIndex: scenarioIndex, scenarioCount: scenarios.count)]
            scenarioIndex += 1
            let event = try await listTaskBenchCall(
                scenario: scenario,
                phase: "measured",
                service: service,
                timeoutDiagnosticsURL: timeoutDiagnosticsURL,
                intervalMS: intervalMS,
                cooldownMS: cooldownMS,
                callIndex: &callIndex,
                rawURL: rawURL
            )
            var stats = scenarioStats[event.scenario] ?? BenchmarkStats()
            stats.ingest(ok: event.ok, timeout: event.timeout, latencyMs: event.latencyMs)
            scenarioStats[event.scenario] = stats
            if event.timeout {
                await runBenchmarkTimeoutRecoveryGate()
            }
        }

        let scenarioNames = scenarios.map(\.name)
        let summary = renderListTaskSummary(
            startedAt: measuredStart,
            endedAt: Date(),
            scenarios: scenarioNames,
            stats: scenarioStats,
            timeoutDiagnosticCount: benchmarkCountLines(in: timeoutDiagnosticsURL)
        )
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)

        let missingCoverage = listTaskMissingMeasuredCoverage(scenarios: scenarioNames, stats: scenarioStats)
        print("Benchmark complete.")
        print("Raw data: \(rawURL.path)")
        print("Summary: \(summaryURL.path)")
        if !missingCoverage.isEmpty {
            throw ValidationError("Measured benchmark coverage is incomplete: \(missingCoverage.joined(separator: ", "))")
        }
    }
}

private struct ListTaskScenario {
    let name: String
    let filter: TaskFilter
}

struct ListTaskEvent: Codable {
    let timestamp: String
    let phase: String
    let callIndex: Int
    let transport: String
    let scenario: String
    let latencyMs: Double
    let ok: Bool
    let timeout: Bool
    let error: String?
    let returnedCount: Int?
    let totalCount: Int?
    let nextCursor: String?
    let firstItemID: String?
    let lastItemID: String?
}

private let listTaskNoMatchSearch = "__focusrelay_benchmark_no_match_7f43d9__"

private func listTaskScenarios(completedAfter: Date) -> [ListTaskScenario] {
    [
        ListTaskScenario(name: "default", filter: TaskFilter(includeTotalCount: true)),
        ListTaskScenario(name: "default_no_total", filter: TaskFilter(includeTotalCount: false)),
        ListTaskScenario(name: "inbox_only", filter: TaskFilter(inboxOnly: true, includeTotalCount: true)),
        ListTaskScenario(name: "inbox_only_no_total", filter: TaskFilter(inboxOnly: true, includeTotalCount: false)),
        ListTaskScenario(name: "available_only", filter: TaskFilter(availableOnly: true, includeTotalCount: true)),
        ListTaskScenario(name: "available_only_no_total", filter: TaskFilter(availableOnly: true, includeTotalCount: false)),
        ListTaskScenario(name: "completed_after_anchor", filter: TaskFilter(completed: true, completedAfter: completedAfter, includeTotalCount: true)),
        ListTaskScenario(name: "flagged_only", filter: TaskFilter(flagged: true, includeTotalCount: true)),
        ListTaskScenario(name: "flagged_only_no_total", filter: TaskFilter(flagged: true, includeTotalCount: false)),
        ListTaskScenario(
            name: "search_no_match",
            filter: TaskFilter(availableOnly: false, inboxView: "everything", search: listTaskNoMatchSearch, includeTotalCount: true)
        )
    ]
}

func benchmarkScenarioIndex(callIndex: Int, scenarioCount: Int) -> Int {
    precondition(callIndex >= 0, "Call index must be non-negative.")
    precondition(scenarioCount > 0, "At least one benchmark scenario is required.")
    return callIndex % scenarioCount
}

private func listTaskBenchCall(
    scenario: ListTaskScenario,
    phase: String,
    service: OmniFocusBridgeService,
    timeoutDiagnosticsURL: URL,
    intervalMS: Int,
    cooldownMS: Int,
    callIndex: inout Int,
    rawURL: URL
) async throws -> ListTaskEvent {
    callIndex += 1
    let started = Date()
    do {
        let page = try await service.listTasks(
            filter: scenario.filter,
            page: PageRequest(limit: 50),
            fields: ["id", "name", "completed", "available", "completionDate"]
        )
        let latencyMs = Date().timeIntervalSince(started) * 1000
        try await enforceBenchmarkInterval(started: started, intervalMS: intervalMS)
        let event = ListTaskEvent(
            timestamp: benchmarkISO8601Now(),
            phase: phase,
            callIndex: callIndex,
            transport: benchmarkTransport,
            scenario: scenario.name,
            latencyMs: latencyMs,
            ok: true,
            timeout: false,
            error: nil,
            returnedCount: page.returnedCount,
            totalCount: page.totalCount,
            nextCursor: page.nextCursor,
            firstItemID: page.items.first?.id,
            lastItemID: page.items.last?.id
        )
        try appendBenchmarkJSONLine(event, to: rawURL)
        return event
    } catch {
        let latencyMs = Date().timeIntervalSince(started) * 1000
        let timeout = isBenchmarkTimeout(error)
        try await enforceBenchmarkInterval(started: started, intervalMS: intervalMS)
        if cooldownMS > 0 {
            try? await Task.sleep(nanoseconds: UInt64(cooldownMS) * 1_000_000)
        }
        if timeout {
            let diagnostic = captureBenchmarkTimeoutDiagnostic(
                scenario: scenario.name,
                phase: phase,
                callIndex: callIndex,
                latencyMs: latencyMs,
                errorMessage: error.localizedDescription
            )
            try? appendBenchmarkJSONLine(diagnostic, to: timeoutDiagnosticsURL)
        }
        let event = ListTaskEvent(
            timestamp: benchmarkISO8601Now(),
            phase: phase,
            callIndex: callIndex,
            transport: benchmarkTransport,
            scenario: scenario.name,
            latencyMs: latencyMs,
            ok: false,
            timeout: timeout,
            error: error.localizedDescription,
            returnedCount: nil,
            totalCount: nil,
            nextCursor: nil,
            firstItemID: nil,
            lastItemID: nil
        )
        try appendBenchmarkJSONLine(event, to: rawURL)
        return event
    }
}

func listTaskMissingMeasuredCoverage(
    scenarios: [String],
    stats: [String: BenchmarkStats]
) -> [String] {
    scenarios.compactMap { scenario in
        let scoped = stats[scenario] ?? BenchmarkStats()
        return scoped.success + scoped.errors == 0 ? "\(scenario):\(benchmarkTransport)" : nil
    }
}

private func renderListTaskSummary(
    startedAt: Date,
    endedAt: Date,
    scenarios: [String],
    stats: [String: BenchmarkStats],
    timeoutDiagnosticCount: Int
) -> String {
    var lines = [
        "# list_tasks Benchmark Summary",
        "",
        "- Started: \(benchmarkISO8601(startedAt))",
        "- Ended: \(benchmarkISO8601(endedAt))",
        "- Scenarios: \(scenarios.joined(separator: ", "))"
    ]
    let missingCoverage = listTaskMissingMeasuredCoverage(scenarios: scenarios, stats: stats)
    lines.append("- Measured coverage complete: \(missingCoverage.isEmpty ? "yes" : "no")")
    if !missingCoverage.isEmpty {
        lines.append("- Missing measured coverage: \(missingCoverage.joined(separator: ", "))")
    }
    lines.append("")
    lines.append("## Scenario Stats")
    lines.append("")
    for scenario in scenarios {
        let scoped = stats[scenario] ?? BenchmarkStats()
        let total = scoped.success + scoped.errors
        lines.append("### \(scenario)")
        lines.append(
            "- \(benchmarkTransport): total=\(total), success=\(scoped.success), errors=\(scoped.errors), error_rate=\(benchmarkFormatPercentage(benchmarkPercentage(part: scoped.errors, total: total))), timeouts=\(scoped.timeouts), timeout_rate=\(benchmarkFormatPercentage(benchmarkPercentage(part: scoped.timeouts, total: total))), p50_ms=\(benchmarkFormatDouble(benchmarkPercentile(scoped.latencies, p: 0.50))), p95_ms=\(benchmarkFormatDouble(benchmarkPercentile(scoped.latencies, p: 0.95))), p99_ms=\(benchmarkFormatDouble(benchmarkPercentile(scoped.latencies, p: 0.99)))"
        )
        lines.append("")
    }
    lines.append("## Timeout Diagnostics")
    lines.append("")
    lines.append("- Diagnostic entries: \(timeoutDiagnosticCount)")
    return lines.joined(separator: "\n")
}
#endif
