import ArgumentParser
import Foundation
import OmniFocusAutomation
import OmniFocusCore

private typealias TaskCountsModel = OmniFocusCore.TaskCounts

struct BenchmarkTaskCounts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark-task-counts",
        abstract: "Benchmark get_task_counts for plugin vs JXA transports.",
        aliases: ["benchmark_get_task_counts"]
    )

    @Option(name: .customLong("duration-hours"), help: "Measured phase duration in hours.")
    var durationHours: Double = 3.0

    @Option(name: .customLong("warmup-calls"), help: "Warmup calls per transport before measured runs.")
    var warmupCalls: Int = 20

    @Option(name: .customLong("interval-ms"), help: "Minimum start-to-start interval between calls in milliseconds.")
    var intervalMS: Int = 1200

    @Option(name: .customLong("cooldown-ms"), help: "Cooldown delay after failed/timeout calls in milliseconds.")
    var cooldownMS: Int = 5000

    @Option(name: .customLong("memory-interval-seconds"), help: "RSS sample interval in seconds.")
    var memoryIntervalSeconds: Int = 30

    @Option(name: .customLong("completed-after"), help: "Fixed ISO8601 anchor for completed-date scenario.")
    var completedAfter: String = "2020-01-01T00:00:00Z"

    @Option(name: .customLong("output-dir"), help: "Output directory. Defaults to docs/benchmarks/<timestamp>.")
    var outputDir: String?

    @Flag(name: .customLong("run-preflight"), help: "Run process cleanup and OmniFocus restart before benchmarking.")
    var performPreflight: Bool = false

    func run() async throws {
        guard durationHours > 0 else {
            throw ValidationError("--duration-hours must be > 0.")
        }
        guard warmupCalls >= 0 else {
            throw ValidationError("--warmup-calls must be >= 0.")
        }
        guard intervalMS >= 0 else {
            throw ValidationError("--interval-ms must be >= 0.")
        }
        guard cooldownMS >= 0 else {
            throw ValidationError("--cooldown-ms must be >= 0.")
        }
        guard memoryIntervalSeconds > 0 else {
            throw ValidationError("--memory-interval-seconds must be > 0.")
        }

        let completedAfterDate = try ISO8601DateParser.parse(completedAfter, argumentName: "--completed-after")
        let scenarios = benchmarkScenarios(completedAfter: completedAfterDate)

        let directoryURL = try benchmarkOutputDirectory(customPath: outputDir)
        let rawURL = directoryURL.appendingPathComponent("raw.jsonl")
        let memoryURL = directoryURL.appendingPathComponent("memory.csv")
        let summaryURL = directoryURL.appendingPathComponent("summary.md")
        let timeoutDiagnosticsURL = directoryURL.appendingPathComponent("timeout-diagnostics.jsonl")
        try initializeBenchmarkArtifacts(rawURL: rawURL, memoryURL: memoryURL, timeoutDiagnosticsURL: timeoutDiagnosticsURL)

        print("Benchmark output directory: \(directoryURL.path)")
        print("Scenarios: \(scenarios.map(\.name).joined(separator: ", "))")

        if performPreflight {
            runPreflight()
        }

        let benchmarkPID = ProcessInfo.processInfo.processIdentifier
        let memoryTask = Task.detached(priority: .utility) {
            while !Task.isCancelled {
                let timestamp = iso8601Now()
                if let rss = readRSSKilobytes(pid: benchmarkPID) {
                    let line = "\(timestamp),focusrelay,\(benchmarkPID),\(rss)\n"
                    try? appendLine(line, to: memoryURL)
                }

                if let omniPID = currentOmniFocusPID(), let rss = readRSSKilobytes(pid: omniPID) {
                    let line = "\(timestamp),OmniFocus,\(omniPID),\(rss)\n"
                    try? appendLine(line, to: memoryURL)
                }

                let nanos = UInt64(memoryIntervalSeconds) * 1_000_000_000
                try? await Task.sleep(nanoseconds: nanos)
            }
        }
        defer { memoryTask.cancel() }

        let pluginService = OmniFocusBridgeService()
        let jxaService = OmniAutomationService()

        var statsByTransport: [Transport: StatsAccumulator] = [:]
        var statsByScenarioTransport: [String: [Transport: StatsAccumulator]] = [:]
        var parityMismatches: [ParityMismatch] = []
        var callIndex = 0

        if warmupCalls > 0 {
            print("Warmup phase: \(warmupCalls) calls per transport")
            try await runWarmup(
                warmupCalls: warmupCalls,
                scenarios: scenarios,
                pluginService: pluginService,
                jxaService: jxaService,
                rawURL: rawURL,
                timeoutDiagnosticsURL: timeoutDiagnosticsURL,
                intervalMS: intervalMS,
                cooldownMS: cooldownMS,
                callIndex: &callIndex
            )
        }

        let durationSeconds = durationHours * 3600
        let measuredStart = Date()
        let measuredEnd = measuredStart.addingTimeInterval(durationSeconds)
        print("Measured phase started at \(iso8601(measuredStart)); ending at \(iso8601(measuredEnd))")

        var scenarioIndex = 0
        while Date() < measuredEnd {
            let scenario = scenarios[scenarioIndex % scenarios.count]
            scenarioIndex += 1

            let pluginEvent = try await runBenchCall(
                transport: .plugin,
                scenario: scenario,
                phase: "measured",
                service: pluginService,
                timeoutDiagnosticsURL: timeoutDiagnosticsURL,
                intervalMS: intervalMS,
                cooldownMS: cooldownMS,
                callIndex: &callIndex
            )
            try appendJSONLine(pluginEvent, to: rawURL)
            accumulate(pluginEvent, byTransport: &statsByTransport, byScenarioTransport: &statsByScenarioTransport)
            if pluginEvent.timeout {
                await runTimeoutRecoveryGate()
            }

            let jxaEvent = try await runBenchCall(
                transport: .jxa,
                scenario: scenario,
                phase: "measured",
                service: jxaService,
                timeoutDiagnosticsURL: timeoutDiagnosticsURL,
                intervalMS: intervalMS,
                cooldownMS: cooldownMS,
                callIndex: &callIndex
            )
            try appendJSONLine(jxaEvent, to: rawURL)
            accumulate(jxaEvent, byTransport: &statsByTransport, byScenarioTransport: &statsByScenarioTransport)
            if jxaEvent.timeout {
                await runTimeoutRecoveryGate()
            }

            if let pluginCounts = pluginEvent.counts,
               let jxaCounts = jxaEvent.counts,
               !taskCountsEqual(pluginCounts, jxaCounts) {
                let mismatch = ParityMismatch(
                    timestamp: iso8601Now(),
                    scenario: scenario.name,
                    plugin: pluginCounts,
                    jxa: jxaCounts
                )
                parityMismatches.append(mismatch)
            }
        }

        try await writeSummary(
            to: summaryURL,
            startedAt: measuredStart,
            endedAt: Date(),
            memoryURL: memoryURL,
            durationHours: durationHours,
            warmupCalls: warmupCalls,
            intervalMS: intervalMS,
            cooldownMS: cooldownMS,
            memoryIntervalSeconds: memoryIntervalSeconds,
            timeoutDiagnosticsURL: timeoutDiagnosticsURL,
            scenarios: scenarios,
            statsByTransport: statsByTransport,
            statsByScenarioTransport: statsByScenarioTransport,
            parityMismatches: parityMismatches
        )

        print("Benchmark complete.")
        print("Raw data: \(rawURL.path)")
        print("Memory samples: \(memoryURL.path)")
        print("Summary: \(summaryURL.path)")
    }
}

