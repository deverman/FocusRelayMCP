import Foundation

/// One installed copy of the bridge plug-in bundle, as found on disk.
public struct InstalledPluginBundle: Codable, Sendable, Equatable {
    /// Short label for the directory family: `icloud`, `sandbox`, or `legacy`.
    public let location: String
    public let path: String
    /// Version read from the bundle's `BridgeLibrary.js`; nil when unreadable.
    public let version: String?
}

let focusRelayPluginBundleName = "FocusRelayBridge.omnijs"

/// Extracts the version constant the plug-in reports at runtime. Reading the
/// same constant the bridge returns keeps this comparison honest — the
/// manifest carries only the numeric core (`0.12.0`) while the bridge reports
/// the full tag (`0.12.0-beta`), so comparing manifests would produce
/// spurious mismatches.
func focusRelayPluginVersion(inBridgeLibrarySource source: String) -> String? {
    guard let range = source.range(of: #"FOCUSRELAY_VERSION\s*=\s*"[^"]*""#, options: .regularExpression) else {
        return nil
    }
    let match = source[range]
    guard let open = match.range(of: "\"") else { return nil }
    let rest = match[open.upperBound...]
    guard let close = rest.range(of: "\"") else { return nil }
    return String(rest[..<close.lowerBound])
}

/// Plug-in directories OmniFocus can load from, in the order OmniFocus
/// prefers them. iCloud wins when plug-in sync is enabled, which is why a
/// current copy in the sandbox container is not sufficient on its own.
func focusRelayPluginSearchPaths(home: URL) -> [(location: String, url: URL)] {
    [
        (
            "icloud",
            home.appendingPathComponent(
                "Library/Mobile Documents/iCloud~com~omnigroup~OmniFocus/Documents/Plug-Ins",
                isDirectory: true
            )
        ),
        (
            "sandbox",
            home.appendingPathComponent(
                "Library/Containers/com.omnigroup.OmniFocus4/Data/Library/Application Support/Plug-Ins",
                isDirectory: true
            )
        ),
        (
            "legacy",
            home.appendingPathComponent("Library/Application Support/OmniFocus/Plug-Ins", isDirectory: true)
        )
    ]
}

func installedFocusRelayPluginBundles(
    fileManager: FileManager = .default,
    home: URL = FileManager.default.homeDirectoryForCurrentUser
) -> [InstalledPluginBundle] {
    focusRelayPluginSearchPaths(home: home).compactMap { entry in
        let bundle = entry.url.appendingPathComponent(focusRelayPluginBundleName, isDirectory: true)
        guard fileManager.fileExists(atPath: bundle.path) else { return nil }
        let library = bundle.appendingPathComponent("Resources/BridgeLibrary.js")
        let version = (try? String(contentsOf: library, encoding: .utf8)).flatMap(focusRelayPluginVersion(inBridgeLibrarySource:))
        return InstalledPluginBundle(location: entry.location, path: bundle.path, version: version)
    }
}

/// Explains a plug-in version disagreement, or nil when everything lines up.
///
/// The version alone cannot distinguish "correct plug-in" from "stale plug-in
/// in a directory you did not update", which is exactly the failure this
/// exists to surface: OmniFocus can keep running a bundle from another
/// directory across reinstalls and restarts, with no other visible signal.
func pluginConsistencyWarning(
    loadedVersion: String?,
    binaryVersion: String,
    bundles: [InstalledPluginBundle]
) -> String? {
    guard let loadedVersion else { return nil }

    if bundles.isEmpty {
        return "OmniFocus is running plug-in \(loadedVersion), but no plug-in bundle was found in any known directory. "
            + "Reinstall the plug-in so upgrades can reach it."
    }

    let stale = bundles.filter { $0.version != loadedVersion }
    var problems: [String] = []

    if !stale.isEmpty {
        let detail = stale
            .map { "\($0.location) (\($0.version ?? "unreadable"))" }
            .joined(separator: ", ")
        problems.append(
            "OmniFocus is running plug-in \(loadedVersion), but these installed copies differ: \(detail). "
                + "OmniFocus prefers the iCloud copy when plug-in sync is enabled, so updating only the sandbox copy has no effect."
        )
    }

    if loadedVersion != binaryVersion {
        problems.append(
            "The loaded plug-in (\(loadedVersion)) does not match the FocusRelay binary (\(binaryVersion)). "
                + "Reinstall the plug-in and restart OmniFocus completely."
        )
    }

    return problems.isEmpty ? nil : problems.joined(separator: " ")
}
