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
        let completedAfterDate = try ISO8601DateParser.parse(completedAfter, argumentName: "--completed-after")
        let scenarios = listTaskScenarios(completedAfter: completedAfterDate)
        let outputURL = try listTaskBenchmarkOutputDirectory(customPath: outputDir)
        let rawURL = outputURL.appendingPathComponent("raw.jsonl")
        let timeoutDiagnosticsURL = outputURL.appendingPathComponent("timeout-diagnostics.jsonl")
        let summaryURL = outputURL.appendingPathComponent("summary.md")
        FileManager.default.createFile(atPath: rawURL.path, contents: nil)
        FileManager.default.createFile(atPath: timeoutDiagnosticsURL.path, contents: nil)

        print("Benchmark output directory: \(outputURL.path)")
        print("Scenarios: \(scenarios.map(\.name).joined(separator: ", "))")

        let pluginService = OmniFocusBridgeService()

        var callIndex = 0
        var stats: [String: [String: ListTaskStats]] = [:]

        if warmupCalls > 0 {
            for _ in 0..<warmupCalls {
                let scenario = scenarios[callIndex % scenarios.count]
                let event = try await listTaskBenchCall(
                    transport: "plugin",
                    scenario: scenario,
                    phase: "warmup",
                    service: pluginService,
                    timeoutDiagnosticsURL: timeoutDiagnosticsURL,
                    intervalMS: intervalMS,
                    cooldownMS: cooldownMS,
                    callIndex: &callIndex,
                    rawURL: rawURL
                )
                if event.timeout {
                    await runListTaskTimeoutRecoveryGate()
                }
            }
        }

        let start = Date()
        let end = start.addingTimeInterval(durationHours * 3600)
        print("Measured phase started at \(listTaskISO8601(start)); ending at \(listTaskISO8601(end))")

        var measuredPairIndex = 0
        while Date() < end {
            let scenario = scenarios[listTaskScenarioIndex(pairIndex: measuredPairIndex, scenarioCount: scenarios.count)]
            measuredPairIndex += 1

            let pluginEvent = try await listTaskBenchCall(
                transport: "plugin",
                scenario: scenario,
                phase: "measured",
                service: pluginService,
                timeoutDiagnosticsURL: timeoutDiagnosticsURL,
                intervalMS: intervalMS,
                cooldownMS: cooldownMS,
                callIndex: &callIndex,
                rawURL: rawURL
            )
            ingestListTaskEvent(pluginEvent, into: &stats)
            if pluginEvent.timeout {
                await runListTaskTimeoutRecoveryGate()
            }

        }

        let summary = renderListTaskSummary(
            startedAt: start,
            endedAt: Date(),
            scenarios: scenarios.map(\.name),
            stats: stats,
            timeoutDiagnosticCount: listTaskCountLines(in: timeoutDiagnosticsURL)
        )
        try summary.write(to: summaryURL, atomically: true, encoding: .utf8)

        let missingCoverage = listTaskMissingMeasuredCoverage(
            scenarios: scenarios.map(\.name),
            stats: stats
        )

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

private struct ListTaskEvent: Codable {
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

struct ListTaskStats {
    var success: Int = 0
    var errors: Int = 0
    var timeouts: Int = 0
    var latencies: [Double] = []

