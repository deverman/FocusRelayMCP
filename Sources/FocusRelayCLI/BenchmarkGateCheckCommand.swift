import ArgumentParser
import Foundation
import OmniFocusAutomation
import OmniFocusCore

struct BenchmarkGateCheck: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "benchmark-gate-check",
        abstract: "Run readiness, parity, and count-contract checks before benchmarks.",
        aliases: ["benchmark_gate_check"]
    )

    @Option(name: .customLong("tool"), help: "Gate scope: all, task-counts, list-tasks, or project-counts.")
    var tool: GateScope = .all

    func run() async throws {
        let bridge = OmniFocusBridgeService()
        let jxa = OmniAutomationService()
        var checks: [GateCheck] = []

        checks.append(await checkBridgeHealth(using: bridge))
        checks.append(await checkJXAProbe(using: jxa))

        switch tool {
        case .all:
            checks.append(contentsOf: await taskCountContractChecks(using: bridge))
            checks.append(contentsOf: await taskCountParityChecks(bridge: bridge, jxa: jxa))
            checks.append(contentsOf: await listTaskParityChecks(bridge: bridge, jxa: jxa))
            checks.append(await projectCountsBridgeActiveContractCheck(using: bridge))
            checks.append(contentsOf: await projectCountParityChecks(bridge: bridge, jxa: jxa))
        case .taskCounts:
            checks.append(contentsOf: await taskCountContractChecks(using: bridge))
            checks.append(contentsOf: await taskCountParityChecks(bridge: bridge, jxa: jxa))
        case .listTasks:
            checks.append(contentsOf: await listTaskParityChecks(bridge: bridge, jxa: jxa))
        case .projectCounts:
            checks.append(await projectCountsBridgeActiveContractCheck(using: bridge))
            checks.append(contentsOf: await projectCountParityChecks(bridge: bridge, jxa: jxa))
        }

        let report = GateReport(
            ok: checks.allSatisfy(\.ok),
            tool: tool.rawValue,
            generatedAt: gateISO8601(Date()),
            dispatchTransport: ProcessInfo.processInfo.environment["FOCUS_RELAY_BRIDGE_DISPATCH_TRANSPORT"] ?? "url",
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
    case all = "all"
    case taskCounts = "task-counts"
    case listTasks = "list-tasks"
    case projectCounts = "project-counts"
}

private struct GateReport: Codable {
    let ok: Bool
    let tool: String
    let generatedAt: String
    let dispatchTransport: String
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
}

struct GateListTaskScenario {
    let name: String
    let filter: TaskFilter
}

struct GateProjectCountScenario {
    let name: String
    let filter: TaskFilter
}

private let gateCompletedAfterAnchor = Date(timeIntervalSince1970: 0)

private func checkBridgeHealth(using service: OmniFocusBridgeService) async -> GateCheck {
    do {
        let result = try service.healthCheck()
        return GateCheck(
            name: "bridge_health",
            ok: result.ok,
            detail: result.ok ? "plugin=\(result.plugin ?? "unknown") version=\(result.version ?? "unknown")" : (result.error ?? "Bridge health check failed")
        )
    } catch {
        return GateCheck(name: "bridge_health", ok: false, detail: error.localizedDescription)
    }
}

private func checkJXAProbe(using service: OmniAutomationService) async -> GateCheck {
    do {
        let probe = try await service.debugInboxProbe()
        return GateCheck(
            name: "jxa_probe",
            ok: true,
            detail: "inboxTasks=\(probe.inboxTasksCount) inInbox=\(probe.inboxInInboxCount)"
        )
    } catch {
        return GateCheck(name: "jxa_probe", ok: false, detail: error.localizedDescription)
    }
}

func gateTaskCountContractScenarios() -> [GateTaskCountScenario] {
    [
        GateTaskCountScenario(name: "default", filter: TaskFilter(includeTotalCount: true)),
        GateTaskCountScenario(name: "inbox_only", filter: TaskFilter(inboxOnly: true, includeTotalCount: true)),
        GateTaskCountScenario(name: "available_only", filter: TaskFilter(availableOnly: true, includeTotalCount: true)),
        GateTaskCountScenario(
            name: "completed_after_anchor",
            filter: TaskFilter(completed: true, completedAfter: gateCompletedAfterAnchor, includeTotalCount: true)
        )
    ]
}

func gateTaskCountParityScenarios() -> [GateTaskCountScenario] {
    [
        GateTaskCountScenario(name: "default", filter: TaskFilter()),
        GateTaskCountScenario(name: "inbox_only", filter: TaskFilter(inboxOnly: true)),
        GateTaskCountScenario(name: "available_only", filter: TaskFilter(availableOnly: true)),
        GateTaskCountScenario(name: "flagged_only", filter: TaskFilter(flagged: true)),
        GateTaskCountScenario(
            name: "completed_after_anchor",
            filter: TaskFilter(completed: true, completedAfter: gateCompletedAfterAnchor)
        )
    ]
}

func gateListTaskParityScenarios(projectID: String?) -> [GateListTaskScenario] {
    var scenarios = [
        GateListTaskScenario(name: "default", filter: TaskFilter(includeTotalCount: true)),
        GateListTaskScenario(name: "default_no_total", filter: TaskFilter(includeTotalCount: false)),
        GateListTaskScenario(name: "inbox_only", filter: TaskFilter(inboxOnly: true, includeTotalCount: true)),
        GateListTaskScenario(name: "inbox_only_no_total", filter: TaskFilter(inboxOnly: true, includeTotalCount: false)),
        GateListTaskScenario(name: "available_only", filter: TaskFilter(availableOnly: true, includeTotalCount: true)),
        GateListTaskScenario(name: "available_only_no_total", filter: TaskFilter(availableOnly: true, includeTotalCount: false)),
        GateListTaskScenario(name: "flagged_only", filter: TaskFilter(flagged: true, includeTotalCount: true)),
        GateListTaskScenario(name: "flagged_only_no_total", filter: TaskFilter(flagged: true, includeTotalCount: false)),
        GateListTaskScenario(
            name: "completed_after_anchor",
            filter: TaskFilter(completed: true, completedAfter: gateCompletedAfterAnchor, includeTotalCount: true)
        )
    ]

    if let projectID, !projectID.isEmpty {
        scenarios.append(GateListTaskScenario(name: "project_scoped_simple", filter: TaskFilter(project: projectID, includeTotalCount: true)))
    }

    return scenarios
}

func gateProjectCountParityScenarios() -> [GateProjectCountScenario] {
    [
        GateProjectCountScenario(name: "project_view_remaining", filter: TaskFilter(projectView: "remaining")),
        GateProjectCountScenario(name: "project_view_active", filter: TaskFilter(projectView: "active")),
        GateProjectCountScenario(
            name: "completed_after_anchor",
            filter: TaskFilter(completed: true, completedAfter: gateCompletedAfterAnchor)
        )
    ]
}

private func taskCountContractChecks(using bridge: OmniFocusBridgeService) async -> [GateCheck] {
    let scenarios = gateTaskCountContractScenarios()

    return await scenarios.asyncMap { scenario in
        do {
            let counts = try await retryAsync(operation: "bridge task-counts contract \(scenario.name)") {
                try await bridge.getTaskCounts(filter: scenario.filter)
            }
            let page = try await retryAsync(operation: "bridge list-tasks contract \(scenario.name)") {
                try await bridge.listTasks(filter: scenario.filter, page: PageRequest(limit: 50), fields: ["id"])
            }
            guard let total = page.totalCount else {
                return GateCheck(name: "task_counts_contract_\(scenario.name)", ok: false, detail: "list_tasks returned nil totalCount")
            }
            return GateCheck(
                name: "task_counts_contract_\(scenario.name)",
                ok: counts.total == total,
                detail: "counts.total=\(counts.total) list.totalCount=\(total)"
            )
        } catch {
            return GateCheck(name: "task_counts_contract_\(scenario.name)", ok: false, detail: error.localizedDescription)
        }
    }
}

private func taskCountParityChecks(bridge: OmniFocusBridgeService, jxa: OmniAutomationService) async -> [GateCheck] {
    let scenarios = gateTaskCountParityScenarios()

    return await scenarios.asyncMap { scenario in
        do {
            let bridgeCounts = try await retryAsync(operation: "bridge task-counts parity \(scenario.name)") {
                try await bridge.getTaskCounts(filter: scenario.filter)
            }
            let jxaCounts = try await retryAsync(operation: "jxa task-counts parity \(scenario.name)") {
                try await jxa.getTaskCounts(filter: scenario.filter)
            }
            let ok = bridgeCounts.total == jxaCounts.total
                && bridgeCounts.completed == jxaCounts.completed
                && bridgeCounts.available == jxaCounts.available
                && bridgeCounts.flagged == jxaCounts.flagged
            return GateCheck(
                name: "task_counts_parity_\(scenario.name)",
                ok: ok,
                detail: "bridge=\(bridgeCounts) jxa=\(jxaCounts)"
            )
        } catch {
            return GateCheck(name: "task_counts_parity_\(scenario.name)", ok: false, detail: error.localizedDescription)
        }
    }
}

private func listTaskParityChecks(bridge: OmniFocusBridgeService, jxa: OmniAutomationService) async -> [GateCheck] {
    let projectID = await gateSimpleActiveProjectID(using: bridge)
    let scenarios = gateListTaskParityScenarios(projectID: projectID)
    let fields = ["id", "name", "completed", "available", "completionDate"]

    return await scenarios.asyncMap { scenario in
        do {
            let bridgePage = try await retryAsync(operation: "bridge list-tasks parity \(scenario.name)") {
                try await bridge.listTasks(filter: scenario.filter, page: PageRequest(limit: 50), fields: fields)
            }
            let jxaPage = try await retryAsync(operation: "jxa list-tasks parity \(scenario.name)") {
                try await jxa.listTasks(filter: scenario.filter, page: PageRequest(limit: 50), fields: fields)
            }
            let bridgeIDs = bridgePage.items.map(\.id)
            let jxaIDs = jxaPage.items.map(\.id)
            let ok = bridgePage.totalCount == jxaPage.totalCount
                && bridgePage.returnedCount == jxaPage.returnedCount
                && bridgePage.nextCursor == jxaPage.nextCursor
                && bridgeIDs == jxaIDs
            return GateCheck(
                name: "list_tasks_parity_\(scenario.name)",
                ok: ok,
                detail: "bridge.total=\(bridgePage.totalCount.map(String.init) ?? "nil") jxa.total=\(jxaPage.totalCount.map(String.init) ?? "nil") bridge.returned=\(bridgePage.returnedCount) jxa.returned=\(jxaPage.returnedCount) bridge.next=\(bridgePage.nextCursor ?? "nil") jxa.next=\(jxaPage.nextCursor ?? "nil")"
            )
        } catch {
            return GateCheck(name: "list_tasks_parity_\(scenario.name)", ok: false, detail: error.localizedDescription)
        }
    }
}

private func gateSimpleActiveProjectID(using bridge: OmniFocusBridgeService) async -> String? {
    do {
        let page = try await retryAsync(operation: "bridge list-projects active gate seed") {
            try await bridge.listProjects(
                page: PageRequest(limit: 10),
                statusFilter: "active",
                includeTaskCounts: false,
                reviewDueBefore: nil,
                reviewDueAfter: nil,
                reviewPerspective: false,
                completed: nil,
                completedBefore: nil,
                completedAfter: nil,
                fields: ["id", "name"]
            )
        }
        return page.items.first?.id
    } catch {
        return nil
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
            return GateCheck(name: "project_counts_active_contract_bridge", ok: false, detail: "list_tasks returned nil totalCount")
        }
        return GateCheck(
            name: "project_counts_active_contract_bridge",
            ok: counts.actions == total,
            detail: "counts.actions=\(counts.actions) list.totalCount=\(total)"
        )
    } catch {
        return GateCheck(name: "project_counts_active_contract_bridge", ok: false, detail: error.localizedDescription)
    }
}