private struct BenchmarkScenario {
    let name: String
    let filter: TaskFilter
}

private func benchmarkScenarios(completedAfter: Date) -> [BenchmarkScenario] {
    [
        BenchmarkScenario(name: "default", filter: TaskFilter()),
        BenchmarkScenario(name: "inbox_only", filter: TaskFilter(inboxOnly: true)),
        BenchmarkScenario(name: "available_only", filter: TaskFilter(availableOnly: true)),
        BenchmarkScenario(
            name: "completed_after_anchor",
            filter: TaskFilter(completed: true, completedAfter: completedAfter)
        ),
        BenchmarkScenario(name: "flagged_only", filter: TaskFilter(flagged: true))
    ]
}

private enum Transport: String, Codable, CaseIterable {
    case plugin
    case jxa
}

private struct BenchEvent: Codable {
    let timestamp: String
    let phase: String
    let callIndex: Int
    let transport: String
    let scenario: String
    let latencyMs: Double
    let ok: Bool
    let timeout: Bool
    let error: String?
    let counts: TaskCountsModel?
}

private struct StatsAccumulator {
    var successCount: Int = 0
    var errorCount: Int = 0
    var timeoutCount: Int = 0
    var latencies: [Double] = []

    mutating func ingest(_ event: BenchEvent) {
        if event.ok {
            successCount += 1
            latencies.append(event.latencyMs)
        } else {
            errorCount += 1
            if event.timeout {
                timeoutCount += 1
            }
        }
    }
}

