import FocusRelayDevCore
import Testing

@Test func documentationOnlyChangesStayLightweight() {
    let result = ChangeClassifier.classify(["README.md", "docs/setup.md"])
    #expect(result.impact == .docs)
    #expect(ValidationPlanner.steps(for: result.impact).map(\.name) == ["Check whitespace", "Check Markdown links"])
}

@Test func highestRiskChangedFileWins() {
    let result = ChangeClassifier.classify(["README.md", "Sources/OmniFocusAutomation/BridgeClient.swift"])
    #expect(result.impact == .transportReliability)
}

@Test func serverWireRunsTestsAndReleaseBuild() {
    let steps = ValidationPlanner.steps(for: .serverWire)
    #expect(steps.map(\.name) == ["Run Swift tests", "Build release binary"])
}

@Test func queryAddsSemanticGate() {
    let steps = ValidationPlanner.steps(for: .query)
    #expect(steps.last?.arguments.contains("benchmark-gate-check") == true)
}
