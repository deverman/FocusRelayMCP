import Foundation
import Testing
@testable import OmniFocusAutomation

@Suite("Plug-in version extraction")
struct PluginVersionExtractionTests {
    @Test func readsTheRuntimeVersionConstant() {
        let source = """
        (function() {
          const FOCUSRELAY_VERSION = "0.12.0-beta";
          return FOCUSRELAY_VERSION;
        })();
        """
        #expect(focusRelayPluginVersion(inBridgeLibrarySource: source) == "0.12.0-beta")
    }

    @Test func toleratesSpacingVariants() {
        #expect(focusRelayPluginVersion(inBridgeLibrarySource: #"const FOCUSRELAY_VERSION="1.2.3";"#) == "1.2.3")
        #expect(focusRelayPluginVersion(inBridgeLibrarySource: #"var FOCUSRELAY_VERSION   =   "1.2.3" ;"#) == "1.2.3")
    }

    @Test func returnsNilWhenAbsent() {
        #expect(focusRelayPluginVersion(inBridgeLibrarySource: "const OTHER = \"1.0.0\";") == nil)
        #expect(focusRelayPluginVersion(inBridgeLibrarySource: "") == nil)
    }
}

@Suite("Plug-in consistency warning")
struct PluginConsistencyWarningTests {
    private func bundle(_ location: String, _ version: String?) -> InstalledPluginBundle {
        InstalledPluginBundle(location: location, path: "/tmp/\(location)/FocusRelayBridge.omnijs", version: version)
    }

    @Test func silentWhenEverythingAgrees() {
        let warning = pluginConsistencyWarning(
            loadedVersion: "0.12.0-beta",
            binaryVersion: "0.12.0-beta",
            bundles: [bundle("icloud", "0.12.0-beta"), bundle("sandbox", "0.12.0-beta")]
        )
        #expect(warning == nil)
    }

    @Test func flagsTheStaleCopyScenarioFromIssue200() {
        // The real failure: the sandbox copy was updated, OmniFocus kept
        // loading the iCloud copy, and every version check looked fine.
        let warning = pluginConsistencyWarning(
            loadedVersion: "0.12.0-beta",
            binaryVersion: "0.0.0-dev",
            bundles: [bundle("icloud", "0.12.0-beta"), bundle("sandbox", "0.0.0-dev")]
        )
        let text = try! #require(warning)
        #expect(text.contains("sandbox"))
        #expect(text.contains("0.0.0-dev"))
        #expect(text.contains("iCloud"), "must explain why updating only the sandbox copy has no effect")
        #expect(!text.contains("icloud (0.12.0-beta)"), "the copy matching the loaded plug-in is not stale")
    }

    @Test func flagsBinaryMismatchEvenWhenBundlesAgree() {
        let warning = pluginConsistencyWarning(
            loadedVersion: "0.11.0-beta",
            binaryVersion: "0.12.0-beta",
            bundles: [bundle("icloud", "0.11.0-beta")]
        )
        let text = try! #require(warning)
        #expect(text.contains("0.11.0-beta") && text.contains("0.12.0-beta"))
        #expect(text.contains("Reinstall"))
    }

    @Test func flagsMissingBundles() {
        let warning = pluginConsistencyWarning(
            loadedVersion: "0.12.0-beta",
            binaryVersion: "0.12.0-beta",
            bundles: []
        )
        #expect(try! #require(warning).contains("no plug-in bundle was found"))
    }

    @Test func flagsUnreadableBundle() {
        let warning = pluginConsistencyWarning(
            loadedVersion: "0.12.0-beta",
            binaryVersion: "0.12.0-beta",
            bundles: [bundle("sandbox", nil)]
        )
        #expect(try! #require(warning).contains("unreadable"))
    }

    @Test func silentWhenBridgeReportedNoVersion() {
        // A failed bridge already reports its own error; do not pile on.
        #expect(pluginConsistencyWarning(loadedVersion: nil, binaryVersion: "0.12.0-beta", bundles: []) == nil)
    }
}

@Suite("Plug-in bundle discovery")
struct PluginBundleDiscoveryTests {
    @Test func searchOrderPutsICloudFirst() {
        let home = URL(fileURLWithPath: "/tmp/fakehome")
        let locations = focusRelayPluginSearchPaths(home: home).map(\.location)
        #expect(locations == ["icloud", "sandbox", "legacy"],
                "iCloud must be listed first: OmniFocus prefers it when plug-in sync is enabled")
    }

    @Test func findsBundlesAndReadsVersionsFromDisk() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("focusrelay-plugin-scan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }

        for (location, dir) in focusRelayPluginSearchPaths(home: home) where location != "legacy" {
            let resources = dir
                .appendingPathComponent(focusRelayPluginBundleName, isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let version = location == "icloud" ? "0.12.0-beta" : "0.0.0-dev"
            try #"const FOCUSRELAY_VERSION = "\#(version)";"#
                .write(to: resources.appendingPathComponent("BridgeLibrary.js"), atomically: true, encoding: .utf8)
        }

        let bundles = installedFocusRelayPluginBundles(home: home)
        #expect(bundles.count == 2, "legacy directory was not created and must not be reported")
        #expect(bundles.first?.location == "icloud")
        #expect(bundles.first?.version == "0.12.0-beta")
        #expect(bundles.last?.version == "0.0.0-dev")
    }
}
