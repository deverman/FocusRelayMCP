import Foundation

public enum ValidationImpact: String, Codable, CaseIterable, Comparable, Sendable {
    case docs
    case package
    case serverWire = "server-wire"
    case mutation
    case query
    case performance
    case transportReliability = "transport-reliability"

    private var rank: Int {
        switch self {
        case .docs: 0
        case .package: 1
        case .serverWire: 2
        case .mutation: 3
        case .query: 4
        case .performance: 5
        case .transportReliability: 6
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public struct ChangeClassification: Codable, Equatable, Sendable {
    public let impact: ValidationImpact
    public let files: [String]
    public let reasons: [String]

    public init(impact: ValidationImpact, files: [String], reasons: [String]) {
        self.impact = impact
        self.files = files
        self.reasons = reasons
    }
}

public enum ChangeClassifier {
    public static func classify(_ files: [String]) -> ChangeClassification {
        let normalized = files.filter { !$0.isEmpty }.sorted()
        var selected = ValidationImpact.docs
        var reasons = Set<String>()

        for path in normalized {
            let lower = path.lowercased()
            let result: (ValidationImpact, String)
            if lower.hasSuffix(".md") || lower == "agents.md" {
                result = (.docs, "documentation")
            } else if lower.contains("benchmark") {
                result = (.performance, "benchmark or performance tooling")
            } else if lower.contains("bridgeclient") || lower.contains("timeout") || lower.contains("transport") {
                result = (.transportReliability, "transport or reliability path")
            } else if lower.contains("mutation") || lower.contains("updatetask") || lower.contains("updateproject") {
                result = (.mutation, "write path")
            } else if lower.contains("focusrelayserver") {
                result = (.serverWire, "MCP server or wire contract")
            } else if lower.contains("omnifocusautomation") || lower.contains("focusrelaybridge.omnijs") {
                result = (.query, "OmniFocus production query path")
            } else if lower == "package.swift" || lower == "package.resolved" || lower.contains("release") || lower.contains("homebrew") || lower.hasPrefix(".github/workflows/") {
                result = (.package, "package or release machinery")
            } else if lower.hasPrefix("tests/") {
                result = (.serverWire, "executable test code")
            } else {
                result = (.package, "unclassified executable or configuration file")
            }
            selected = max(selected, result.0)
            reasons.insert(result.1)
        }

        return ChangeClassification(impact: selected, files: normalized, reasons: reasons.sorted())
    }
}

public struct ValidationStep: Codable, Equatable, Sendable {
    public let name: String
    public let executable: String
    public let arguments: [String]

    public init(_ name: String, _ executable: String, _ arguments: [String]) {
        self.name = name
        self.executable = executable
        self.arguments = arguments
    }
}

public enum ValidationPlanner {
    public static func steps(for impact: ValidationImpact, disableNestedSwiftSandbox: Bool = false) -> [ValidationStep] {
        if impact == .docs {
            return [
                ValidationStep("Check whitespace", "git", ["diff", "--check"]),
                ValidationStep("Check Markdown links", "focusrelay-dev", ["check-markdown-links"])
            ]
        }

        let sandboxArguments = disableNestedSwiftSandbox ? ["--disable-sandbox"] : []
        var steps = [ValidationStep("Run Swift tests", "swift", ["test"] + sandboxArguments)]
        if impact == .package || impact == .serverWire || impact == .mutation {
            steps.append(ValidationStep("Build release binary", "swift", ["build"] + sandboxArguments + ["-c", "release", "--product", "focusrelay"]))
        }
        if impact >= .query {
            steps.append(ValidationStep("Run semantic gates", "swift", ["run"] + sandboxArguments + ["focusrelay", "benchmark-gate-check", "--tool", "all"]))
        }
        return steps
    }
}