    fileprivate mutating func ingest(_ event: ListTaskEvent) {
        if event.ok {
            success += 1
            latencies.append(event.latencyMs)
        } else {
            errors += 1
            if event.timeout { timeouts += 1 }
        }
    }
}

private let listTaskNoMatchSearch = "__focusrelay_benchmark_no_match_7f43d9__"

private struct ListTaskTimeoutQueueSnapshot: Codable {
    let basePath: String
    let requestsCount: Int
    let locksCount: Int
    let responsesCount: Int
    let requestExists: Bool?
    let lockExists: Bool?
    let responseExists: Bool?
    let sampleRequests: [String]
    let sampleLocks: [String]
    let sampleResponses: [String]
}

private struct ListTaskTimeoutProcessSnapshot: Codable {
    let process: String
    let pid: Int32?
    let rssKB: Int?
}

private struct ListTaskTimeoutBridgeHealthSnapshot: Codable {
    let ok: Bool
    let detail: String
}

private struct ListTaskTimeoutDiagnostic: Codable {
    let timestamp: String
    let transport: String
    let scenario: String
    let phase: String
    let callIndex: Int
    let latencyMs: Double
    let error: String
    let requestId: String?
    let queue: ListTaskTimeoutQueueSnapshot
    let omniFocus: ListTaskTimeoutProcessSnapshot
    let focusrelay: ListTaskTimeoutProcessSnapshot
    let bridgeHealth: ListTaskTimeoutBridgeHealthSnapshot?
}

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

func listTaskScenarioIndex(pairIndex: Int, scenarioCount: Int) -> Int {
    precondition(pairIndex >= 0, "Pair index must be non-negative.")
    precondition(scenarioCount > 0, "At least one benchmark scenario is required.")
    return pairIndex % scenarioCount
}

private func listTaskBenchCall(
    transport: String,
    scenario: ListTaskScenario,
    phase: String,
    service: any OmniFocusService,
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
        let elapsed = Date().timeIntervalSince(started) * 1000
        try await listTaskEnforceInterval(started: started, intervalMS: intervalMS)
        let event = ListTaskEvent(
            timestamp: listTaskISO8601Now(),
            phase: phase,
            callIndex: callIndex,
            transport: transport,
            scenario: scenario.name,
            latencyMs: elapsed,
            ok: true,
            timeout: false,
            error: nil,
            returnedCount: page.returnedCount,
            totalCount: page.totalCount,
            nextCursor: page.nextCursor,
            firstItemID: page.items.first?.id,
            lastItemID: page.items.last?.id
        )
        try listTaskAppendJSONLine(event, to: rawURL)
        return event
    } catch {
        let elapsed = Date().timeIntervalSince(started) * 1000
        let timeout = listTaskIsTimeout(error)
        try await listTaskEnforceInterval(started: started, intervalMS: intervalMS)
        if cooldownMS > 0 {
            try? await Task.sleep(nanoseconds: UInt64(cooldownMS) * 1_000_000)
        }
        if timeout {
            let diagnostic = captureListTaskTimeoutDiagnostic(
                transport: transport,
                scenario: scenario,
                phase: phase,
                callIndex: callIndex,
                latencyMs: elapsed,
                errorMessage: error.localizedDescription
            )
            try? listTaskAppendJSONLine(diagnostic, to: timeoutDiagnosticsURL)
        }
        let event = ListTaskEvent(
            timestamp: listTaskISO8601Now(),
            phase: phase,
            callIndex: callIndex,
            transport: transport,
            scenario: scenario.name,
            latencyMs: elapsed,
            ok: false,
            timeout: timeout,
            error: error.localizedDescription,
            returnedCount: nil,
            totalCount: nil,
            nextCursor: nil,
            firstItemID: nil,
            lastItemID: nil
        )
        try listTaskAppendJSONLine(event, to: rawURL)
        return event
    }
}

private func runListTaskTimeoutRecoveryGate() async {
    let env = ProcessInfo.processInfo.environment
    let recoveryMs = max(0, env["FOCUS_RELAY_TIMEOUT_RECOVERY_MS"].flatMap(Int.init) ?? 10_000)
    if recoveryMs > 0 {
        try? await Task.sleep(nanoseconds: UInt64(recoveryMs) * 1_000_000)
    }
    // Lightweight readiness probe before resuming to reduce timeout cascades.
    _ = try? OmniFocusBridgeService().healthCheck()
}

private func ingestListTaskEvent(_ event: ListTaskEvent, into stats: inout [String: [String: ListTaskStats]]) {
    guard event.phase == "measured" else { return }
    var perScenario = stats[event.scenario] ?? [:]
    var perTransport = perScenario[event.transport] ?? ListTaskStats()
    perTransport.ingest(event)
    perScenario[event.transport] = perTransport
    stats[event.scenario] = perScenario
}

func listTaskMissingMeasuredCoverage(
    scenarios: [String],
    stats: [String: [String: ListTaskStats]]
) -> [String] {
    scenarios.compactMap { scenario in
        let scoped = stats[scenario]?["plugin"] ?? ListTaskStats()
        return scoped.success + scoped.errors == 0 ? "\(scenario):plugin" : nil
    }
}

