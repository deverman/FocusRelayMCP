import Foundation

public struct FocusRelayPluginTarget: Equatable, Sendable {
    public let location: String
    public let directory: URL
    public let destination: URL
    public let alreadyCurrent: Bool

    public init(location: String, directory: URL, destination: URL, alreadyCurrent: Bool) {
        self.location = location
        self.directory = directory
        self.destination = destination
        self.alreadyCurrent = alreadyCurrent
    }
}

public struct FocusRelayUnavailablePluginTarget: Equatable, Sendable {
    public let location: String
    public let directory: URL

    public init(location: String, directory: URL) {
        self.location = location
        self.directory = directory
    }
}

public struct FocusRelayPluginSetupPlan: Equatable, Sendable {
    public let source: URL
    public let pluginVersion: String
    public let binaryVersion: String
    public let detectedOmniFocusPath: String
    public let targets: [FocusRelayPluginTarget]
    public let unavailableExpectedTargets: [FocusRelayUnavailablePluginTarget]

    public init(
        source: URL,
        pluginVersion: String,
        binaryVersion: String,
        detectedOmniFocusPath: String,
        targets: [FocusRelayPluginTarget],
        unavailableExpectedTargets: [FocusRelayUnavailablePluginTarget]
    ) {
        self.source = source
        self.pluginVersion = pluginVersion
        self.binaryVersion = binaryVersion
        self.detectedOmniFocusPath = detectedOmniFocusPath
        self.targets = targets
        self.unavailableExpectedTargets = unavailableExpectedTargets
    }
}

public enum FocusRelayPluginInstallDisposition: String, Equatable, Sendable {
    case preview
    case installed
    case alreadyCurrent
}

public struct FocusRelayPluginInstallResult: Equatable, Sendable {
    public let location: String
    public let destination: URL
    public let disposition: FocusRelayPluginInstallDisposition

    public init(location: String, destination: URL, disposition: FocusRelayPluginInstallDisposition) {
        self.location = location
        self.destination = destination
        self.disposition = disposition
    }
}

public enum FocusRelayPluginSetupError: LocalizedError {
    case pluginSourceNotFound([String])
    case pluginVersionUnreadable(String)
    case pluginVersionMismatch(plugin: String, binary: String)
    case omniFocusNotDetected
    case noPluginTargets
    case unavailableExpectedTargets([FocusRelayUnavailablePluginTarget])
    case installationFailed(location: String, path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .pluginSourceNotFound(paths):
            return "FocusRelayBridge.omnijs was not found. Checked: \(paths.joined(separator: ", ")). Reinstall FocusRelay or pass --plugin-source."
        case let .pluginVersionUnreadable(path):
            return "Could not read the FocusRelay version from \(path). Reinstall FocusRelay before running setup."
        case let .pluginVersionMismatch(plugin, binary):
            return "Bundled plug-in version \(plugin) does not match the FocusRelay binary \(binary). Reinstall or upgrade FocusRelay before copying the plug-in."
        case .omniFocusNotDetected:
            return "OmniFocus 4 was not detected. Install and open OmniFocus once, then rerun `focusrelay setup`."
        case .noPluginTargets:
            return "No supported OmniFocus plug-in directory could be selected. Open OmniFocus once, then rerun `focusrelay setup`."
        case let .unavailableExpectedTargets(targets):
            let detail = targets.map { "\($0.location): \($0.directory.path)" }.joined(separator: ", ")
            return "Expected OmniFocus plug-in directories are unavailable (\(detail)). Open OmniFocus so those folders are materialized, then rerun setup; no plug-in copies were changed."
        case let .installationFailed(location, path, reason):
            return "Failed to install the \(location) plug-in copy at \(path): \(reason). The previous copy was preserved when possible."
        }
    }
}

/// Shared plug-in setup implementation used by the installed CLI and the
/// repository's thin development install script.
public struct FocusRelayPluginInstaller {
    private let fileManager: FileManager
    private let homeDirectory: URL
    private let omniFocusApplicationURL: URL?
    private let customPluginDirectories: [URL]
    private let binaryVersion: String

