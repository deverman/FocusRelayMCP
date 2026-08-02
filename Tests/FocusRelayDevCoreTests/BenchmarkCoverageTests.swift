import Foundation
import Testing
@testable import FocusRelayDevCore

@Suite("Benchmark coverage detection")
struct BenchmarkCoverageTests {
    @Test func changedToolWithoutABenchmarkIsFlagged() {
        // The #88 case: list_projects has no benchmark in the suite.
        let assessment = BenchmarkCoverage.assess(changedFiles: [
            "Sources/FocusRelayServer/FocusRelayServer.swift",
            "Sources/OmniFocusCore/OmniFocusCore.swift",
            "Sources/FocusRelayCLI/ListProjectsCommand.swift"
        ])
        #expect(assessment.touchedTools.contains("list_projects"))
        #expect(assessment.uncovered.contains("list_projects"))
        #expect(assessment.hasCoverageGap)
    }

    @Test func coveredToolDoesNotTripTheGate() {
        let assessment = BenchmarkCoverage.assess(changedFiles: [
            "Sources/OmniFocusCore/TaskIDSelection.swift"
        ])
        #expect(assessment.touchedTools.contains("list_tasks"))
        #expect(assessment.covered.contains("list_tasks"))
        #expect(!assessment.hasCoverageGap)
    }

    @Test func batchResolutionTouchesBothListTools() {
        // #171 changed list_projects and list_tags; neither is benchmarked.
        let assessment = BenchmarkCoverage.assess(changedFiles: [
            "Sources/OmniFocusCore/BatchNameResolution.swift"
        ])
        #expect(Set(assessment.touchedTools).isSuperset(of: ["list_projects", "list_tags"]))
        #expect(assessment.hasCoverageGap)
    }

    @Test func docsOnlyChangeTouchesNoTools() {
        let assessment = BenchmarkCoverage.assess(changedFiles: ["README.md", "docs/roadmap-execution-plan.md"])
        #expect(assessment.touchedTools.isEmpty)
        #expect(!assessment.hasCoverageGap)
    }

    @Test func gapMessageNamesTheToolAndExplainsWhyGreenIsNotEnough() {
        let assessment = BenchmarkCoverage.assess(changedFiles: ["Sources/FocusRelayCLI/ListProjectsCommand.swift"])
        let message = BenchmarkCoverage.coverageGapMessage(assessment)
        #expect(message.contains("list_projects"))
        #expect(message.contains("does not clear this change"))
        #expect(message.contains("interleaved A/B"))
    }

    @Test func everyBenchmarkedToolIsAPublicTool() {
        #expect(BenchmarkCoverage.publicTools.isSuperset(of: BenchmarkCoverage.benchmarkedTools))
    }

    @Test func mostPublicToolsAreStillUnbenchmarked() {
        // Records the current state honestly: 3 of 9 covered.
        #expect(BenchmarkCoverage.benchmarkedTools.count == 3)
        #expect(BenchmarkCoverage.publicTools.count == 9)
    }
}
