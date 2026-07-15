import Foundation
import FocusRelayDevCore
import Testing

@Test func markdownLinkValidatorUsesParsedLinksAndImages() throws {
    let fixture = try MarkdownFixture()
    try fixture.write("target.md", "# Target")
    try fixture.write("image.png", "bytes")
    try fixture.write("README.md", "[target](target.md#heading) ![image](image.png) `not-a-link(missing.md)`")

    #expect(try MarkdownLinkValidator.validate(root: fixture.root).isEmpty)
}

@Test func markdownLinkValidatorReportsOnlyMissingLocalDestinations() throws {
    let fixture = try MarkdownFixture()
    try fixture.write("README.md", "[missing](docs/missing.md) [web](https://example.com) [anchor](#section)")

    let actual = try MarkdownLinkValidator.validate(root: fixture.root)
    #expect(actual == [
        BrokenMarkdownLink(source: "README.md", destination: "docs/missing.md")
    ], "Unexpected result: \(actual)")
}

private final class MarkdownFixture {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func write(_ path: String, _ contents: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
}
