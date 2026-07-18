#if DEBUG
import ArgumentParser
import Foundation
import OmniFocusAutomation

let benchmarkTransport = "plugin"

struct BenchmarkStats {
    var success: Int = 0
    var errors: Int = 0
    var timeouts: Int = 0
    var latencies: [Double] = []

    mutating func ingest(ok: Bool, timeout: Bool, latencyMs: Double) {
        if ok {
            success += 1
            latencies.append(latencyMs)
        } else {
            errors += 1
            if timeout {
                timeouts += 1
            }
        }
    }
}

struct CountBenchmarkEvent<Counts: Codable>: Codable {
    let timestamp: String
    let phase: String
    let callIndex: Int
    let transport: String
    let scenario: String
    let latencyMs: Double
    let ok: Bool
    let timeout: Bool
    let error: String?
    let counts: Counts?
}

struct BenchmarkTimeoutQueueSnapshot: Codable {
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

struct BenchmarkTimeoutProcessSnapshot: Codable {
    let process: String
    let pid: Int32?
    let rssKB: Int?
}

struct BenchmarkTimeoutBridgeHealthSnapshot: Codable {
    let ok: Bool
    let detail: String
}

struct BenchmarkTimeoutDiagnostic: Codable {
    let timestamp: String
    let transport: String
    let scenario: String
    let phase: String
    let callIndex: Int
    let latencyMs: Double
    let error: String
    let requestId: String?
    let queue: BenchmarkTimeoutQueueSnapshot
    let omniFocus: BenchmarkTimeoutProcessSnapshot
    let focusrelay: BenchmarkTimeoutProcessSnapshot
    let bridgeHealth: BenchmarkTimeoutBridgeHealthSnapshot?
}

func validateBenchmarkArguments(
    durationHours: Double,
    warmupCalls: Int,
    intervalMS: Int,
    cooldownMS: Int,
    memoryIntervalSeconds: Int? = nil
) throws {
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
    if let memoryIntervalSeconds, memoryIntervalSeconds <= 0 {
        throw ValidationError("--memory-interval-seconds must be > 0.")
    }
}

func runCountBenchmarkCall<Counts: Codable>(
    scenario: String,
    phase: String,
    timeoutDiagnosticsURL: URL,
    intervalMS: Int,
    cooldownMS: Int,
    callIndex: inout Int,
    operation: () async throws -> Counts
) async throws -> CountBenchmarkEvent<Counts> {
    callIndex += 1
    let started = Date()
    do {
        let counts = try await operation()
        let latencyMs = Date().timeIntervalSince(started) * 1000
        try await enforceBenchmarkInterval(started: started, intervalMS: intervalMS)
        return CountBenchmarkEvent(
            timestamp: benchmarkISO8601Now(),
            phase: phase,
            callIndex: callIndex,
            transport: benchmarkTransport,
            scenario: scenario,
            latencyMs: latencyMs,
            ok: true,
            timeout: false,
            error: nil,
            counts: counts
        )
    } catch {
        let latencyMs = Date().timeIntervalSince(started) * 1000
        let timeout = isBenchmarkTimeout(error)
        try await enforceBenchmarkInterval(started: started, intervalMS: intervalMS)
        if cooldownMS > 0 {
            try? await Task.sleep(nanoseconds: UInt64(cooldownMS) * 1_000_000)
        }
        if timeout {
            let diagnostic = captureBenchmarkTimeoutDiagnostic(
                scenario: scenario,
                phase: phase,
                callIndex: callIndex,
                latencyMs: latencyMs,
                errorMessage: error.localizedDescription
            )
            try? appendBenchmarkJSONLine(diagnostic, to: timeoutDiagnosticsURL)
        }
        return CountBenchmarkEvent(
            timestamp: benchmarkISO8601Now(),
            phase: phase,
            callIndex: callIndex,
            transport: benchmarkTransport,
            scenario: scenario,
            latencyMs: latencyMs,
            ok: false,
            timeout: timeout,
            error: error.localizedDescription,
            counts: nil
        )
    }
}

func ingestBenchmarkEvent(
    scenario: String,
    ok: Bool,
    timeout: Bool,
    latencyMs: Double,
    overall: inout BenchmarkStats,
    scenarios: inout [String: BenchmarkStats]
) {
    overall.ingest(ok: ok, timeout: timeout, latencyMs: latencyMs)
    var scoped = scenarios[scenario] ?? BenchmarkStats()
    scoped.ingest(ok: ok, timeout: timeout, latencyMs: latencyMs)
    scenarios[scenario] = scoped
}

func benchmarkOutputDirectory(customPath: String?, defaultPrefix: String? = nil) throws -> URL {
    if let customPath, !customPath.isEmpty {
        let url = URL(
            fileURLWithPath: customPath,
            relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ).standardizedFileURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let timestamp = formatter.string(from: Date())
    let directoryName = defaultPrefix.map { "\($0)-\(timestamp)" } ?? timestamp
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build", isDirectory: true)
        .appendingPathComponent("benchmarks", isDirectory: true)
        .appendingPathComponent(directoryName, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func initializeBenchmarkArtifacts(rawURL: URL, memoryURL: URL?, timeoutDiagnosticsURL: URL) throws {
    FileManager.default.createFile(atPath: rawURL.path, contents: nil)
    FileManager.default.createFile(atPath: timeoutDiagnosticsURL.path, contents: nil)
    if let memoryURL {
        FileManager.default.createFile(atPath: memoryURL.path, contents: nil)
        try appendBenchmarkLine("timestamp,process,pid,rss_kb\n", to: memoryURL)
    }
}

func appendBenchmarkJSONLine<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    guard var line = String(data: data, encoding: .utf8) else {
        throw ValidationError("Failed to encode benchmark event as UTF-8.")
    }
    line.append("\n")
    try appendBenchmarkLine(line, to: url)
}

func appendBenchmarkLine(_ line: String, to url: URL) throws {
    guard let data = line.data(using: .utf8) else { return }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
}

func startBenchmarkMemorySampling(memoryURL: URL, intervalSeconds: Int) -> Task<Void, Never> {
    let benchmarkPID = ProcessInfo.processInfo.processIdentifier
    return Task.detached(priority: .utility) {
        while !Task.isCancelled {
            let timestamp = benchmarkISO8601Now()
            if let rss = benchmarkRSSKilobytes(pid: benchmarkPID) {
                try? appendBenchmarkLine("\(timestamp),focusrelay,\(benchmarkPID),\(rss)\n", to: memoryURL)
            }
            if let omniPID = currentOmniFocusPID(), let rss = benchmarkRSSKilobytes(pid: omniPID) {
                try? appendBenchmarkLine("\(timestamp),OmniFocus,\(omniPID),\(rss)\n", to: memoryURL)
            }
            try? await Task.sleep(nanoseconds: UInt64(intervalSeconds) * 1_000_000_000)
        }
    }
}

func runBenchmarkTimeoutRecoveryGate() async {
    let environment = ProcessInfo.processInfo.environment
    let recoveryMS = max(0, environment["FOCUS_RELAY_TIMEOUT_RECOVERY_MS"].flatMap(Int.init) ?? 10_000)
    if recoveryMS > 0 {
        try? await Task.sleep(nanoseconds: UInt64(recoveryMS) * 1_000_000)
    }
    _ = try? OmniFocusBridgeService().healthCheck()
}

func enforceBenchmarkInterval(started: Date, intervalMS: Int) async throws {
    guard intervalMS > 0 else { return }
    let elapsed = Date().timeIntervalSince(started)
    let target = Double(intervalMS) / 1000.0
    if elapsed < target {
        try await Task.sleep(nanoseconds: UInt64((target - elapsed) * 1_000_000_000))
    }
}

func isBenchmarkTimeout(_ error: Error) -> Bool {
    let message = error.localizedDescription.lowercased()
    return message.contains("timed out") || message.contains("timeout")
}

func runBenchmarkPreflight() {
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
    guard let output = try? runBenchmarkProcess(
        executable: "/usr/bin/pgrep",
        arguments: ["-f", "focusrelay"],
        timeout: 3
    ) else {
        print("Preflight: no extra focusrelay server processes detected.")
        return
    }

    let candidatePIDs = output.split(separator: "\n").compactMap { Int32($0) }
    var terminated: [Int32] = []
    for pid in candidatePIDs where pid != currentPID {
        guard let command = try? runBenchmarkProcess(
            executable: "/bin/ps",
            arguments: ["-o", "command=", "-p", String(pid)],
            timeout: 3
        ) else {
            continue
        }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("focusrelay serve") || trimmed.contains("focusrelay mcp") || trimmed.contains("focusrelay server") {
            _ = try? runBenchmarkProcess(executable: "/bin/kill", arguments: ["-TERM", String(pid)], timeout: 2)
            terminated.append(pid)
        }
    }

    if terminated.isEmpty {
        print("Preflight: no extra focusrelay server processes detected.")
    } else {
        print("Preflight: terminated focusrelay server processes: \(terminated.map(String.init).joined(separator: ", "))")
        Thread.sleep(forTimeInterval: 1.0)
    }
}

private func restartOmniFocus() throws {
    print("Preflight: restarting OmniFocus...")
    _ = try? runBenchmarkProcess(
        executable: "/usr/bin/osascript",
        arguments: ["-e", "tell application \"OmniFocus\" to quit"],
        timeout: 8
    )
    Thread.sleep(forTimeInterval: 2.0)
    _ = try runBenchmarkProcess(executable: "/usr/bin/open", arguments: ["-a", "OmniFocus"], timeout: 8)
    Thread.sleep(forTimeInterval: 3.0)
}

func currentOmniFocusPID() -> Int32? {
    guard let output = try? runBenchmarkProcess(
        executable: "/usr/bin/pgrep",
        arguments: ["-x", "OmniFocus"],
        timeout: 3
    ) else {
        return nil
    }
    return output.split(separator: "\n").first.flatMap { Int32($0) }
}

func benchmarkRSSKilobytes(pid: Int32) -> Int? {
    guard let output = try? runBenchmarkProcess(
        executable: "/bin/ps",
        arguments: ["-o", "rss=", "-p", String(pid)],
        timeout: 3
    ) else {
        return nil
    }
    return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
}

@discardableResult
func runBenchmarkProcess(executable: String, arguments: [String], timeout: TimeInterval = 15) throws -> String {
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
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    if process.terminationStatus != 0 {
        throw AutomationError.executionFailed("Process \(executable) failed: \(output)")
    }
    return output
}

func captureBenchmarkTimeoutDiagnostic(
    scenario: String,
    phase: String,
    callIndex: Int,
    latencyMs: Double,
    errorMessage: String
) -> BenchmarkTimeoutDiagnostic {
    let requestID = extractBenchmarkRequestID(from: errorMessage)
    let baseURL = defaultBenchmarkIPCBaseURL()
    let requestsURL = baseURL.appendingPathComponent("requests", isDirectory: true)
    let locksURL = baseURL.appendingPathComponent("locks", isDirectory: true)
    let responsesURL = baseURL.appendingPathComponent("responses", isDirectory: true)
    let omniPID = currentOmniFocusPID()
    let benchmarkPID = ProcessInfo.processInfo.processIdentifier
    let bridgeHealth: BenchmarkTimeoutBridgeHealthSnapshot
    if let result = try? OmniFocusBridgeService().healthCheck() {
        bridgeHealth = BenchmarkTimeoutBridgeHealthSnapshot(
            ok: result.ok,
            detail: "plugin=\(result.plugin ?? "unknown") version=\(result.version ?? "unknown")"
        )
    } else {
        bridgeHealth = BenchmarkTimeoutBridgeHealthSnapshot(
            ok: false,
            detail: "bridge-health-check failed after timeout"
        )
    }

    return BenchmarkTimeoutDiagnostic(
        timestamp: benchmarkISO8601Now(),
        transport: benchmarkTransport,
        scenario: scenario,
        phase: phase,
        callIndex: callIndex,
        latencyMs: latencyMs,
        error: errorMessage,
        requestId: requestID,
        queue: BenchmarkTimeoutQueueSnapshot(
            basePath: baseURL.path,
            requestsCount: benchmarkDirectoryEntryCount(requestsURL),
            locksCount: benchmarkDirectoryEntryCount(locksURL),
            responsesCount: benchmarkDirectoryEntryCount(responsesURL),
            requestExists: requestID.map { FileManager.default.fileExists(atPath: requestsURL.appendingPathComponent("\($0).json").path) },
            lockExists: requestID.map { FileManager.default.fileExists(atPath: locksURL.appendingPathComponent("\($0).lock").path) },
            responseExists: requestID.map { FileManager.default.fileExists(atPath: responsesURL.appendingPathComponent("\($0).json").path) },
            sampleRequests: benchmarkDirectoryEntrySamples(requestsURL),
            sampleLocks: benchmarkDirectoryEntrySamples(locksURL),
            sampleResponses: benchmarkDirectoryEntrySamples(responsesURL)
        ),
        omniFocus: BenchmarkTimeoutProcessSnapshot(
            process: "OmniFocus",
            pid: omniPID,
            rssKB: omniPID.flatMap(benchmarkRSSKilobytes(pid:))
        ),
        focusrelay: BenchmarkTimeoutProcessSnapshot(
            process: "focusrelay",
            pid: benchmarkPID,
            rssKB: benchmarkRSSKilobytes(pid: benchmarkPID)
        ),
        bridgeHealth: bridgeHealth
    )
}

private func extractBenchmarkRequestID(from message: String) -> String? {
    let pattern = #"requestId=([A-F0-9-]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(message.startIndex..<message.endIndex, in: message)
    guard let match = regex.firstMatch(in: message, range: range),
          let matchRange = Range(match.range(at: 1), in: message) else {
        return nil
    }
    return String(message[matchRange])
}

private func benchmarkDirectoryEntryCount(_ url: URL) -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
}

private func benchmarkDirectoryEntrySamples(_ url: URL, limit: Int = 5) -> [String] {
    guard let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return [] }
    return Array(contents.sorted().prefix(limit))
}

private func defaultBenchmarkIPCBaseURL() -> URL {
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

func renderCountBenchmarkSummary(
    title: String,
    startedAt: Date,
    endedAt: Date,
    durationHours: Double,
    warmupCalls: Int,
    intervalMS: Int,
    cooldownMS: Int,
    memoryIntervalSeconds: Int,
    scenarioNames: [String],
    overall: BenchmarkStats,
    scenarios: [String: BenchmarkStats],
    memoryURL: URL,
    timeoutDiagnosticsURL: URL
) -> String {
    let memorySummary = loadBenchmarkMemorySummary(from: memoryURL)
    var lines = [
        "# \(title) Benchmark Summary",
        "",
        "- Started: \(benchmarkISO8601(startedAt))",
        "- Ended: \(benchmarkISO8601(endedAt))",
        String(format: "- Configured duration (hours): %.2f", durationHours),
        "- Warmup calls: \(warmupCalls)",
        "- Interval (ms): \(intervalMS)",
        "- Cooldown after failure (ms): \(cooldownMS)",
        "- Memory sampling interval (seconds): \(memoryIntervalSeconds)",
        "- Scenarios: \(scenarioNames.joined(separator: ", "))",
        "",
        "## Overall Transport Stats",
        "",
        "### \(benchmarkTransport)"
    ]
    appendBenchmarkStats(overall, to: &lines, prefix: "")
    lines.append("")
    lines.append("## Scenario Stats")
    lines.append("")
    for scenario in scenarioNames {
        lines.append("### \(scenario)")
        let stats = scenarios[scenario] ?? BenchmarkStats()
        let total = stats.success + stats.errors
        lines.append(
            "- \(benchmarkTransport): total=\(total), success=\(stats.success), errors=\(stats.errors), error_rate=\(benchmarkFormatPercentage(benchmarkPercentage(part: stats.errors, total: total))), timeouts=\(stats.timeouts), timeout_rate=\(benchmarkFormatPercentage(benchmarkPercentage(part: stats.timeouts, total: total))), p95_ms=\(benchmarkFormatDouble(benchmarkPercentile(stats.latencies, p: 0.95)))"
        )
        lines.append("")
    }
    lines.append("## Memory Notes")
    lines.append("")
    lines.append("- `memory.csv` contains RSS samples for `focusrelay` and `OmniFocus`.")
    lines.append("- Memory growth slope is estimated in KB/min from sampled RSS values.")
    lines.append("- `timeout-diagnostics.jsonl` contains timeout queue/process snapshots for this benchmark.")
    lines.append("")
    lines.append("### Memory Growth")
    for process in ["focusrelay", "OmniFocus"] {
        if let summary = memorySummary[process] {
            lines.append("- \(process): samples=\(summary.samples), start_kb=\(summary.startKB), end_kb=\(summary.endKB), delta_kb=\(summary.endKB - summary.startKB), slope_kb_per_min=\(benchmarkFormatDouble(summary.slopeKBPerMinute))")
        } else {
            lines.append("- \(process): no samples")
        }
    }
    lines.append("")
    lines.append("## Timeout Diagnostics")
    lines.append("")
    lines.append("- Diagnostic entries: \(benchmarkCountLines(in: timeoutDiagnosticsURL))")
    return lines.joined(separator: "\n")
}

private func appendBenchmarkStats(_ stats: BenchmarkStats, to lines: inout [String], prefix: String) {
    let total = stats.success + stats.errors
    lines.append("\(prefix)- Total calls: \(total)")
    lines.append("\(prefix)- Success calls: \(stats.success)")
    lines.append("\(prefix)- Error calls: \(stats.errors)")
    lines.append("\(prefix)- Error rate: \(benchmarkFormatPercentage(benchmarkPercentage(part: stats.errors, total: total)))")
    lines.append("\(prefix)- Timeout calls: \(stats.timeouts)")
    lines.append("\(prefix)- Timeout rate: \(benchmarkFormatPercentage(benchmarkPercentage(part: stats.timeouts, total: total)))")
    lines.append("\(prefix)- p50 latency (ms): \(benchmarkFormatDouble(benchmarkPercentile(stats.latencies, p: 0.50)))")
    lines.append("\(prefix)- p95 latency (ms): \(benchmarkFormatDouble(benchmarkPercentile(stats.latencies, p: 0.95)))")
    lines.append("\(prefix)- p99 latency (ms): \(benchmarkFormatDouble(benchmarkPercentile(stats.latencies, p: 0.99)))")
}

func benchmarkCountLines(in url: URL) -> Int {
    guard let content = try? String(contentsOf: url, encoding: .utf8), !content.isEmpty else { return 0 }
    return content.split(separator: "\n", omittingEmptySubsequences: true).count
}

func benchmarkPercentile(_ values: [Double], p: Double) -> Double {
    guard !values.isEmpty else { return .nan }
    let sorted = values.sorted()
    let index = Int(Double(sorted.count - 1) * p)
    return sorted[max(0, min(index, sorted.count - 1))]
}

func benchmarkFormatDouble(_ value: Double) -> String {
    guard value.isFinite else { return "n/a" }
    return String(format: "%.2f", value)
}

func benchmarkFormatPercentage(_ value: Double) -> String {
    guard value.isFinite else { return "n/a" }
    return String(format: "%.2f%%", value)
}

func benchmarkPercentage(part: Int, total: Int) -> Double {
    guard total > 0 else { return .nan }
    return (Double(part) / Double(total)) * 100.0
}

private struct BenchmarkMemorySample {
    let timestamp: Date
    let rssKB: Double
}

private struct BenchmarkMemoryProcessSummary {
    let samples: Int
    let startKB: Int
    let endKB: Int
    let slopeKBPerMinute: Double
}

private func loadBenchmarkMemorySummary(from url: URL) -> [String: BenchmarkMemoryProcessSummary] {
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
    var grouped: [String: [BenchmarkMemorySample]] = [:]
    for line in content.split(separator: "\n").dropFirst() {
        let parts = line.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 4,
              let timestamp = benchmarkParseISO8601(String(parts[0])),
              let rss = Double(parts[3]) else {
            continue
        }
        grouped[String(parts[1]), default: []].append(BenchmarkMemorySample(timestamp: timestamp, rssKB: rss))
    }

    var summaries: [String: BenchmarkMemoryProcessSummary] = [:]
    for (process, samples) in grouped {
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first, let last = sorted.last else { continue }
        summaries[process] = BenchmarkMemoryProcessSummary(
            samples: sorted.count,
            startKB: Int(first.rssKB),
            endKB: Int(last.rssKB),
            slopeKBPerMinute: benchmarkLinearSlope(samples: sorted)
        )
    }
    return summaries
}

private func benchmarkLinearSlope(samples: [BenchmarkMemorySample]) -> Double {
    guard samples.count > 1, let first = samples.first else { return .nan }
    let points = samples.map {
        (x: $0.timestamp.timeIntervalSince(first.timestamp) / 60.0, y: $0.rssKB)
    }
    let meanX = points.map(\.x).reduce(0, +) / Double(points.count)
    let meanY = points.map(\.y).reduce(0, +) / Double(points.count)
    let numerator = points.reduce(0.0) { $0 + (($1.x - meanX) * ($1.y - meanY)) }
    let denominator = points.reduce(0.0) { $0 + (($1.x - meanX) * ($1.x - meanX)) }
    return denominator == 0 ? .nan : numerator / denominator
}

func benchmarkISO8601Now() -> String {
    benchmarkISO8601(Date())
}

func benchmarkISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func benchmarkParseISO8601(_ value: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: value) { return date }
    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    return standard.date(from: value)
}
#endif
