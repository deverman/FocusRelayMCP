import ArgumentParser
import Foundation
import FocusRelayDevCore

struct CreationBenchmark: AsyncParsableCommand {
    enum Profile: String, ExpressibleByArgument { case canary, smoke }
    static let configuration = CommandConfiguration(commandName: "creation-benchmark", abstract: "Sequential preview-only add_tasks measurements; never applies or retries.")
    @Option(help: "Required: canary (nine calls) or smoke (ten minutes).") var profile: Profile
    @Option(help: "Disposable existing project ID.") var projectID: String
    @Option(help: "Disposable existing parent task ID.") var parentID: String
    @Option(help: "Optional existing tag ID.") var tagID: String?
    @Option(help: "Server binary to measure.") var serverPath = ".build/debug/focusrelay"
    @Option(help: "New output directory; must not already exist.") var outputDir: String

    mutating func validate() throws {
        for id in [projectID, parentID] + (tagID.map { [$0] } ?? []) {
            guard !id.isEmpty, id == id.trimmingCharacters(in: .whitespacesAndNewlines) else {
                throw ValidationError("Fixture IDs must be nonempty without surrounding whitespace.")
            }
        }
        guard FileManager.default.isExecutableFile(atPath: serverPath) else { throw ValidationError("Server is not executable.") }
        guard !FileManager.default.fileExists(atPath: outputDir) else { throw ValidationError("Output directory already exists.") }
    }

    struct Sample: Codable {
        let scenario: String
        let classification: BridgeBurstClassification
        let milliseconds: Double
    }

    func run() async throws {
        let directory = URL(fileURLWithPath: outputDir)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let raw = directory.appendingPathComponent("timings.jsonl")
        try Data().write(to: raw)
        let handle = try FileHandle(forWritingTo: raw)
        defer { try? handle.close() }
        let transport = StdioMCPBurstTransport(serverPath: serverPath, currentDirectory: FileManager.default.currentDirectoryPath)
        let heartbeat = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(25)) } catch { break }
                creationProgress("[running] creation-preview benchmark")
            }
        }
        defer { heartbeat.cancel() }
        var samples: [Sample] = []
        let started = Date()
        do {
            try await transport.start()
            try await transport.initialize(timeout: .seconds(10))
            let clock = ContinuousClock()
            let begin = clock.now
            repeat {
                let scenario = CreationPreviewScenario.allCases[samples.count % 3]
                let before = clock.now
                let classification: BridgeBurstClassification
                do {
                    classification = try await transport.call(.init(id: samples.count + 2, toolName: "add_tasks",
                        arguments: scenario.arguments(projectID: projectID, parentID: parentID, tagID: tagID)), timeout: .seconds(60))
                } catch let error as BridgeBurstTransportError { classification = error.classification }
                let elapsed = before.duration(to: clock.now).components
                let ms = Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
                let sample = Sample(scenario: scenario.rawValue, classification: classification, milliseconds: ms)
                samples.append(sample)
                try handle.write(contentsOf: JSONEncoder().encode(sample) + Data([10]))
                creationProgress("\(samples.count) \(scenario.rawValue): \(classification.rawValue) \(String(format: "%.2f", ms))ms")
                guard classification == .success else { throw ValidationError("Stopped after first failure; no retry or diagnostic Bridge call.") }
                if profile == .smoke { try await Task.sleep(for: .seconds(5)) }
            } while profile == .canary ? samples.count < 9 : begin.duration(to: clock.now) < .seconds(600)
            await transport.stop()
            try writeSummary(directory, samples: samples, started: started, status: "passed")
        } catch {
            await transport.stop()
            try writeSummary(directory, samples: samples, started: started, status: "failed")
            throw error
        }
    }

    private func writeSummary(_ directory: URL, samples: [Sample], started: Date, status: String) throws {
        let stats: [[String: Any]] = CreationPreviewScenario.allCases.map { scenario in
            let values = samples.filter { $0.scenario == scenario.rawValue && $0.classification == .success }.map(\.milliseconds).sorted()
            return ["scenario": scenario.rawValue, "successCount": values.count,
                    "p50Milliseconds": values.isEmpty ? NSNull() : values[Int(ceil(Double(values.count) * 0.5)) - 1] as Any,
                    "p95Milliseconds": values.isEmpty ? NSNull() : values[Int(ceil(Double(values.count) * 0.95)) - 1] as Any]
        }
        let summary: [String: Any] = ["profile": profile.rawValue, "status": status, "calls": samples.count,
            "started": ISO8601DateFormatter().string(from: started), "elapsedSeconds": Date().timeIntervalSince(started),
            "serverPath": serverPath, "scenarios": stats,
            "scope": "Sequential three-node creation previews only; no apply throughput claim. MCP errors classified; semantic correctness is gated separately."]
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("summary.json"))
    }
}

private func creationProgress(_ message: String) {
    FileHandle.standardOutput.write(Data((message + "\n").utf8))
}