private func renderListTaskSummary(
    startedAt: Date,
    endedAt: Date,
    scenarios: [String],
    stats: [String: [String: ListTaskStats]],
    timeoutDiagnosticCount: Int
) -> String {
    func p(_ values: [Double], _ q: Double) -> String {
        guard !values.isEmpty else { return "n/a" }
        let sorted = values.sorted()
        let idx = Int(Double(sorted.count - 1) * q)
        return String(format: "%.2f", sorted[idx])
    }

    var lines: [String] = []
    lines.append("# list_tasks Benchmark Summary")
    lines.append("")
    lines.append("- Started: \(listTaskISO8601(startedAt))")
    lines.append("- Ended: \(listTaskISO8601(endedAt))")
    lines.append("- Scenarios: \(scenarios.joined(separator: ", "))")
    let missingCoverage = listTaskMissingMeasuredCoverage(scenarios: scenarios, stats: stats)
    lines.append("- Measured coverage complete: \(missingCoverage.isEmpty ? "yes" : "no")")
    if !missingCoverage.isEmpty {
        lines.append("- Missing measured coverage: \(missingCoverage.joined(separator: ", "))")
    }
    lines.append("")
    lines.append("## Scenario Stats")
    lines.append("")
    for scenario in scenarios {
        lines.append("### \(scenario)")
        let scoped = stats[scenario] ?? [:]
        for transport in ["plugin"] {
            let s = scoped[transport] ?? ListTaskStats()
            let total = s.success + s.errors
            let errorRate = total > 0 ? (Double(s.errors) / Double(total)) * 100.0 : .nan
            let timeoutRate = total > 0 ? (Double(s.timeouts) / Double(total)) * 100.0 : .nan
            let er = errorRate.isFinite ? String(format: "%.2f%%", errorRate) : "n/a"
            let tr = timeoutRate.isFinite ? String(format: "%.2f%%", timeoutRate) : "n/a"
            lines.append("- \(transport): total=\(total), success=\(s.success), errors=\(s.errors), error_rate=\(er), timeouts=\(s.timeouts), timeout_rate=\(tr), p50_ms=\(p(s.latencies, 0.5)), p95_ms=\(p(s.latencies, 0.95)), p99_ms=\(p(s.latencies, 0.99))")
        }
        lines.append("")
    }

    lines.append("## Timeout Diagnostics")
    lines.append("")
    lines.append("- Diagnostic entries: \(timeoutDiagnosticCount)")
    return lines.joined(separator: "\n")
}

private func listTaskBenchmarkOutputDirectory(customPath: String?) throws -> URL {
    if let customPath, !customPath.isEmpty {
        let url = URL(fileURLWithPath: customPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let timestamp = formatter.string(from: Date())
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("benchmarks", isDirectory: true)
        .appendingPathComponent("list-tasks-\(timestamp)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func listTaskAppendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    let data = try encoder.encode(value)
    guard var line = String(data: data, encoding: .utf8) else { return }
    line.append("\n")
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(line.utf8))
}

private func captureListTaskTimeoutDiagnostic(
    transport: String,
    scenario: ListTaskScenario,
    phase: String,
    callIndex: Int,
    latencyMs: Double,
    errorMessage: String
) -> ListTaskTimeoutDiagnostic {
    let requestID = listTaskExtractRequestID(from: errorMessage)
    let baseURL = listTaskDefaultIPCBaseURL()
    let requestsURL = baseURL.appendingPathComponent("requests", isDirectory: true)
    let locksURL = baseURL.appendingPathComponent("locks", isDirectory: true)
    let responsesURL = baseURL.appendingPathComponent("responses", isDirectory: true)
    let queue = ListTaskTimeoutQueueSnapshot(
        basePath: baseURL.path,
        requestsCount: listTaskDirectoryEntryCount(requestsURL),
        locksCount: listTaskDirectoryEntryCount(locksURL),
        responsesCount: listTaskDirectoryEntryCount(responsesURL),
        requestExists: requestID.map { FileManager.default.fileExists(atPath: requestsURL.appendingPathComponent("\($0).json").path) },
        lockExists: requestID.map { FileManager.default.fileExists(atPath: locksURL.appendingPathComponent("\($0).lock").path) },
        responseExists: requestID.map { FileManager.default.fileExists(atPath: responsesURL.appendingPathComponent("\($0).json").path) },
        sampleRequests: listTaskDirectoryEntrySamples(requestsURL),
        sampleLocks: listTaskDirectoryEntrySamples(locksURL),
        sampleResponses: listTaskDirectoryEntrySamples(responsesURL)
    )
    let omniPID = listTaskCurrentOmniFocusPID()
    let benchmarkPID = ProcessInfo.processInfo.processIdentifier
    let bridgeHealth: ListTaskTimeoutBridgeHealthSnapshot?
    if transport == "plugin" {
        if let result = try? OmniFocusBridgeService().healthCheck() {
            bridgeHealth = ListTaskTimeoutBridgeHealthSnapshot(
                ok: result.ok,
                detail: "plugin=\(result.plugin ?? "unknown") version=\(result.version ?? "unknown")"
            )
        } else {
            bridgeHealth = ListTaskTimeoutBridgeHealthSnapshot(
                ok: false,
                detail: "bridge-health-check failed after timeout"
            )
        }
    } else {
        bridgeHealth = nil
    }

    return ListTaskTimeoutDiagnostic(
        timestamp: listTaskISO8601Now(),
        transport: transport,
        scenario: scenario.name,
        phase: phase,
        callIndex: callIndex,
        latencyMs: latencyMs,
        error: errorMessage,
        requestId: requestID,
        queue: queue,
        omniFocus: ListTaskTimeoutProcessSnapshot(
            process: "OmniFocus",
            pid: omniPID,
            rssKB: omniPID.flatMap(listTaskReadRSSKilobytes(pid:))
        ),
        focusrelay: ListTaskTimeoutProcessSnapshot(
            process: "focusrelay",
            pid: benchmarkPID,
            rssKB: listTaskReadRSSKilobytes(pid: benchmarkPID)
        ),
        bridgeHealth: bridgeHealth
    )
}

private func listTaskExtractRequestID(from message: String) -> String? {
    let pattern = #"requestId=([A-F0-9-]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return nil
    }
    let range = NSRange(message.startIndex..<message.endIndex, in: message)
    guard let match = regex.firstMatch(in: message, range: range),
          let matchRange = Range(match.range(at: 1), in: message) else {
        return nil
    }
    return String(message[matchRange])
}

private func listTaskDirectoryEntryCount(_ url: URL) -> Int {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
        return 0
    }
    return contents.count
}

