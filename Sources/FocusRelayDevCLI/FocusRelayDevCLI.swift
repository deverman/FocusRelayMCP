import ArgumentParser
import Foundation
import FocusRelayDevCore

@main
struct FocusRelayDevCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "focusrelay-dev",
        abstract: "Developer-only validation and release orchestration.",
        subcommands: [Classify.self, Validate.self, CheckMarkdownLinks.self, Benchmark.self, ReleasePlan.self, ReleaseVerify.self, WorkspaceReport.self]
    )
}

private struct Classify: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Classify changed files conservatively.")

    @Option(help: "Git base revision.") var base = "origin/master"
    @Flag(help: "Emit JSON.") var json = false

    func run() throws {
        let changed = try CommandRunner.capture("git", ["diff", "--name-only", base])
        let untracked = try CommandRunner.capture("git", ["ls-files", "--others", "--exclude-standard"])
        let files = (changed + "\n" + untracked).split(separator: "\n").map(String.init)
        let result = ChangeClassifier.classify(files)
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(result))
            print()
        } else {
            print(result.impact.rawValue)
            result.reasons.forEach { print("- \($0)") }
        }
    }
}

private struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run the checks required by one impact class.")

    @Option(help: "Validation impact from docs through transport-reliability.")
    var impact: ValidationImpact

    func run() throws {
        let started = Date()
        let steps = ValidationPlanner.steps(
            for: impact,
            disableNestedSwiftSandbox: ProcessInfo.processInfo.environment["CODEX_SANDBOX"] != nil
        )
        for step in steps {
            let executable = step.executable == "focusrelay-dev" ? CommandLine.arguments[0] : step.executable
            try CommandRunner.run(step.name, executable, step.arguments)
        }
        try writeReport(kind: "validate", values: [
            "impact": impact.rawValue,
            "status": "passed",
            "elapsedSeconds": String(format: "%.2f", Date().timeIntervalSince(started))
        ])
    }
}

private struct CheckMarkdownLinks: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "check-markdown-links", abstract: "Validate local Markdown links with swift-markdown.")

    @Option(help: "Repository or documentation root.") var root = "."

    func run() throws {
        let rootURL = URL(fileURLWithPath: root, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath)).standardizedFileURL
        let broken = try MarkdownLinkValidator.validate(root: rootURL)
        guard broken.isEmpty else {
            broken.forEach { print("\($0.source): \($0.destination)") }
            throw ValidationError("Found \(broken.count) broken local Markdown link(s).")
        }
        print("Local Markdown links are valid.")
    }
}

private struct Benchmark: ParsableCommand {
    enum Profile: String, ExpressibleByArgument { case canary, smoke, release, stress }
    static let configuration = CommandConfiguration(abstract: "Run an explicit benchmark profile.")

    @Option(help: "Required profile: canary, smoke, release, or stress.") var profile: Profile

    func run() throws {
        switch profile {
        case .canary:
            let sandboxArguments = ProcessInfo.processInfo.environment["CODEX_SANDBOX"] == nil ? [] : ["--disable-sandbox"]
            try CommandRunner.run("Semantic canary", "swift", ["run"] + sandboxArguments + ["focusrelay", "benchmark-gate-check", "--tool", "all"])
        case .smoke:
            try CommandRunner.run("Ten-minute-per-tool smoke suite", "./scripts/benchmark-suite.sh", ["--profile", "smoke"], timeoutSeconds: 2_700)
        case .release:
            try CommandRunner.run("Release validation suite", "./scripts/benchmark-suite.sh", ["--profile", "release"], timeoutSeconds: 7_200)
        case .stress:
            try CommandRunner.run("Diagnostic stress suite", "./scripts/benchmark-suite.sh", ["--profile", "stress"], timeoutSeconds: 14_400)
        }
    }
}

