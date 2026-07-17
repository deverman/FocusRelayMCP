import Foundation
import JavaScriptCore
import Testing

/// Regression coverage for #98: completed=false uses remaining/parent-chain semantics.
@Test
func completedFalseUsesRemainingSemanticsNotJustNotCompleted() throws {
    let statusModule = try loadStatusModule()
    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }

    let script = """
    const Task = { Status: {
      Available: "Available", Next: "Next", DueSoon: "DueSoon", Overdue: "Overdue",
      Blocked: "Blocked", Completed: "Completed", Dropped: "Dropped"
    }};
    const Project = { Status: {
      Active: "Active", OnHold: "OnHold", Dropped: "Dropped", Done: "Done"
    }};
    function safe(fn) { try { return fn(); } catch (_) { return null; } }
    \(statusModule)
    function task(status, parent) {
      return { taskStatus: status, parent: parent || null };
    }
    const completedParent = task(Task.Status.Completed);
    const droppedParent = task(Task.Status.Dropped);
    const samples = {
      available: task(Task.Status.Available),
      blocked: task(Task.Status.Blocked),
      completed: task(Task.Status.Completed),
      dropped: task(Task.Status.Dropped),
      childOfCompleted: task(Task.Status.Available, completedParent),
      childOfDropped: task(Task.Status.Available, droppedParent)
    };
    function evaluate(completedFilter, everythingView) {
      const out = {};
      Object.keys(samples).forEach(key => {
        out[key] = matchesCompletedFilter(samples[key], completedFilter, everythingView);
      });
      return out;
    }
    JSON.stringify({
      completedFalse: evaluate(false, false),
      completedOmitted: evaluate(undefined, false),
      everything: evaluate(undefined, true),
      completedTrue: evaluate(true, false)
    });
    """

    guard let json = context.evaluateScript(script)?.toString(), exceptionMessage == nil else {
        Issue.record("JS evaluation failed: \(exceptionMessage ?? "no result")")
        return
    }

    struct Sample: Decodable {
        let available: Bool
        let blocked: Bool
        let completed: Bool
        let dropped: Bool
        let childOfCompleted: Bool
        let childOfDropped: Bool
    }
    struct Result: Decodable {
        let completedFalse: Sample
        let completedOmitted: Sample
        let everything: Sample
        let completedTrue: Sample
    }
    let decoded = try JSONDecoder().decode(Result.self, from: Data(json.utf8))

    // completed=false must match remaining (exclude dropped + children under completed/dropped parents)
    #expect(decoded.completedFalse.available)
    #expect(decoded.completedFalse.blocked)
    #expect(!decoded.completedFalse.completed)
    #expect(!decoded.completedFalse.dropped)
    #expect(!decoded.completedFalse.childOfCompleted)
    #expect(!decoded.completedFalse.childOfDropped)

    // omitted completed with non-everything view matches remaining
    #expect(decoded.completedOmitted.available)
    #expect(!decoded.completedOmitted.dropped)
    #expect(!decoded.completedOmitted.childOfCompleted)

    // everything includes completed/dropped and hidden children
    #expect(decoded.everything.available)
    #expect(decoded.everything.completed)
    #expect(decoded.everything.dropped)
    #expect(decoded.everything.childOfCompleted)

    // completed=true is completed-only
    #expect(!decoded.completedTrue.available)
    #expect(decoded.completedTrue.completed)
    #expect(!decoded.completedTrue.dropped)
}

private func loadStatusModule() throws -> String {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let librarySource = try String(contentsOf: sourceURL, encoding: .utf8)
    let startMarker = "// STATUS MODULE - Single Source of Truth for OmniFocus Status"
    let endMarker = "// END STATUS MODULE"
    guard let start = librarySource.range(of: startMarker),
          let end = librarySource.range(of: endMarker, range: start.upperBound..<librarySource.endIndex) else {
        throw CompletedFilterTestError.missingStatusModule
    }
    return String(librarySource[start.lowerBound..<end.upperBound])
}

private enum CompletedFilterTestError: Error {
    case missingStatusModule
}
