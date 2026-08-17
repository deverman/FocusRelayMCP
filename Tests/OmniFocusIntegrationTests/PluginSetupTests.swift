import Foundation
import Testing
@testable import OmniFocusAutomation

@Suite("Guided plug-in setup")
struct PluginSetupTests {
    @Test func findsTheHomebrewBundledPluginAndEverySupportedDestination() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let prefix = fixture.root.appendingPathComponent("prefix", isDirectory: true)
        let source = prefix.appendingPathComponent(
            "share/focusrelay/Plugin/FocusRelayBridge.omnijs",
            isDirectory: true
        )
        try fixture.writePlugin(at: source, marker: "source")

        let custom = fixture.root.appendingPathComponent("Custom Plug-Ins", isDirectory: true)
        let iCloud = fixture.home.appendingPathComponent(
            "Library/Mobile Documents/iCloud~com~omnigroup~OmniFocus/Documents/Plug-Ins",
            isDirectory: true
        )
        let legacy = fixture.home.appendingPathComponent(
            "Library/Application Support/OmniFocus/Plug-Ins",
            isDirectory: true
        )
        for directory in [custom, iCloud, legacy] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let installer = fixture.installer(customPluginDirectories: [custom])
        let plan = try installer.makePlan(
            pluginSourceOverride: nil,
            executableURL: prefix.appendingPathComponent("bin/focusrelay")
        )

