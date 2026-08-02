import Foundation

/// Which public tools a change touches, and whether the benchmark suite can
/// actually measure them.
///
/// #88 changed `list_projects` and was gated on a smoke suite that benchmarks
/// `list_tasks`, `get_task_counts`, and `get_project_counts` — so four suites
/// ran without measuring a line of the changed path. This makes that gap loud
/// instead of invisible.
public enum BenchmarkCoverage {
    /// Tools the benchmark suite can measure today.
    public static let benchmarkedTools: Set<String> = [
        "list_tasks",
        "get_task_counts",
        "get_project_counts"
    ]

    /// Every public model-facing tool.
    public static let publicTools: Set<String> = [
        "list_tasks", "get_task", "list_projects", "list_tags", "list_folders",
        "edit_tasks", "edit_projects", "get_task_counts", "get_project_counts"
    ]

    /// Source markers that imply a tool's request path may have changed.
    /// Deliberately broad: a false "you should benchmark this" costs a
    /// conversation, a false "nothing to see here" costs what #88 cost.
    private static let toolMarkers: [String: [String]] = [
        "list_tasks": ["listtasks", "list_tasks", "taskfilter", "taskidselection"],
        "get_task": ["gettask", "get_task"],
        "list_projects": ["listprojects", "list_projects", "projectfilter", "batchnameresolution"],
        "list_tags": ["listtags", "list_tags", "tagfilter", "batchnameresolution"],
        "list_folders": ["listfolders", "list_folders", "folderitem"],
        "edit_tasks": ["edittasks", "edit_tasks"],
        "edit_projects": ["editprojects", "edit_projects"],
        "get_task_counts": ["taskcounts", "get_task_counts"],
        "get_project_counts": ["projectcounts", "get_project_counts"]
    ]

    /// Paths broad enough that any public tool could be affected.
    private static let wideMarkers = ["bridgeclient", "bridgelibrary.js", "focusrelayserver"]

    public struct Assessment: Codable, Equatable, Sendable {
        public let touchedTools: [String]
        public let covered: [String]
        public let uncovered: [String]
        /// True when a changed tool has no benchmark, so the suite cannot
        /// clear it however green it runs.
        public var hasCoverageGap: Bool { !uncovered.isEmpty }
    }

    public static func assess(changedFiles: [String]) -> Assessment {
        var touched = Set<String>()
        for path in changedFiles {
            let lower = path.lowercased()
            if wideMarkers.contains(where: lower.contains) {
                // A shared path can affect anything; report only the tools
                // that also have their own marker, so the message stays
                // actionable rather than listing all nine every time.
                continue
            }
            for (tool, markers) in toolMarkers where markers.contains(where: lower.contains) {
                touched.insert(tool)
            }
        }
        // Second pass: shared paths still count once specific tools are known.
        if touched.isEmpty {
            for path in changedFiles {
                let lower = path.lowercased()
                for (tool, markers) in toolMarkers where markers.contains(where: lower.contains) {
                    touched.insert(tool)
                }
            }
        }

        let sorted = touched.sorted()
        return Assessment(
            touchedTools: sorted,
            covered: sorted.filter { benchmarkedTools.contains($0) },
            uncovered: sorted.filter { !benchmarkedTools.contains($0) }
        )
    }

    /// Message shown when a changed tool cannot be measured by the suite.
    public static func coverageGapMessage(_ assessment: Assessment) -> String {
        let missing = assessment.uncovered.joined(separator: ", ")
        return """
        Benchmark coverage gap: \(missing) has no benchmark in the suite.
        A passing benchmark run does not clear this change, because the suite \
        never exercises the path it modifies. Measure the changed tool directly \
        with an interleaved A/B against the baseline ref before drawing a \
        performance conclusion.
        """
    }
}
