import Foundation
import JavaScriptCore
import Testing
@testable import OmniFocusAutomation
import OmniFocusCore

@Test
func pluginEffectiveFlagModuleUsesNativeStateAndIdentifiesProjectRoots() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let librarySource = try String(contentsOf: sourceURL, encoding: .utf8)
    let module = try extractEffectiveFlagModule(from: librarySource)

    let result = try evaluateEffectiveFlagScript(
        """
        function safe(fn) { try { return fn(); } catch (_) { return null; } }
        \(module)
        const project = { id: { primaryKey: "project" } };
        JSON.stringify({
          direct: isTaskEffectivelyFlagged({ flagged: true, effectiveFlagged: true }),
          inherited: isTaskEffectivelyFlagged({ flagged: false, effectiveFlagged: true }),
          unflagged: isTaskEffectivelyFlagged({ flagged: false, effectiveFlagged: false }),
          root: isProjectRootTask({ id: { primaryKey: "project" }, containingProject: project }),
          action: isProjectRootTask({ id: { primaryKey: "action" }, containingProject: project }),
          inbox: isProjectRootTask({ id: { primaryKey: "inbox" }, containingProject: null })
        });
        """
    )

    let decoded = try JSONDecoder().decode(EffectiveFlagModuleResult.self, from: Data(result.utf8))
    #expect(decoded.direct)
    #expect(decoded.inherited)
    #expect(!decoded.unflagged)
    #expect(decoded.root)
    #expect(!decoded.action)
    #expect(!decoded.inbox)
}

private func extractEffectiveFlagModule(from source: String) throws -> String {
    let startMarker = "// EFFECTIVE FLAG MODULE - Native Flagged perspective semantics"
    let endMarker = "// END EFFECTIVE FLAG MODULE"
    guard let start = source.range(of: startMarker),
          let end = source.range(of: endMarker, range: start.upperBound..<source.endIndex) else {
        throw EffectiveFlagTestError.missingModule
    }
    return String(source[start.lowerBound..<end.upperBound])
}

private func evaluateEffectiveFlagScript(_ script: String) throws -> String {
    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }
    let result = context.evaluateScript(script)?.toString()
    guard let result, exceptionMessage == nil else {
        throw EffectiveFlagTestError.javaScript(exceptionMessage ?? "No result")
    }
    return result
}

private struct EffectiveFlagModuleResult: Decodable {
    let direct: Bool
    let inherited: Bool
    let unflagged: Bool
    let root: Bool
    let action: Bool
    let inbox: Bool
}

private enum EffectiveFlagTestError: Error {
    case missingModule
    case javaScript(String)
}
