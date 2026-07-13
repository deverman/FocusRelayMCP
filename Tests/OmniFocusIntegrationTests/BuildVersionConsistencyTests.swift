import Foundation
import Testing
import FocusRelayVersion

@Test
func binaryAndPluginVersionSourcesStayAligned() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let manifestURL = repositoryRoot
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/manifest.json")
    let libraryURL = repositoryRoot
        .appendingPathComponent("Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js")

    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try #require(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
    let manifestVersion = try #require(manifest["version"] as? String)
    let librarySource = try String(contentsOf: libraryURL, encoding: .utf8)
    let numericCore = FocusRelayBuildVersion.current
        .split(separator: "+", maxSplits: 1)[0]
        .split(separator: "-", maxSplits: 1)[0]

    #expect(manifestVersion == numericCore)
    #expect(librarySource.contains("const FOCUSRELAY_VERSION = \"\(FocusRelayBuildVersion.current)\";"))
}
