import Foundation

/// Turns two sets of latency samples into a stated conclusion and a merge
/// recommendation.
///
/// The rule this encodes: a percentage change means nothing without knowing the
/// noise it sits in. On the host that produced #88's evidence, whole-suite
/// run-to-run variance reached 3-4x, so a 13% difference can be real (it was,
/// at ~5 standard errors) while a 0.4% failure-rate difference is chance
/// (it was, at well under 1).
public enum BenchmarkVerdict {
    /// Minimum relative change worth reporting as a direction. Below this a
    /// result is called indistinguishable even when statistically clean,
    /// because it is not user-relevant.
    public static let minimumRelativeChange = 0.05
    /// Minimum separation in standard errors before a direction is claimed.
    public static let minimumStandardErrors = 3.0
    /// Minimum samples per arm; below this the comparison is inconclusive.
    public static let minimumSamplesPerArm = 5
    /// Above this coefficient of variation the host is too noisy to conclude.
    public static let maximumCoefficientOfVariation = 0.35

    public enum Outcome: String, Codable, Sendable {
        case improvement = "IMPROVEMENT"
        case regression = "REGRESSION"
        case indistinguishable = "INDISTINGUISHABLE"
        /// Too few samples, or a host too noisy to separate the arms.
        case inconclusive = "INCONCLUSIVE"
        /// The arms did not return equivalent results, so their timings are
        /// not comparable. #171 was in exactly this state before a field bug
        /// was found: the fast arm was fast because it returned nothing.
        case notComparable = "NOT COMPARABLE"
    }

    public struct ArmStatistics: Codable, Equatable, Sendable {
        public let name: String
        public let samples: Int
        public let median: Double
        public let stdev: Double
        public let standardError: Double

        public init(name: String, samplesMilliseconds: [Double]) {
            self.name = name
            self.samples = samplesMilliseconds.count
            let sorted = samplesMilliseconds.sorted()
            self.median = sorted.isEmpty ? 0 : (sorted.count % 2 == 1
                ? sorted[sorted.count / 2]
                : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2)
            if samplesMilliseconds.count > 1 {
                let mean = samplesMilliseconds.reduce(0, +) / Double(samplesMilliseconds.count)
                let variance = samplesMilliseconds.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
                    / Double(samplesMilliseconds.count - 1)
                self.stdev = variance.squareRoot()
                self.standardError = self.stdev / Double(samplesMilliseconds.count).squareRoot()
            } else {
                self.stdev = 0
                self.standardError = 0
            }
        }
    }

    public struct Result: Codable, Equatable, Sendable {
        public let outcome: Outcome
        public let baseline: ArmStatistics
        public let candidate: ArmStatistics
        public let relativeChange: Double
        public let standardErrors: Double
        public let recommendation: String
    }

    /// `resultsEquivalent` must be established by the caller before timings
    /// mean anything — two arms returning different data are not a comparison.
    public static func evaluate(
        baseline: ArmStatistics,
        candidate: ArmStatistics,
        resultsEquivalent: Bool
    ) -> Result {
        let relative = baseline.median == 0 ? 0 : (candidate.median - baseline.median) / baseline.median
        let combinedError = (baseline.standardError * baseline.standardError
            + candidate.standardError * candidate.standardError).squareRoot()
        let separation = combinedError == 0 ? 0 : abs(candidate.median - baseline.median) / combinedError

        let outcome: Outcome
        if !resultsEquivalent {
            outcome = .notComparable
        } else if baseline.samples < minimumSamplesPerArm || candidate.samples < minimumSamplesPerArm {
            outcome = .inconclusive
        } else if tooNoisy(baseline) || tooNoisy(candidate) {
            outcome = .inconclusive
        } else if relative <= -minimumRelativeChange && separation >= minimumStandardErrors {
            outcome = .improvement
        } else if relative >= minimumRelativeChange && separation >= minimumStandardErrors {
            outcome = .regression
        } else {
            outcome = .indistinguishable
        }

        return Result(
            outcome: outcome,
            baseline: baseline,
            candidate: candidate,
            relativeChange: relative,
            standardErrors: separation,
            recommendation: recommendation(for: outcome, relative: relative)
        )
    }

    private static func tooNoisy(_ arm: ArmStatistics) -> Bool {
        guard arm.median > 0 else { return true }
        return arm.stdev / arm.median > maximumCoefficientOfVariation
    }

    private static func recommendation(for outcome: Outcome, relative: Double) -> String {
        switch outcome {
        case .improvement:
            return "safe to merge — measured improvement on the changed path"
        case .regression:
            let percent = String(format: "%.1f", relative * 100)
            return "do not merge on performance grounds — measured regression of \(percent)% on the changed path"
        case .indistinguishable:
            return "safe to merge — no regression detected on the changed path"
        case .inconclusive:
            return "re-run on a quiescent host — the samples cannot separate the arms"
        case .notComparable:
            return "fix the arms before concluding — they did not return equivalent results, so the timings mean nothing"
        }
    }

    /// Human-readable block for a PR comment or suite output.
    public static func render(_ result: Result) -> String {
        let pct = String(format: "%+.1f", result.relativeChange * 100)
        let se = String(format: "%.1f", result.standardErrors)
        return """
        VERDICT: \(result.outcome.rawValue) (median \(pct)%, \(se) SE, \
        n=\(result.baseline.samples)/\(result.candidate.samples) per arm)
        RECOMMENDATION: \(result.recommendation)
        """
    }
}
