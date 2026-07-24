import Foundation
import Testing

@Suite("Benchmark suite result script")
struct BenchmarkSuiteResultScriptTests {
    @Test("clean required scenarios pass")
    func cleanSuitePasses() throws {
        let fixture = try BenchmarkSuiteFixture()
        try fixture.writeCleanSuite()

        let result = try fixture.runValidator()

        #expect(result.status == 0)
        #expect(result.output.contains("Benchmark suite evidence passed"))
    }

    @Test(
        "invalid evidence fails closed",
        arguments: [
            FailureFixture.timeout,
            .error,
            .incompleteCoverage,
            .malformedJSON,
            .missingRaw,
            .missingSummary,
        ]
    )
    func invalidEvidenceFailsClosed(failure: FailureFixture) throws {
        let fixture = try BenchmarkSuiteFixture()
        try fixture.writeCleanSuite()
        try fixture.apply(failure)

        let result = try fixture.runValidator()

        #expect(result.status != 0)
        #expect(result.output.contains(failure.expectedDiagnostic))
        #expect(result.output.contains("Artifacts retained"))
    }
}

enum FailureFixture: CaseIterable, Sendable {
    case timeout
    case error
    case incompleteCoverage
    case malformedJSON
    case missingRaw
    case missingSummary

    var expectedDiagnostic: String {
        switch self {
        case .timeout: "timed out"
        case .error: "reported an error"
        case .incompleteCoverage: "missing measured scenario search_no_match"
        case .malformedJSON: "malformed JSON"
        case .missingRaw: "missing or empty raw.jsonl"
        case .missingSummary: "missing or empty summary.md"
        }
    }
}

private struct BenchmarkSuiteFixture {
    let root: URL
    let validator: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("focusrelay-benchmark-\(UUID().uuidString)", isDirectory: true)
        validator = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/check-benchmark-suite-results.sh")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func writeCleanSuite() throws {
        try writeTool("get_task_counts", scenarios: [
            "default", "inbox_only", "available_only", "completed_after_anchor",
            "flagged_only", "search_no_match",
        ])
        try writeTool("list_tasks", scenarios: [
            "default", "default_no_total", "inbox_only", "inbox_only_no_total",
            "available_only", "available_only_no_total", "completed_after_anchor",
            "flagged_only", "flagged_only_no_total", "search_no_match",
        ])
        try writeTool("get_project_counts", scenarios: [
            "project_view_remaining", "project_view_active", "project_view_available",
            "project_view_everything", "completed_after_anchor",
        ])
    }

    func apply(_ failure: FailureFixture) throws {
        let tool = root.appendingPathComponent("get_task_counts", isDirectory: true)
        let raw = tool.appendingPathComponent("raw.jsonl")
        switch failure {
        case .timeout:
            try append(
                #"{"phase":"measured","scenario":"default","ok":false,"timeout":true,"error":"timed out"}"#,
                to: raw
            )
        case .error:
            try append(
                #"{"phase":"measured","scenario":"default","ok":false,"timeout":false,"error":"failed"}"#,
                to: raw
            )
        case .incompleteCoverage:
            let contents = try String(contentsOf: raw, encoding: .utf8)
                .split(separator: "\n")
                .filter { !$0.contains(#""scenario":"search_no_match""#) }
                .joined(separator: "\n") + "\n"
            try contents.write(to: raw, atomically: true, encoding: .utf8)
        case .malformedJSON:
            try append("{not-json}", to: raw)
        case .missingRaw:
            try FileManager.default.removeItem(at: raw)
        case .missingSummary:
            try FileManager.default.removeItem(at: tool.appendingPathComponent("summary.md"))
        }
    }

    func runValidator() throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [validator.path, root.path]
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, output)
    }

    private func writeTool(_ name: String, scenarios: [String]) throws {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rows = scenarios.map {
            #"{"phase":"measured","scenario":"\#($0)","ok":true,"timeout":false}"#
        }.joined(separator: "\n") + "\n"
        try rows.write(
            to: directory.appendingPathComponent("raw.jsonl"),
            atomically: true,
            encoding: .utf8
        )
        try "# Summary\n".write(
            to: directory.appendingPathComponent("summary.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func append(_ line: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\(line)\n".utf8))
    }
}
