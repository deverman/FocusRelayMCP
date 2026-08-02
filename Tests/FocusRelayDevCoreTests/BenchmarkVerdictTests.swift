import Foundation
import Testing
@testable import FocusRelayDevCore

private func arm(_ name: String, _ samples: [Double]) -> BenchmarkVerdict.ArmStatistics {
    BenchmarkVerdict.ArmStatistics(name: name, samplesMilliseconds: samples)
}

@Suite("Benchmark verdict criteria")
struct BenchmarkVerdictTests {
    @Test func clearImprovementIsReported() {
        // #171 as measured: 10 scalar searches vs one batch call.
        let result = BenchmarkVerdict.evaluate(
            baseline: arm("scalar", [2402, 2380, 2415, 2398, 2440, 2371]),
            candidate: arm("batch", [432, 428, 435, 430, 433, 429]),
            resultsEquivalent: true
        )
        #expect(result.outcome == .improvement)
        #expect(result.recommendation.contains("safe to merge"))
    }

    @Test func clearRegressionIsReported() {
        let result = BenchmarkVerdict.evaluate(
            baseline: arm("before", [400, 402, 398, 401, 399, 403]),
            candidate: arm("after", [600, 604, 598, 602, 601, 599]),
            resultsEquivalent: true
        )
        #expect(result.outcome == .regression)
        #expect(result.recommendation.contains("do not merge"))
    }

    @Test func noiseLevelDifferenceIsNotAWin() {
        // #88's unchanged path: 385ms vs 390ms with ~25ms stdev. Reporting
        // this as an improvement is exactly the mistake to avoid.
        let result = BenchmarkVerdict.evaluate(
            baseline: arm("master", [390, 412, 371, 398, 405, 380]),
            candidate: arm("branch", [385, 402, 366, 410, 379, 395]),
            resultsEquivalent: true
        )
        #expect(result.outcome == .indistinguishable)
        #expect(result.recommendation.contains("no regression detected"))
    }

    @Test func statisticallyCleanButTinyChangeIsNotADirection() {
        // 2% with almost no variance: real, but not user-relevant.
        let result = BenchmarkVerdict.evaluate(
            baseline: arm("before", [1000, 1001, 999, 1000, 1002, 998]),
            candidate: arm("after", [1020, 1021, 1019, 1020, 1022, 1018]),
            resultsEquivalent: true
        )
        #expect(result.outcome == .indistinguishable,
                "below the relevance floor, however clean the statistics")
    }

    @Test func largeChangeWithoutSeparationIsIndistinguishable() {
        // Big medians apart, but the arms overlap heavily.
        let result = BenchmarkVerdict.evaluate(
            baseline: arm("before", [100, 180, 90, 200, 110, 170]),
            candidate: arm("after", [130, 190, 95, 210, 120, 175]),
            resultsEquivalent: true
        )
        #expect(result.outcome == .inconclusive || result.outcome == .indistinguishable)
    }

    @Test func tooFewSamplesIsInconclusive() {
        let result = BenchmarkVerdict.evaluate(
            baseline: arm("before", [400, 402]),
            candidate: arm("after", [200, 201]),
            resultsEquivalent: true
        )
        #expect(result.outcome == .inconclusive)
        #expect(result.recommendation.contains("quiescent host"))
    }

    @Test func noisyHostIsInconclusiveRatherThanAVerdict() {
        // The 3-4x swings seen while validating #88.
        let result = BenchmarkVerdict.evaluate(
            baseline: arm("before", [2692, 9259, 11838, 3100, 10400, 2800]),
            candidate: arm("after", [2600, 9100, 11700, 3000, 10200, 2750]),
            resultsEquivalent: true
        )
        #expect(result.outcome == .inconclusive,
                "a host this noisy cannot support any conclusion")
    }

    @Test func nonEquivalentArmsAreNotComparable() {
        // #171 before the field bug was found: the fast arm was fast because
        // it returned nothing at all.
        let result = BenchmarkVerdict.evaluate(
            baseline: arm("scalar", [2400, 2380, 2410, 2390, 2405, 2395]),
            candidate: arm("batch", [30, 31, 29, 30, 32, 28]),
            resultsEquivalent: false
        )
        #expect(result.outcome == .notComparable)
        #expect(result.recommendation.contains("did not return equivalent results"))
    }

    @Test func renderStatesOutcomeAndRecommendation() {
        let result = BenchmarkVerdict.evaluate(
            baseline: arm("scalar", [2402, 2380, 2415, 2398, 2440, 2371]),
            candidate: arm("batch", [432, 428, 435, 430, 433, 429]),
            resultsEquivalent: true
        )
        let text = BenchmarkVerdict.render(result)
        #expect(text.contains("VERDICT: IMPROVEMENT"))
        #expect(text.contains("RECOMMENDATION:"))
        #expect(text.contains("SE"))
        #expect(text.contains("n=6/6"))
    }

    @Test func standardErrorShrinksWithMoreSamples() {
        let few = arm("few", [100, 110, 90, 105, 95])
        let many = arm("many", Array(repeating: [100, 110, 90, 105, 95], count: 4).flatMap { $0 })
        #expect(many.standardError < few.standardError)
    }
}

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