private struct ReleasePlan: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "release-plan", abstract: "Capture the frozen production fingerprint.")
    @Option(help: "Release version or tag.") var version: String

    func run() throws {
        let commit = try CommandRunner.capture("git", ["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        let swiftVersion = try CommandRunner.capture("swift", ["--version"]).split(separator: "\n").first.map(String.init) ?? "unknown"
        let productionHash = try productionFingerprint()
        try writeReport(kind: "release-plan", values: [
            "version": version, "commit": commit, "swift": swiftVersion, "productionFingerprint": productionHash
        ])
        print("Release candidate \(version)")
        print("commit: \(commit)")
        print("production fingerprint: \(productionHash)")
    }
}

private struct ReleaseVerify: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "release-verify", abstract: "Verify published assets, checksum, and embedded binary version.")
    @Option(help: "Release version or tag.") var version: String

    func run() throws {
        let tag = version.hasPrefix("v") ? version : "v\(version)"
        let expectedVersion = String(tag.dropFirst())
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/focusrelay-validation/releases/\(tag)", isDirectory: true)
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try CommandRunner.run("Verify GitHub release metadata", "gh", ["release", "view", tag, "--repo", "deverman/FocusRelayMCP"])
        try CommandRunner.run("Download release assets", "gh", ["release", "download", tag, "--repo", "deverman/FocusRelayMCP", "--dir", root.path])

        let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let archive = try required(contents.first { $0.pathExtension == "gz" }, "Missing release tarball.")
        let checksumFile = try required(contents.first { $0.pathExtension == "sha256" }, "Missing checksum asset.")
        let expectedChecksum = try required(String(contentsOf: checksumFile, encoding: .utf8).split(whereSeparator: \.isWhitespace).first.map(String.init), "Checksum asset is empty.")
        let actualChecksum = try required(CommandRunner.capture("shasum", ["-a", "256", archive.path]).split(whereSeparator: \.isWhitespace).first.map(String.init), "Could not calculate tarball checksum.")
        guard expectedChecksum == actualChecksum else { throw ValidationError("Release checksum does not match the tarball.") }

        let extracted = root.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        try CommandRunner.run("Extract release", "tar", ["-xzf", archive.path, "-C", extracted.path])
        let binaries = FileManager.default.enumerator(at: extracted, includingPropertiesForKeys: [.isRegularFileKey])?
            .allObjects.compactMap { $0 as? URL }.filter { $0.lastPathComponent == "focusrelay" } ?? []
        let binary = try required(binaries.first, "Packaged focusrelay binary is missing.")
        let embedded = try CommandRunner.capture(binary.path, ["--version"])
        guard embedded.contains(expectedVersion) else { throw ValidationError("Embedded version does not match \(expectedVersion): \(embedded)") }
        print("Release \(tag) verified: checksum and embedded version match.")
    }
}

private struct WorkspaceReport: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "workspace-report", abstract: "Report worktrees and merged local branches without deleting anything.")
    func run() throws {
        print("Worktrees:\n" + (try CommandRunner.capture("git", ["worktree", "list"])))
        print("Merged branches:\n" + (try CommandRunner.capture("git", ["branch", "--merged", "master"])))
        print("Report only. Remove worktrees or branches explicitly after review.")
    }
}

private enum CommandRunner {
    static func capture(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else { throw ValidationError(output) }
        return output
    }

    static func run(_ name: String, _ executable: String, _ arguments: [String], timeoutSeconds: TimeInterval = 1_800) throws {
        let process = Process()
        let pipe = Pipe()
        let state = RunState()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        process.standardOutput = pipe
        process.standardError = pipe
        let started = Date()
        emit("[start] \(name)")
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            if state.markFirstOutput() {
                emit("[first-output] \(name) elapsed=\(String(format: "%.2f", Date().timeIntervalSince(started)))s")
            }
            FileHandle.standardOutput.write(data)
        }
        try process.run()
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler {
            let elapsed = Date().timeIntervalSince(started)
            emit("[running] \(name) elapsed=\(Int(elapsed))s")
            if elapsed >= timeoutSeconds, process.isRunning {
                state.markTimedOut()
                process.terminate()
            }
        }
        timer.resume()
        process.waitUntilExit()
        timer.cancel()
        pipe.fileHandleForReading.readabilityHandler = nil
        let remainder = pipe.fileHandleForReading.readDataToEndOfFile()
        if !remainder.isEmpty { FileHandle.standardOutput.write(remainder) }
        let elapsed = Date().timeIntervalSince(started)
        emit("[end] \(name) status=\(process.terminationStatus) elapsed=\(String(format: "%.2f", elapsed))s")
        if state.timedOut {
            throw ValidationError("\(name) exceeded its \(Int(timeoutSeconds))-second timeout.")
        }
        guard process.terminationStatus == 0 else { throw ExitCode(process.terminationStatus) }
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var sawOutput = false
    private var didTimeOut = false

    func markFirstOutput() -> Bool {
        lock.withLock {
            guard !sawOutput else { return false }
            sawOutput = true
            return true
        }
    }

    func markTimedOut() { lock.withLock { didTimeOut = true } }
    var timedOut: Bool { lock.withLock { didTimeOut } }
}

private func emit(_ message: String) {
    FileHandle.standardOutput.write(Data("\(message)\n".utf8))
}

private func productionFingerprint() throws -> String {
    let tracked = try CommandRunner.capture("git", ["ls-files", "--cached", "--others", "--exclude-standard", "Package.swift", "Package.resolved", "Sources", "Plugin/FocusRelayBridge.omnijs"])
        .split(separator: "\n").map(String.init)
    let hashes = try CommandRunner.capture("git", ["hash-object"] + tracked).split(separator: "\n").map(String.init)
    let listing = zip(tracked, hashes).map { "\($0.0) \($0.1)" }.joined(separator: "\n")
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data(listing.utf8).write(to: temporary)
    defer { try? FileManager.default.removeItem(at: temporary) }
    return try CommandRunner.capture("shasum", ["-a", "256", temporary.path]).split(separator: " ").first.map(String.init) ?? "unknown"
}

private func required<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw ValidationError(message) }
    return value
}

private func writeReport(kind: String, values: [String: String]) throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/focusrelay-validation", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let formatter = ISO8601DateFormatter()
    let report: [String: Any] = ["kind": kind, "generatedAt": formatter.string(from: Date()), "values": values]
    let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: directory.appendingPathComponent("\(kind)-latest.json"))
}

extension ValidationImpact: ExpressibleByArgument {}