    public init(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        omniFocusApplicationURL: URL?,
        customPluginDirectories: [URL] = FocusRelayPluginInstaller.configuredCustomPluginDirectories(),
        binaryVersion: String
    ) {
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
        self.omniFocusApplicationURL = omniFocusApplicationURL
        self.customPluginDirectories = customPluginDirectories
        self.binaryVersion = binaryVersion
    }

    public static func configuredCustomPluginDirectories() -> [URL] {
        let domain = UserDefaults.standard.persistentDomain(forName: "com.omnigroup.OmniFocus4")
        let paths = domain?["PlugInFolders"] as? [String] ?? []
        return paths
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }
    }

    public func makePlan(pluginSourceOverride: URL?, executableURL: URL) throws -> FocusRelayPluginSetupPlan {
        let source = try locatePluginSource(override: pluginSourceOverride, executableURL: executableURL)
        let bridgeLibrary = source.appendingPathComponent("Resources/BridgeLibrary.js")
        guard let bridgeSource = try? String(contentsOf: bridgeLibrary, encoding: .utf8),
              let pluginVersion = focusRelayPluginVersion(inBridgeLibrarySource: bridgeSource) else {
            throw FocusRelayPluginSetupError.pluginVersionUnreadable(bridgeLibrary.path)
        }
        guard pluginVersion == binaryVersion else {
            throw FocusRelayPluginSetupError.pluginVersionMismatch(plugin: pluginVersion, binary: binaryVersion)
        }

        let sandboxContainer = homeDirectory.appendingPathComponent(
            "Library/Containers/com.omnigroup.OmniFocus4/Data",
            isDirectory: true
        )
        let hasSandboxContainer = isDirectory(sandboxContainer)
        guard omniFocusApplicationURL != nil || hasSandboxContainer else {
            throw FocusRelayPluginSetupError.omniFocusNotDetected
        }

        var targets: [FocusRelayPluginTarget] = []
        var unavailable: [FocusRelayUnavailablePluginTarget] = []
        var seen = Set<String>()

        func addTarget(location: String, directory: URL, createIfMissing: Bool = false, expected: Bool = false) {
            let normalized = directory.standardizedFileURL
            guard seen.insert(normalized.path).inserted else { return }
            if createIfMissing || isDirectory(normalized) {
                let destination = normalized.appendingPathComponent(focusRelayPluginBundleName, isDirectory: true)
                targets.append(FocusRelayPluginTarget(
                    location: location,
                    directory: normalized,
                    destination: destination,
                    alreadyCurrent: pluginBundlesEqual(source, destination)
                ))
            } else if expected {
                unavailable.append(FocusRelayUnavailablePluginTarget(location: location, directory: normalized))
            }
        }

        for directory in customPluginDirectories {
            addTarget(location: "custom", directory: directory, expected: true)
        }

        let iCloudContainer = homeDirectory.appendingPathComponent(
            "Library/Mobile Documents/iCloud~com~omnigroup~OmniFocus",
            isDirectory: true
        )
        let iCloudPlugins = iCloudContainer.appendingPathComponent("Documents/Plug-Ins", isDirectory: true)
        addTarget(location: "icloud", directory: iCloudPlugins, expected: isDirectory(iCloudContainer))

        let sandboxPlugins = sandboxContainer.appendingPathComponent(
            "Library/Application Support/Plug-Ins",
            isDirectory: true
        )
        addTarget(location: "sandbox", directory: sandboxPlugins, createIfMissing: true)

        let legacyPlugins = homeDirectory.appendingPathComponent(
            "Library/Application Support/OmniFocus/Plug-Ins",
            isDirectory: true
        )
        addTarget(location: "legacy", directory: legacyPlugins)

        guard !targets.isEmpty else {
            throw FocusRelayPluginSetupError.noPluginTargets
        }

        return FocusRelayPluginSetupPlan(
            source: source,
            pluginVersion: pluginVersion,
            binaryVersion: binaryVersion,
            detectedOmniFocusPath: omniFocusApplicationURL?.path ?? sandboxContainer.path,
            targets: targets,
            unavailableExpectedTargets: unavailable
        )
    }

    public func install(_ plan: FocusRelayPluginSetupPlan, dryRun: Bool) throws -> [FocusRelayPluginInstallResult] {
        guard plan.unavailableExpectedTargets.isEmpty else {
            throw FocusRelayPluginSetupError.unavailableExpectedTargets(plan.unavailableExpectedTargets)
        }

        return try plan.targets.map { target in
            if pluginBundlesEqual(plan.source, target.destination) {
                return FocusRelayPluginInstallResult(
                    location: target.location,
                    destination: target.destination,
                    disposition: .alreadyCurrent
                )
            }
            if dryRun {
                return FocusRelayPluginInstallResult(
                    location: target.location,
                    destination: target.destination,
                    disposition: .preview
                )
            }

            do {
                try installSafely(source: plan.source, target: target)
                return FocusRelayPluginInstallResult(
                    location: target.location,
                    destination: target.destination,
                    disposition: .installed
                )
            } catch {
                throw FocusRelayPluginSetupError.installationFailed(
                    location: target.location,
                    path: target.destination.path,
                    reason: error.localizedDescription
                )
            }
        }
    }

    private func locatePluginSource(override: URL?, executableURL: URL) throws -> URL {
        var candidates: [URL] = []
        if let override {
            candidates = [override]
        } else {
            for executable in [executableURL, executableURL.resolvingSymlinksInPath()] {
                let binDirectory = executable.deletingLastPathComponent()
                candidates.append(
                    binDirectory
                        .deletingLastPathComponent()
                        .appendingPathComponent("share/focusrelay/Plugin/FocusRelayBridge.omnijs", isDirectory: true)
                )
                candidates.append(binDirectory.appendingPathComponent("FocusRelayBridge.omnijs", isDirectory: true))
            }
        }

        var seen = Set<String>()
        let unique = candidates.filter { seen.insert($0.standardizedFileURL.path).inserted }
        if let source = unique.first(where: isDirectory) {
            return source.standardizedFileURL
        }
        throw FocusRelayPluginSetupError.pluginSourceNotFound(unique.map(\.path))
    }

    private func installSafely(source: URL, target: FocusRelayPluginTarget) throws {
        try fileManager.createDirectory(at: target.directory, withIntermediateDirectories: true)

        let nonce = UUID().uuidString
        let staging = target.directory.appendingPathComponent(".\(focusRelayPluginBundleName).install-\(nonce)", isDirectory: true)
        let backup = target.directory.appendingPathComponent(".\(focusRelayPluginBundleName).backup-\(nonce)", isDirectory: true)
        var movedPreviousCopy = false

        defer {
            try? fileManager.removeItem(at: staging)
        }

        try fileManager.copyItem(at: source, to: staging)
        guard pluginBundlesEqual(source, staging) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        do {
            if fileManager.fileExists(atPath: target.destination.path) {
                try fileManager.moveItem(at: target.destination, to: backup)
                movedPreviousCopy = true
            }
            try fileManager.moveItem(at: staging, to: target.destination)
            if movedPreviousCopy {
                try? fileManager.removeItem(at: backup)
            }
        } catch {
            if movedPreviousCopy {
                try? fileManager.removeItem(at: target.destination)
                try? fileManager.moveItem(at: backup, to: target.destination)
            }
            throw error
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func pluginBundlesEqual(_ lhs: URL, _ rhs: URL) -> Bool {
        guard isDirectory(lhs), isDirectory(rhs),
              let lhsFiles = try? regularFiles(in: lhs),
              let rhsFiles = try? regularFiles(in: rhs),
              lhsFiles.keys == rhsFiles.keys else {
            return false
        }
        return lhsFiles.allSatisfy { relativePath, data in
            rhsFiles[relativePath] == data
        }
    }

    private func regularFiles(in root: URL) throws -> [String: Data] {
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        guard let enumerator = fileManager.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else {
            throw CocoaError(.fileReadUnknown)
        }

        var files: [String: Data] = [:]
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let prefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
            let canonicalFileURL = fileURL.resolvingSymlinksInPath().standardizedFileURL
            guard canonicalFileURL.path.hasPrefix(prefix) else { continue }
            let relativePath = String(canonicalFileURL.path.dropFirst(prefix.count))
            files[relativePath] = try Data(contentsOf: fileURL)
        }
        return files
    }
}