private func listTaskDirectoryEntrySamples(_ url: URL, limit: Int = 5) -> [String] {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
        return []
    }
    return Array(contents.sorted().prefix(limit))
}

private func listTaskDefaultIPCBaseURL() -> URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let container = home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Containers", isDirectory: true)
        .appendingPathComponent("com.omnigroup.OmniFocus4", isDirectory: true)
        .appendingPathComponent("Data", isDirectory: true)
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("FocusRelayIPC", isDirectory: true)

    if FileManager.default.fileExists(atPath: container.deletingLastPathComponent().path) {
        return container
    }

    return home
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Caches", isDirectory: true)
        .appendingPathComponent("focusrelay", isDirectory: true)
}

private func listTaskCurrentOmniFocusPID() -> Int32? {
    guard let output = try? listTaskRunProcess(
        executable: "/usr/bin/pgrep",
        arguments: ["-x", "OmniFocus"],
        timeout: 3
    ) else {
        return nil
    }
    let firstLine = output.split(separator: "\n").first
    return firstLine.flatMap { Int32($0) }
}

private func listTaskReadRSSKilobytes(pid: Int32) -> Int? {
    guard let output = try? listTaskRunProcess(
        executable: "/bin/ps",
        arguments: ["-o", "rss=", "-p", String(pid)],
        timeout: 3
    ) else {
        return nil
    }
    return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
}

@discardableResult
private func listTaskRunProcess(executable: String, arguments: [String], timeout: TimeInterval = 15) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }

    if process.isRunning {
        process.terminate()
        throw AutomationError.executionFailed("Process \(executable) timed out after \(Int(timeout))s")
    }

    process.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(decoding: data, as: UTF8.self)
    if process.terminationStatus != 0 {
        throw AutomationError.executionFailed("Process \(executable) failed: \(output)")
    }
    return output
}

private func listTaskCountLines(in url: URL) -> Int {
    guard let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8),
          !text.isEmpty else {
        return 0
    }
    return text.split(separator: "\n").count
}

private func listTaskIsTimeout(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("timed out") || message.contains("timeout")
}

private func listTaskEnforceInterval(started: Date, intervalMS: Int) async throws {
    guard intervalMS > 0 else { return }
    let elapsed = Date().timeIntervalSince(started)
    let target = Double(intervalMS) / 1000.0
    if elapsed < target {
        try await Task.sleep(nanoseconds: UInt64((target - elapsed) * 1_000_000_000))
    }
}

private func listTaskISO8601Now() -> String {
    listTaskISO8601(Date())
}

private func listTaskISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
#endif