private struct ParityMismatch: Codable {
    let timestamp: String
    let scenario: String
    let plugin: TaskCountsModel
    let jxa: TaskCountsModel
}

private struct TimeoutQueueSnapshot: Codable {
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

private struct TimeoutProcessSnapshot: Codable {
    let process: String
    let pid: Int32?
    let rssKB: Int?
}

private struct TimeoutBridgeHealthSnapshot: Codable {
    let ok: Bool
    let detail: String
}

private struct TaskTimeoutDiagnostic: Codable {
    let timestamp: String
    let transport: String
    let scenario: String
    let phase: String
    let callIndex: Int
    let latencyMs: Double
    let error: String
    let requestId: String?
    let queue: TimeoutQueueSnapshot
    let omniFocus: TimeoutProcessSnapshot
    let focusrelay: TimeoutProcessSnapshot
    let bridgeHealth: TimeoutBridgeHealthSnapshot?
}

private func runWarmup(
    warmupCalls: Int,
    scenarios: [BenchmarkScenario],
    pluginService: OmniFocusBridgeService,
    jxaService: OmniAutomationService,
    rawURL: URL,
    timeoutDiagnosticsURL: URL,
    intervalMS: Int,
    cooldownMS: Int,
    callIndex: inout Int
) async throws {
    var scenarioIndex = 0
    for _ in 0..<warmupCalls {
        let scenario = scenarios[scenarioIndex % scenarios.count]
        scenarioIndex += 1
        let event = try await runBenchCall(
            transport: .plugin,
            scenario: scenario,
            phase: "warmup",
            service: pluginService,
            timeoutDiagnosticsURL: timeoutDiagnosticsURL,
            intervalMS: intervalMS,
            cooldownMS: cooldownMS,
            callIndex: &callIndex
        )
        try appendJSONLine(event, to: rawURL)
    }

    for _ in 0..<warmupCalls {
        let scenario = scenarios[scenarioIndex % scenarios.count]
        scenarioIndex += 1
        let event = try await runBenchCall(
            transport: .jxa,
            scenario: scenario,
            phase: "warmup",
            service: jxaService,
            timeoutDiagnosticsURL: timeoutDiagnosticsURL,
            intervalMS: intervalMS,
            cooldownMS: cooldownMS,
            callIndex: &callIndex
        )
        try appendJSONLine(event, to: rawURL)
    }
}

private func runBenchCall(
    transport: Transport,
    scenario: BenchmarkScenario,
    phase: String,
    service: any OmniFocusService,
    timeoutDiagnosticsURL: URL,
    intervalMS: Int,
    cooldownMS: Int,
    callIndex: inout Int
) async throws -> BenchEvent {
    callIndex += 1
    let start = Date()
    do {
        let counts = try await service.getTaskCounts(filter: scenario.filter)
        let elapsed = Date().timeIntervalSince(start)
        try await enforceInterval(start: start, intervalMS: intervalMS)
        return BenchEvent(
            timestamp: iso8601Now(),
            phase: phase,
            callIndex: callIndex,
            transport: transport.rawValue,
            scenario: scenario.name,
            latencyMs: elapsed * 1000,
            ok: true,
            timeout: false,
            error: nil,
            counts: counts
        )
    } catch {
        let elapsed = Date().timeIntervalSince(start)
        let message = error.localizedDescription
        let isTimeout = isTimeoutError(error)
        try await enforceInterval(start: start, intervalMS: intervalMS)
        if cooldownMS > 0 {
            try? await Task.sleep(nanoseconds: UInt64(cooldownMS) * 1_000_000)
        }
        if isTimeout {
            let diagnostic = captureTaskTimeoutDiagnostic(
                transport: transport,
                scenario: scenario,
                phase: phase,
                callIndex: callIndex,
                latencyMs: elapsed * 1000,
                errorMessage: message
            )
            try? appendJSONLine(diagnostic, to: timeoutDiagnosticsURL)
        }
        return BenchEvent(
            timestamp: iso8601Now(),
            phase: phase,
            callIndex: callIndex,
            transport: transport.rawValue,
            scenario: scenario.name,
            latencyMs: elapsed * 1000,
            ok: false,
            timeout: isTimeout,
            error: message,
            counts: nil
        )
    }
}

private func runTimeoutRecoveryGate() async {
    let env = ProcessInfo.processInfo.environment
    let recoveryMs = max(0, env["FOCUS_RELAY_TIMEOUT_RECOVERY_MS"].flatMap(Int.init) ?? 10_000)
    if recoveryMs > 0 {
        try? await Task.sleep(nanoseconds: UInt64(recoveryMs) * 1_000_000)
    }
    // Lightweight readiness probe before resuming to reduce timeout cascades.
    _ = try? OmniFocusBridgeService().healthCheck()
}

private func enforceInterval(start: Date, intervalMS: Int) async throws {
    guard intervalMS > 0 else { return }
    let elapsed = Date().timeIntervalSince(start)
    let target = Double(intervalMS) / 1000.0
    if elapsed < target {
        let wait = target - elapsed
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
    }
}

private func accumulate(
    _ event: BenchEvent,
    byTransport: inout [Transport: StatsAccumulator],
    byScenarioTransport: inout [String: [Transport: StatsAccumulator]]
) {
    guard let transport = Transport(rawValue: event.transport) else { return }

    var transportStats = byTransport[transport] ?? StatsAccumulator()
    transportStats.ingest(event)
    byTransport[transport] = transportStats

    var scenarioStats = byScenarioTransport[event.scenario] ?? [:]
    var scopedStats = scenarioStats[transport] ?? StatsAccumulator()
    scopedStats.ingest(event)
    scenarioStats[transport] = scopedStats
    byScenarioTransport[event.scenario] = scenarioStats
}

private func benchmarkOutputDirectory(customPath: String?) throws -> URL {
    if let customPath, !customPath.isEmpty {
        let url = URL(fileURLWithPath: customPath, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let timestamp = formatter.string(from: Date())
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("docs", isDirectory: true)
        .appendingPathComponent("benchmarks", isDirectory: true)
        .appendingPathComponent(timestamp, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func initializeBenchmarkArtifacts(rawURL: URL, memoryURL: URL, timeoutDiagnosticsURL: URL) throws {
    FileManager.default.createFile(atPath: rawURL.path, contents: nil)
    FileManager.default.createFile(atPath: memoryURL.path, contents: nil)
    FileManager.default.createFile(atPath: timeoutDiagnosticsURL.path, contents: nil)
    try appendLine("timestamp,process,pid,rss_kb\n", to: memoryURL)
}

private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    guard var line = String(data: data, encoding: .utf8) else {
        throw ValidationError("Failed to encode benchmark event as UTF-8.")
    }
    line.append("\n")
    try appendLine(line, to: url)
}

private func appendLine(_ line: String, to url: URL) throws {
    guard let data = line.data(using: .utf8) else { return }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
}

private func isTimeoutError(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("timed out") || message.contains("timeout")
}

private func runPreflight() {
    do {
        try stopExtraServeProcesses()
    } catch {
        print("Preflight warning: failed to inspect/terminate extra servers (\(error.localizedDescription)).")
    }

    do {
        try restartOmniFocus()
    } catch {
        print("Preflight warning: failed to restart OmniFocus (\(error.localizedDescription)).")
    }
}

private func stopExtraServeProcesses() throws {
    let currentPID = ProcessInfo.processInfo.processIdentifier
    guard let output = try? runProcess(
        executable: "/usr/bin/pgrep",
        arguments: ["-f", "focusrelay"],
        timeout: 3
    ) else {
        print("Preflight: no extra focusrelay server processes detected.")
        return
    }

    let candidatePIDs = output
        .split(separator: "\n")
        .compactMap { Int32($0) }

    var terminated: [Int32] = []
    for pid in candidatePIDs {
        if pid == currentPID { continue }
        guard let command = try? runProcess(
            executable: "/bin/ps",
            arguments: ["-o", "command=", "-p", String(pid)],
            timeout: 3
        ) else {
            continue
        }
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCommand.contains("focusrelay serve") || trimmedCommand.contains("focusrelay mcp") || trimmedCommand.contains("focusrelay server") {
            _ = try? runProcess(executable: "/bin/kill", arguments: ["-TERM", String(pid)], timeout: 2)
            terminated.append(pid)
        }
    }

    if !terminated.isEmpty {
        print("Preflight: terminated focusrelay server processes: \(terminated.map(String.init).joined(separator: ", "))")
        Thread.sleep(forTimeInterval: 1.0)
    } else {
        print("Preflight: no extra focusrelay server processes detected.")
    }
}

private func restartOmniFocus() throws {
    print("Preflight: restarting OmniFocus...")
    _ = try? runProcess(
        executable: "/usr/bin/osascript",
        arguments: ["-e", "tell application \"OmniFocus\" to quit"],
        timeout: 8
    )
    Thread.sleep(forTimeInterval: 2.0)
    _ = try runProcess(executable: "/usr/bin/open", arguments: ["-a", "OmniFocus"], timeout: 8)
    Thread.sleep(forTimeInterval: 3.0)
}

private func currentOmniFocusPID() -> Int32? {
    guard let output = try? runProcess(executable: "/usr/bin/pgrep", arguments: ["-x", "OmniFocus"], timeout: 3) else {
        return nil
    }
    let firstLine = output.split(separator: "\n").first
    return firstLine.flatMap { Int32($0) }
}

private func readRSSKilobytes(pid: Int32) -> Int? {
    guard let output = try? runProcess(executable: "/bin/ps", arguments: ["-o", "rss=", "-p", String(pid)], timeout: 3) else {
        return nil
    }
    return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
}

@discardableResult
private func runProcess(executable: String, arguments: [String], timeout: TimeInterval = 15) throws -> String {
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

private func captureTaskTimeoutDiagnostic(
    transport: Transport,
    scenario: BenchmarkScenario,
    phase: String,
    callIndex: Int,
    latencyMs: Double,
    errorMessage: String
) -> TaskTimeoutDiagnostic {
    let requestID = extractRequestID(from: errorMessage)
    let baseURL = defaultIPCBaseURL()
    let requestsURL = baseURL.appendingPathComponent("requests", isDirectory: true)
    let locksURL = baseURL.appendingPathComponent("locks", isDirectory: true)
    let responsesURL = baseURL.appendingPathComponent("responses", isDirectory: true)
    let queue = TimeoutQueueSnapshot(
        basePath: baseURL.path,
        requestsCount: directoryEntryCount(requestsURL),
        locksCount: directoryEntryCount(locksURL),
        responsesCount: directoryEntryCount(responsesURL),
        requestExists: requestID.map { FileManager.default.fileExists(atPath: requestsURL.appendingPathComponent("\($0).json").path) },
        lockExists: requestID.map { FileManager.default.fileExists(atPath: locksURL.appendingPathComponent("\($0).lock").path) },
        responseExists: requestID.map { FileManager.default.fileExists(atPath: responsesURL.appendingPathComponent("\($0).json").path) },
        sampleRequests: directoryEntrySamples(requestsURL),
        sampleLocks: directoryEntrySamples(locksURL),
        sampleResponses: directoryEntrySamples(responsesURL)
    )
    let omniPID = currentOmniFocusPID()
    let benchmarkPID = ProcessInfo.processInfo.processIdentifier
    let bridgeHealth: TimeoutBridgeHealthSnapshot?
    if transport == .plugin {
        if let result = try? OmniFocusBridgeService().healthCheck() {
            bridgeHealth = TimeoutBridgeHealthSnapshot(
                ok: result.ok,
                detail: "plugin=\(result.plugin ?? "unknown") version=\(result.version ?? "unknown")"
            )
        } else {
            bridgeHealth = TimeoutBridgeHealthSnapshot(
                ok: false,
                detail: "bridge-health-check failed after timeout"
            )
        }
    } else {
        bridgeHealth = nil
    }

    return TaskTimeoutDiagnostic(
        timestamp: iso8601Now(),
        transport: transport.rawValue,
        scenario: scenario.name,
        phase: phase,
        callIndex: callIndex,
        latencyMs: latencyMs,
        error: errorMessage,
        requestId: requestID,
        queue: queue,
        omniFocus: TimeoutProcessSnapshot(
            process: "OmniFocus",
            pid: omniPID,
            rssKB: omniPID.flatMap(readRSSKilobytes(pid:))
        ),
        focusrelay: TimeoutProcessSnapshot(
            process: "focusrelay",
            pid: benchmarkPID,
            rssKB: readRSSKilobytes(pid: benchmarkPID)
        ),
        bridgeHealth: bridgeHealth
    )
}

private func extractRequestID(from message: String) -> String? {
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

private func directoryEntryCount(_ url: URL) -> Int {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
        return 0
    }
    return contents.count
}

private func directoryEntrySamples(_ url: URL, limit: Int = 5) -> [String] {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else {
        return []
    }
    return Array(contents.sorted().prefix(limit))
}

private func defaultIPCBaseURL() -> URL {
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

private func writeSummary(
    to url: URL,
    startedAt: Date,
    endedAt: Date,
    memoryURL: URL,
    durationHours: Double,
    warmupCalls: Int,
    intervalMS: Int,
    cooldownMS: Int,
    memoryIntervalSeconds: Int,
    timeoutDiagnosticsURL: URL,
    scenarios: [BenchmarkScenario],
    statsByTransport: [Transport: StatsAccumulator],
    statsByScenarioTransport: [String: [Transport: StatsAccumulator]],
    parityMismatches: [ParityMismatch]
) async throws {
    let memorySummary = loadMemorySummary(from: memoryURL)
    let timeoutDiagnosticCount = countLines(in: timeoutDiagnosticsURL)
    var lines: [String] = []
    lines.append("# get_task_counts Benchmark Summary")
    lines.append("")
    lines.append("- Started: \(iso8601(startedAt))")
    lines.append("- Ended: \(iso8601(endedAt))")
    lines.append(String(format: "- Configured duration (hours): %.2f", durationHours))
    lines.append("- Warmup calls per transport: \(warmupCalls)")
    lines.append("- Interval (ms): \(intervalMS)")
    lines.append("- Cooldown after failure (ms): \(cooldownMS)")
    lines.append("- Memory sampling interval (seconds): \(memoryIntervalSeconds)")
    lines.append("- Scenarios: \(scenarios.map(\.name).joined(separator: ", "))")
    lines.append("")
    lines.append("## Overall Transport Stats")
    lines.append("")
    for transport in Transport.allCases {
        let stats = statsByTransport[transport] ?? StatsAccumulator()
        let totalCalls = stats.successCount + stats.errorCount
        let timeoutRate = percentage(part: stats.timeoutCount, total: totalCalls)
        let errorRate = percentage(part: stats.errorCount, total: totalCalls)
        lines.append("### \(transport.rawValue)")
        lines.append("- Total calls: \(totalCalls)")
        lines.append("- Success calls: \(stats.successCount)")
        lines.append("- Error calls: \(stats.errorCount)")
        lines.append("- Error rate: \(formatPercentage(errorRate))")
        lines.append("- Timeout calls: \(stats.timeoutCount)")
        lines.append("- Timeout rate: \(formatPercentage(timeoutRate))")
        lines.append("- p50 latency (ms): \(formatDouble(percentile(stats.latencies, p: 0.50)))")
        lines.append("- p95 latency (ms): \(formatDouble(percentile(stats.latencies, p: 0.95)))")
        lines.append("- p99 latency (ms): \(formatDouble(percentile(stats.latencies, p: 0.99)))")
        lines.append("")
    }

    lines.append("## Scenario Stats")
    lines.append("")
    for scenario in scenarios {
        lines.append("### \(scenario.name)")
        let scoped = statsByScenarioTransport[scenario.name] ?? [:]
        for transport in Transport.allCases {
            let stats = scoped[transport] ?? StatsAccumulator()
            let totalCalls = stats.successCount + stats.errorCount
            let timeoutRate = percentage(part: stats.timeoutCount, total: totalCalls)
            let errorRate = percentage(part: stats.errorCount, total: totalCalls)
            lines.append("- \(transport.rawValue): total=\(totalCalls), success=\(stats.successCount), errors=\(stats.errorCount), error_rate=\(formatPercentage(errorRate)), timeouts=\(stats.timeoutCount), timeout_rate=\(formatPercentage(timeoutRate)), p95_ms=\(formatDouble(percentile(stats.latencies, p: 0.95)))")
        }
        lines.append("")
    }

    lines.append("## Parity")
    lines.append("")
    lines.append("- Mismatch count: \(parityMismatches.count)")
    if !parityMismatches.isEmpty {
        lines.append("")
        lines.append("First mismatches:")
        for mismatch in parityMismatches.prefix(10) {
            lines.append("- \(mismatch.timestamp) scenario=\(mismatch.scenario) plugin=\(mismatch.plugin) jxa=\(mismatch.jxa)")
        }
    }

    lines.append("")
    lines.append("## Memory Notes")
    lines.append("")
    lines.append("- `memory.csv` contains RSS samples for `focusrelay` and `OmniFocus`.")
    lines.append("- Memory growth slope is estimated in KB/min from sampled RSS values.")
    lines.append("- `timeout-diagnostics.jsonl` contains timeout queue/process snapshots for this benchmark.")
    lines.append("")
    lines.append("### Memory Growth")
    for process in ["focusrelay", "OmniFocus"] {
        if let summary = memorySummary[process] {
            lines.append("- \(process): samples=\(summary.samples), start_kb=\(summary.startKB), end_kb=\(summary.endKB), delta_kb=\(summary.endKB - summary.startKB), slope_kb_per_min=\(formatDouble(summary.slopeKBPerMinute))")
        } else {
            lines.append("- \(process): no samples")
        }
    }

    lines.append("")
    lines.append("## Timeout Diagnostics")
    lines.append("")
    lines.append("- Diagnostic entries: \(timeoutDiagnosticCount)")

    try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
}

private func percentile(_ values: [Double], p: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    let index = Int(Double(sorted.count - 1) * p)
    return sorted[max(0, min(index, sorted.count - 1))]
}

private func formatDouble(_ value: Double) -> String {
    guard value.isFinite else { return "n/a" }
    return String(format: "%.2f", value)
}

private func formatPercentage(_ value: Double) -> String {
    guard value.isFinite else { return "n/a" }
    return String(format: "%.2f%%", value)
}

private func taskCountsEqual(_ lhs: TaskCountsModel, _ rhs: TaskCountsModel) -> Bool {
    lhs.total == rhs.total &&
        lhs.completed == rhs.completed &&
        lhs.available == rhs.available &&
        lhs.flagged == rhs.flagged
}

private struct MemorySample {
    let timestamp: Date
    let process: String
    let rssKB: Double
}

private struct MemoryProcessSummary {
    let samples: Int
    let startKB: Int
    let endKB: Int
    let slopeKBPerMinute: Double
}

private func loadMemorySummary(from url: URL) -> [String: MemoryProcessSummary] {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else {
        return [:]
    }

    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    var byProcess: [String: [MemorySample]] = [:]
    let lines = content.split(separator: "\n")
    for (index, line) in lines.enumerated() {
        if index == 0 { continue } // header
        let columns = line.split(separator: ",", omittingEmptySubsequences: false)
        if columns.count < 4 { continue }
        let timestampRaw = String(columns[0])
        let process = String(columns[1])
        let rssRaw = String(columns[3])
        guard let timestamp = parser.date(from: timestampRaw),
              let rss = Double(rssRaw) else {
            continue
        }
        let sample = MemorySample(timestamp: timestamp, process: process, rssKB: rss)
        byProcess[process, default: []].append(sample)
    }

    var summary: [String: MemoryProcessSummary] = [:]
    for (process, samples) in byProcess {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { continue }
        let slope = linearSlopeKBPerMinute(samples: sorted)
        summary[process] = MemoryProcessSummary(
            samples: sorted.count,
            startKB: Int(first.rssKB.rounded()),
            endKB: Int(last.rssKB.rounded()),
            slopeKBPerMinute: slope
        )
    }
    return summary
}

private func linearSlopeKBPerMinute(samples: [MemorySample]) -> Double {
    guard samples.count > 1, let first = samples.first else { return .nan }

    var sumX = 0.0
    var sumY = 0.0
    var sumXX = 0.0
    var sumXY = 0.0
    let n = Double(samples.count)

    for sample in samples {
        let x = sample.timestamp.timeIntervalSince(first.timestamp) / 60.0
        let y = sample.rssKB
        sumX += x
        sumY += y
        sumXX += x * x
        sumXY += x * y
    }

    let denominator = (n * sumXX) - (sumX * sumX)
    if abs(denominator) < 1e-9 { return .nan }
    return ((n * sumXY) - (sumX * sumY)) / denominator
}

private func percentage(part: Int, total: Int) -> Double {
    guard total > 0 else { return .nan }
    return (Double(part) / Double(total)) * 100.0
}

private func countLines(in url: URL) -> Int {
    guard let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty else {
        return 0
    }
    return max(0, content.split(separator: "\n").count)
}

private func iso8601Now() -> String {
    iso8601(Date())
}

private func iso8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}