        #expect(plan.source == source.standardizedFileURL)
        #expect(plan.pluginVersion == fixture.version)
        #expect(plan.targets.map(\.location) == ["custom", "icloud", "sandbox", "legacy"])
        #expect(plan.unavailableExpectedTargets.isEmpty)
    }

    @Test func findsTheRepositoryPluginWhenRunThroughSwiftPM() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent(
            "Plugin/FocusRelayBridge.omnijs",
            isDirectory: true
        )
        try fixture.writePlugin(at: source, marker: "development")
        try "// fixture".write(
            to: fixture.root.appendingPathComponent("Package.swift"),
            atomically: true,
            encoding: .utf8
        )

        let plan = try fixture.installer().makePlan(
            pluginSourceOverride: nil,
            executableURL: fixture.root.appendingPathComponent(".build/out/Products/Debug/focusrelay")
        )

        #expect(plan.source == source.standardizedFileURL)
    }

    @Test func rejectsABundledPluginThatDoesNotMatchTheBinary() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: source, version: "9.9.9", marker: "mismatch")

        do {
            _ = try fixture.installer().makePlan(
                pluginSourceOverride: source,
                executableURL: fixture.root.appendingPathComponent("focusrelay")
            )
            Issue.record("Expected a plug-in/binary version mismatch")
        } catch let error as FocusRelayPluginSetupError {
            guard case let .pluginVersionMismatch(plugin, binary) = error else {
                Issue.record("Expected pluginVersionMismatch, got \(error)")
                return
            }
            #expect(plugin == "9.9.9")
            #expect(binary == fixture.version)
        }
    }

    @Test func dryRunReportsWorkWithoutCreatingADestination() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: source, marker: "dry-run")
        let installer = fixture.installer()
        let plan = try installer.makePlan(
            pluginSourceOverride: source,
            executableURL: fixture.root.appendingPathComponent("focusrelay")
        )

        let results = try installer.install(plan, dryRun: true)

        #expect(results.map(\.disposition) == [.preview])
        #expect(!FileManager.default.fileExists(atPath: try #require(plan.targets.first).destination.path))
    }

    @Test func reinstallReportsAlreadyCurrentInsteadOfRecopying() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: source, marker: "current")
        let installer = fixture.installer()
        let firstPlan = try installer.makePlan(
            pluginSourceOverride: source,
            executableURL: fixture.root.appendingPathComponent("focusrelay")
        )

        #expect(try installer.install(firstPlan, dryRun: false).map(\.disposition) == [.installed])

        let secondPlan = try installer.makePlan(
            pluginSourceOverride: source,
            executableURL: fixture.root.appendingPathComponent("focusrelay")
        )
        #expect(secondPlan.targets.first?.alreadyCurrent == true)
        #expect(try installer.install(secondPlan, dryRun: false).map(\.disposition) == [.alreadyCurrent])
    }

    @Test func equivalentPluginThroughASymlinkIsAlreadyCurrent() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let realSource = fixture.root.appendingPathComponent("real/FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: realSource, marker: "current")
        let linkedParent = fixture.root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(
            at: linkedParent,
            withDestinationURL: fixture.root.appendingPathComponent("real", isDirectory: true)
        )
        let linkedSource = linkedParent.appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)

        let destination = fixture.sandboxPluginDirectory
            .appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: destination, marker: "current")

        let plan = try fixture.installer().makePlan(
            pluginSourceOverride: linkedSource,
            executableURL: fixture.root.appendingPathComponent("focusrelay")
        )

        #expect(plan.targets.first?.alreadyCurrent == true)
    }

    @Test func privateTmpAliasDoesNotTriggerAFalseUpdate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let privateRoot = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("focusrelay-setup-alias-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: privateRoot) }
        let privateSource = privateRoot.appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: privateSource, marker: "current")
        let publicSource = URL(
            fileURLWithPath: privateSource.path.replacingOccurrences(of: "/private/tmp/", with: "/tmp/"),
            isDirectory: true
        )

        let destination = fixture.sandboxPluginDirectory
            .appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: destination, marker: "current")

        let plan = try fixture.installer().makePlan(
            pluginSourceOverride: publicSource,
            executableURL: fixture.root.appendingPathComponent("focusrelay")
        )

        #expect(plan.targets.first?.alreadyCurrent == true)
    }

    @Test func copyFailurePreservesThePreviousPlugin() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: source, marker: "new")

        let destination = fixture.sandboxPluginDirectory
            .appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: destination, marker: "old")

        let installer = fixture.installer()
        let plan = try installer.makePlan(
            pluginSourceOverride: source,
            executableURL: fixture.root.appendingPathComponent("focusrelay")
        )
        try FileManager.default.removeItem(at: source)

        #expect(throws: (any Error).self) {
            _ = try installer.install(plan, dryRun: false)
        }
        #expect(try fixture.marker(in: destination) == "old")
    }

    @Test func unavailableICloudTargetFailsBeforeChangingSandbox() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: source, marker: "new")

        let iCloudContainer = fixture.home.appendingPathComponent(
            "Library/Mobile Documents/iCloud~com~omnigroup~OmniFocus",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: iCloudContainer, withIntermediateDirectories: true)

        let destination = fixture.sandboxPluginDirectory
            .appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true)
        try fixture.writePlugin(at: destination, marker: "old")

        let installer = fixture.installer()
        let plan = try installer.makePlan(
            pluginSourceOverride: source,
            executableURL: fixture.root.appendingPathComponent("focusrelay")
        )
        #expect(plan.unavailableExpectedTargets.map(\.location) == ["icloud"])

        #expect(throws: FocusRelayPluginSetupError.self) {
            _ = try installer.install(plan, dryRun: false)
        }
        #expect(try fixture.marker(in: destination) == "old")
    }

    private final class Fixture {
        let version = "1.2.3-test"
        let root: URL
        let home: URL
        let application: URL

        var sandboxPluginDirectory: URL {
            home.appendingPathComponent(
                "Library/Containers/com.omnigroup.OmniFocus4/Data/Library/Application Support/Plug-Ins",
                isDirectory: true
            )
        }

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("focusrelay-setup-\(UUID().uuidString)", isDirectory: true)
            home = root.appendingPathComponent("home", isDirectory: true)
            application = root.appendingPathComponent("Applications/OmniFocus.app", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        func installer(customPluginDirectories: [URL] = []) -> FocusRelayPluginInstaller {
            FocusRelayPluginInstaller(
                homeDirectory: home,
                omniFocusApplicationURL: application,
                customPluginDirectories: customPluginDirectories,
                binaryVersion: version
            )
        }

        func writePlugin(at bundle: URL, version: String? = nil, marker: String) throws {
            let resources = bundle.appendingPathComponent("Resources", isDirectory: true)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try #"const FOCUSRELAY_VERSION = "\#(version ?? self.version)";"#
                .write(to: resources.appendingPathComponent("BridgeLibrary.js"), atomically: true, encoding: .utf8)
            try marker.write(
                to: bundle.appendingPathComponent("marker.txt"),
                atomically: true,
                encoding: .utf8
            )
        }

        func marker(in bundle: URL) throws -> String {
            try String(contentsOf: bundle.appendingPathComponent("marker.txt"), encoding: .utf8)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
