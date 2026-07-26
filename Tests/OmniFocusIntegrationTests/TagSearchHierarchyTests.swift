import Foundation
import JavaScriptCore
@testable import OmniFocusAutomation
import OmniFocusCore
import Testing

@Test
func tagNameSearchIsCaseInsensitiveAndHierarchyDistinguishesDuplicates() throws {
    let module = try tagQueryHelperModule()
    let context = JSContext()!
    var exceptionMessage: String?
    context.exceptionHandler = { _, exception in
        exceptionMessage = exception?.toString()
    }

    let script = """
    function safe(fn) { try { return fn(); } catch (_) { return null; } }
    \(module)
    function tag(id, name, parent, exclusive) {
      return {
        id: { primaryKey: id },
        name: name,
        parent: parent || null,
        childrenAreMutuallyExclusive: exclusive === true
      };
    }
    const people = tag("people", "People", null, false);
    const material = tag("material", "Material", null, true);
    const peopleContact = tag("people-contact", "Contact", people, false);
    const peopleContactDuplicate = tag("people-contact-2", "Contact", people, false);
    const materialContact = tag("material-contact", "CONTACT", material, false);
    const nested = tag("nested", "Preferred Contact", peopleContact, false);
    const tags = [
      people,
      peopleContact,
      peopleContactDuplicate,
      material,
      materialContact,
      nested
    ];
    const query = normalizedTagNameSearch("  contact ");
    const matches = tags.filter(tag => tagMatchesNameSearch(tag, query));
    JSON.stringify(matches.map(tag => ({
      id: tag.id.primaryKey,
      hierarchy: tagHierarchyPayload(tag)
    })));
    """

    let json = try #require(context.evaluateScript(script)?.toString())
    #expect(exceptionMessage == nil)

    struct Match: Decodable {
        struct Hierarchy: Decodable {
            let parentID: String?
            let parentName: String?
            let path: [TagPathElement]
        }
        let id: String
        let hierarchy: Hierarchy
    }

    let matches = try JSONDecoder().decode([Match].self, from: Data(json.utf8))
    #expect(matches.map(\.id) == [
        "people-contact",
        "people-contact-2",
        "material-contact",
        "nested"
    ])
    #expect(matches[0].hierarchy.parentID == "people")
    #expect(matches[0].hierarchy.parentName == "People")
    #expect(matches[0].hierarchy.path.map(\.name) == ["People", "Contact"])
    #expect(matches[1].hierarchy.path.map(\.name) == ["People", "Contact"])
    #expect(matches[2].hierarchy.path.map(\.name) == ["Material", "CONTACT"])
    #expect(matches[3].hierarchy.path.map(\.name) == ["People", "Contact", "Preferred Contact"])
}

@Test
func tagSearchNormalizationRejectsWhitespaceOnlyInput() throws {
    #expect(try OmniFocusBridgeService.normalizeTagSearch("  Contact \n") == "Contact")
    #expect(try OmniFocusBridgeService.normalizeTagSearch(nil) == nil)
    #expect(throws: AutomationError.self) {
        try OmniFocusBridgeService.normalizeTagSearch(" \t\n ")
    }
}

private func tagQueryHelperModule() throws -> String {
    let sourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")
    let source = try String(contentsOf: sourceURL, encoding: .utf8)
    let startMarker = "// TAG QUERY MODULE - list_tags search and hierarchy"
    let endMarker = "// END TAG QUERY MODULE"
    let start = try #require(source.range(of: startMarker))
    let end = try #require(
        source.range(of: endMarker, range: start.upperBound..<source.endIndex)
    )
    return String(source[start.lowerBound..<end.upperBound])
}
