import Foundation
import JavaScriptCore
import Testing
@testable import OmniFocusAutomation

@Test
func pluginTaskSearchMatchesNameAndNoteCaseInsensitively() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let librarySource = try String(contentsOf: sourceURL, encoding: .utf8)
    let module = try extractTaskSearchModule(from: librarySource)

    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }
    let result = context.evaluateScript(
        """
        function safe(fn) { try { return fn(); } catch (_) { return null; } }
        \(module)
        JSON.stringify({
          normalized: normalizeTaskSearchQuery("  ALpHa  "),
          blank: normalizeTaskSearchQuery("   "),
          nameMatch: taskMatchesSearch({ name: "Alpha task", note: "" }, "alpha"),
          noteMatch: taskMatchesSearch({ name: "Other", note: "Contains ALPHA here" }, "alpha"),
          miss: taskMatchesSearch({ name: "Other", note: "Nothing" }, "alpha")
        });
        """
    )?.toString()

    #expect(exceptionMessage == nil)
    let json = try #require(result)
    let decoded = try JSONDecoder().decode(SearchModuleResult.self, from: Data(json.utf8))
    #expect(decoded.normalized == "alpha")
    #expect(decoded.blank == nil)
    #expect(decoded.nameMatch)
    #expect(decoded.noteMatch)
    #expect(!decoded.miss)
}

private func extractTaskSearchModule(from source: String) throws -> String {
    let startMarker = "// TASK SEARCH MODULE - Shared name/note matching semantics"
    let endMarker = "// END TASK SEARCH MODULE"
    guard let start = source.range(of: startMarker),
          let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
        throw TaskSearchTestError.missingModule
    }
    return String(source[start.lowerBound..<end.upperBound])
}

private struct SearchModuleResult: Decodable {
    let normalized: String
    let blank: String?
    let nameMatch: Bool
    let noteMatch: Bool
    let miss: Bool
}

private enum TaskSearchTestError: Error {
    case missingModule
}
