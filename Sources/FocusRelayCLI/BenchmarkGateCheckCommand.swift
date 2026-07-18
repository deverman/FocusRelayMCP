#if DEBUG
import ArgumentParser
import Foundation
import OmniFocusAutomation
import OmniFocusCore

struct BenchmarkGateCheck: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark-gate-check",
        abstract: "Run Bridge health and semantic contracts before benchmarks.",
        aliases: ["benchmark_gate_check"]
    )

    @Option(name: .customLong("tool"), help: "Gate scope: all, task-counts, list-tasks, or project-counts.")
    var tool: GateScope = .all

    func run() async throws {
        let bridge = OmniFocusBridgeService()
        var checks = [await checkBridgeHealth(using: bridge)]

        switch tool {
        case .all:
            checks.append(contentsOf: await taskCountContractChecks(using: bridge))
            checks.append(await projectCountsBridgeActiveContractCheck(using: bridge))
        case .taskCounts, .listTasks:
            checks.append(contentsOf: await taskCountContractChecks(using: bridge))
        case .projectCounts:
            checks.append(await projectCountsBridgeActiveContractCheck(using: bridge))
        }

        let report = GateReport(
            ok: checks.allSatisfy(\.ok),
            tool: tool.rawValue,
            generatedAt: gateISO8601(Date()),
            architecture: "bridge-plugin-url",
            checks: checks
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))

        if !report.ok {
            throw ExitCode.failure
        }
    }
}

enum GateScope: String, ExpressibleByArgument {
    case all
    case taskCounts = "task-counts"
    case listTasks = "list-tasks"
    case projectCounts = "project-counts"
}

private struct GateReport: Codable {
    let ok: Bool
    let tool: String
    let generatedAt: String
    let architecture: String
    let checks: [GateCheck]
}

private struct GateCheck: Codable {
    let name: String
    let ok: Bool
    let detail: String
}

struct GateTaskCountScenario {
    let name: String
    let filter: TaskFilter
    let expectedTotal: Int?

    init(name: String, filter: TaskFilter, expectedTotal: Int? = nil) {
        self.name = name
        self.filter = filter
        self.expectedTotal = expectedTotal
    }
}

private let gateCompletedAfterAnchor = Date(timeIntervalSince1970: 0)
private let gateNoMatchSearch = "__focusrelay_semantic_gate_no_match_7f43d9__"

func gateTaskCountContractScenarios() -> [GateTaskCountScenario] {
    [
        GateTaskCountScenario(name: "default", filter: TaskFilter(includeTotalCount: true)),
        GateTaskCountScenario(name: "inbox_only", filter: TaskFilter(inboxOnly: true, includeTotalCount: true)),
        GateTaskCountScenario(name: "available_only", filter: TaskFilter(availableOnly: true, includeTotalCount: true)),
        GateTaskCountScenario(name: "flagged_only", filter: TaskFilter(flagged: true, includeTotalCount: true)),
        GateTaskCountScenario(
            name: "completed_after_anchor",
            filter: TaskFilter(completed: true, completedAfter: gateCompletedAfterAnchor, includeTotalCount: true)
        ),
        GateTaskCountScenario(
            name: "search_no_match",
            filter: TaskFilter(availableOnly: false, inboxView: "everything", search: gateNoMatchSearch, includeTotalCount: true),
            expectedTotal: 0
        )
    ]
}

private func checkBridgeHealth(using service: OmniFocusBridgeService) async -> GateCheck {
    do {
        let result = try service.healthCheck()
        return GateCheck(
            name: "bridge_health",
            ok: result.ok,
            detail: result.ok
                ? "plugin=\(result.plugin ?? "unknown") version=\(result.version ?? "unknown")"
                : (result.error ?? "Bridge health check failed")
        )
    } catch {
        return GateCheck(name: "bridge_health", ok: false, detail: error.localizedDescription)
    }
}

private func taskCountContractChecks(using bridge: OmniFocusBridgeService) async -> [GateCheck] {
    await gateTaskCountContractScenarios().asyncMap { scenario in
        do {
            let counts = try await retryAsync(operation: "bridge task-counts contract \(scenario.name)") {
                try await bridge.getTaskCounts(filter: scenario.filter)
            }
            let page = try await retryAsync(operation: "bridge list-tasks contract \(scenario.name)") {
                try await bridge.listTasks(filter: scenario.filter, page: PageRequest(limit: 50), fields: ["id"])
            }
            guard let total = page.totalCount else {
                return GateCheck(
                    name: "task_counts_contract_\(scenario.name)",
                    ok: false,
                    detail: "list_tasks returned nil totalCount"
                )
            }
            let matchesExpectedTotal = scenario.expectedTotal.map { counts.total == $0 && total == $0 } ?? true
            return GateCheck(
                name: "task_counts_contract_\(scenario.name)",
                ok: counts.total == total && matchesExpectedTotal,
                detail: "counts.total=\(counts.total) list.totalCount=\(total) expected=\(scenario.expectedTotal.map(String.init) ?? "any")"
            )
        } catch {
            return GateCheck(
                name: "task_counts_contract_\(scenario.name)",
                ok: false,
                detail: error.localizedDescription
            )
        }
    }
}

private func projectCountsBridgeActiveContractCheck(using bridge: OmniFocusBridgeService) async -> GateCheck {
    let filter = TaskFilter(completed: false, availableOnly: false, projectView: "active", includeTotalCount: true)
    do {
        let counts = try await retryAsync(operation: "bridge project-counts active contract") {
            try await bridge.getProjectCounts(filter: filter)
        }
        let page = try await retryAsync(operation: "bridge list-tasks active contract") {
            try await bridge.listTasks(filter: filter, page: PageRequest(limit: 50), fields: ["id"])
        }
        guard let total = page.totalCount else {
            return GateCheck(
                name: "project_counts_active_contract_bridge",
                ok: false,
                detail: "list_tasks returned nil totalCount"
            )
        }
        return GateCheck(
            name: "project_counts_active_contract_bridge",
            ok: counts.actions == total,
            detail: "counts.actions=\(counts.actions) list.totalCount=\(total)"
        )
    } catch {
        return GateCheck(
            name: "project_counts_active_contract_bridge",
            ok: false,
            detail: error.localizedDescription
        )
    }
}

private func retryAsync<T>(
    operation: String,
    maxAttempts: Int = 2,
    delayNanoseconds: UInt64 = 750_000_000,
    _ body: () async throws -> T
) async throws -> T {
    var lastError: Error?
    for attempt in 1...maxAttempts {
        do {
            return try await body()
        } catch {
            lastError = error
            if attempt == maxAttempts {
                throw AutomationError.executionFailed(
                    "\(operation) failed on attempt \(attempt)/\(maxAttempts): \(error.localizedDescription)"
                )
            }
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
    }
    throw lastError ?? AutomationError.executionFailed("\(operation) failed without a specific error")
}

private func gateISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async -> T) async -> [T] {
        var result: [T] = []
        result.reserveCapacity(count)
        for element in self {
            result.append(await transform(element))
        }
        return result
    }
}
#endif
