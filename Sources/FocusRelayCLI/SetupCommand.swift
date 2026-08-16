import AppKit
import ArgumentParser
import Foundation
import FocusRelayVersion
import OmniFocusAutomation

enum SetupClient: String, CaseIterable, ExpressibleByArgument {
    case claudeCode = "claude-code"
    case codex
    case opencode
}

struct SetupReadinessSummary: Equatable {
    let ready: Bool
    let message: String
}

enum SetupCommandSupport {
    static func isAffirmative(_ input: String?) -> Bool {
        guard let input else { return false }
        return ["y", "yes"].contains(input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    static func executablePath(argumentZero: String, environmentPath: String?) -> String {
        if argumentZero.contains("/") {
            return URL(fileURLWithPath: argumentZero).standardizedFileURL.path
        }
        for directory in (environmentPath ?? "").split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(argumentZero)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate.standardizedFileURL.path
            }
        }
        return argumentZero
    }

    static func clientSnippet(_ client: SetupClient, executablePath: String) -> String {
        let quoted = shellQuote(executablePath)
        switch client {
        case .claudeCode:
            return "claude mcp add --scope user focusrelay -- \(quoted) serve"
        case .codex:
            return "codex mcp add focusrelay -- \(quoted) serve"
        case .opencode:
            let object: [String: Any] = [
                "mcp": [
                    "focusrelay": [
                        "type": "local",
                        "command": [executablePath, "serve"],
                        "enabled": true
                    ]
                ]
            ]
            let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            return String(decoding: data, as: UTF8.self)
        }
    }

    static func readinessSummary(_ health: BridgeHealthResult, binaryVersion: String) -> SetupReadinessSummary {
        guard health.ok else {
            return SetupReadinessSummary(
                ready: false,
                message: health.error ?? "The FocusRelay bridge did not report ready."
            )
        }
        if let warning = health.pluginWarning {
            return SetupReadinessSummary(ready: false, message: warning)
        }
        guard health.version == binaryVersion else {
            return SetupReadinessSummary(
                ready: false,
                message: "Loaded plug-in version \(health.version ?? "unknown") does not match binary \(binaryVersion). Restart OmniFocus completely and check again."
            )
        }
        return SetupReadinessSummary(
            ready: true,
            message: "FocusRelay Bridge \(health.version ?? binaryVersion) is ready."
        )
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

struct Setup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Install the OmniFocus bridge plug-in and print MCP client settings."
    )

    @Option(name: .customLong("plugin-source"), help: "Override the bundled FocusRelayBridge.omnijs path.")
    var pluginSource: String?

    @Flag(help: "Preview detected paths and required actions without changing files.")
    var dryRun = false

    @Flag(
        name: [.customLong("yes"), .customLong("non-interactive")],
        help: "Install without an interactive confirmation prompt."
    )
    var assumeYes = false

    @Flag(help: "After installation, wait for your OmniFocus restart and check bridge readiness.")
    var checkReadiness = false

    @Option(help: "Also print configuration for claude-code, codex, or opencode.")
    var client: SetupClient?

    func run() async throws {
        if dryRun && checkReadiness {
            throw ValidationError("--dry-run cannot be combined with --check-readiness")
        }

        let executableURL = Bundle.main.executableURL
            ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
        let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.omnigroup.OmniFocus4"
        )
        let installer = FocusRelayPluginInstaller(
            omniFocusApplicationURL: applicationURL,
            binaryVersion: FocusRelayBuildVersion.current
        )
        let sourceOverride = pluginSource.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
        }
        let plan = try installer.makePlan(pluginSourceOverride: sourceOverride, executableURL: executableURL)
        let executablePath = SetupCommandSupport.executablePath(
            argumentZero: ProcessInfo.processInfo.arguments[0],
            environmentPath: ProcessInfo.processInfo.environment["PATH"]
        )

        printPreview(plan, executablePath: executablePath)

        let needsInstall = plan.targets.contains { !$0.alreadyCurrent }
        if needsInstall && assumeYes && checkReadiness {
            throw ValidationError(
                "An updated plug-in cannot be checked before OmniFocus restarts. Run non-interactive setup, restart OmniFocus, then run `focusrelay setup --non-interactive --check-readiness`."
            )
        }
        if needsInstall && !dryRun && !assumeYes {
            print("\nInstall or update every listed plug-in copy? [y/N] ", terminator: "")
            guard let answer = readLine() else {
                throw ValidationError("Confirmation input is unavailable. Rerun with --non-interactive after reviewing --dry-run output.")
            }
            guard SetupCommandSupport.isAffirmative(answer) else {
                print("Setup cancelled; no files were changed.")
                return
            }
        }

        let results = try installer.install(plan, dryRun: dryRun)
        print("\nPlug-in result:")
        for result in results {
            print("  - \(result.location): \(result.disposition.rawValue) — \(result.destination.path)")
        }

        print("\nMCP settings:")
        print("  command: \(executablePath)")
        print("  arguments: serve")
        if let client {
            print("\n\(client.rawValue) configuration:")
            print(SetupCommandSupport.clientSnippet(client, executablePath: executablePath))
        }

        if dryRun {
            print("\nDry run complete; no files were changed.")
            return
        }

        let installedAny = results.contains { $0.disposition == .installed }
        if installedAny {
            printRestartInstructions()
        } else {
            print("\nEvery detected plug-in copy is already current; no files were changed.")
        }

        if checkReadiness {
            if installedAny {
                print("\nRestart OmniFocus now, approve FocusRelay Bridge if prompted, then press Return to check readiness.")
                _ = readLine()
            }
            do {
                let health = try await OmniFocusBridgeService().healthCheck()
                let summary = SetupCommandSupport.readinessSummary(
                    health,
                    binaryVersion: FocusRelayBuildVersion.current
                )
                print("\nReadiness: \(summary.message)")
                if !summary.ready {
                    throw ExitCode.failure
                }
            } catch let exitCode as ExitCode {
                throw exitCode
            } catch {
                print("\nReadiness failed: \(error.localizedDescription)")
                print("Restart OmniFocus completely, approve the plug-in if prompted, then run `focusrelay setup --check-readiness`.")
                throw ExitCode.failure
            }
        }
    }

    private func printPreview(_ plan: FocusRelayPluginSetupPlan, executablePath: String) {
        print("FocusRelay setup")
        print("  Binary: \(executablePath) (\(plan.binaryVersion))")
        print("  OmniFocus: \(plan.detectedOmniFocusPath)")
        print("  Plug-in source: \(plan.source.path) (\(plan.pluginVersion))")
        print("  Plug-in destinations:")
        for target in plan.targets {
            let action = target.alreadyCurrent ? "already current" : "install or update"
            print("    - \(target.location): \(target.destination.path) [\(action)]")
        }
        for target in plan.unavailableExpectedTargets {
            print("    - \(target.location): \(target.directory.path) [unavailable]")
        }
    }

    private func printRestartInstructions() {
        print("\nRestart required:")
        print("  Quit OmniFocus completely and reopen it so it loads this plug-in version.")
        print("  The first query may ask you to approve FocusRelay Bridge; choose Run Script.")
        print("  Then run: focusrelay setup --check-readiness")
    }
}