private func projectCountParityChecks(bridge: OmniFocusBridgeService, jxa: OmniAutomationService) async -> [GateCheck] {
    let scenarios = gateProjectCountParityScenarios()

    return await scenarios.asyncMap { scenario in
        do {
            let bridgeCounts = try await retryAsync(operation: "bridge project-counts parity \(scenario.name)") {
                try await bridge.getProjectCounts(filter: scenario.filter)
            }
            let jxaCounts = try await retryAsync(operation: "jxa project-counts parity \(scenario.name)") {
                try await jxa.getProjectCounts(filter: scenario.filter)
            }
            let ok = bridgeCounts.projects == jxaCounts.projects && bridgeCounts.actions == jxaCounts.actions
            return GateCheck(
                name: "project_counts_parity_\(scenario.name)",
                ok: ok,
                detail: "bridge=\(bridgeCounts) jxa=\(jxaCounts)"
            )
        } catch {
            return GateCheck(name: "project_counts_parity_\(scenario.name)", ok: false, detail: error.localizedDescription)
        }
    }
}

private func retryAsync<T>(operation: String, maxAttempts: Int = 2, delaySeconds: TimeInterval = 1.0, _ body: @escaping () async throws -> T) async throws -> T {
    var attempt = 0
    var lastError: Error?
    while attempt < maxAttempts {
        attempt += 1
        do {
            return try await body()
        } catch {
            lastError = error
            let lower = error.localizedDescription.lowercased()
            let retryable = lower.contains("timed out") || lower.contains("timeout")
            if !retryable || attempt >= maxAttempts {
                throw AutomationError.executionFailed("\(operation) failed on attempt \(attempt)/\(maxAttempts): \(error.localizedDescription)")
            }
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
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
