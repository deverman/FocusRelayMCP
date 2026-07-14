# FocusRelay - MCP (Model Context Protocal) Server and CLI for OmniFocus Mac

## Plan your day and keep OmniFocus up to date with AI

FocusRelay is a fast, native Swift MCP server and CLI that helps AI assistants
read and safely update OmniFocus using documented OmniFocus APIs.

[Install with Homebrew](#install-with-homebrew) ·
[See what it can do](#ask-review-update) ·
[Star FocusRelay](https://github.com/deverman/FocusRelayMCP) ·
[Contribute](#help-shape-focusrelay)

![Demo: Ask an AI assistant about your OmniFocus tasks](imgs/omnifocusaiquery.gif)

Ask about the work already in OmniFocus, review the answer, and make approved
changes without clicking through long task lists.

## Ask. Review. Update.

FocusRelay is designed for targeted questions and compact answers, so the
assistant does not need your entire OmniFocus database for routine requests.

Try prompts like:

- “How many flagged items do I have?”
- “Show me the first three available tasks in my inbox.”
- “Find my task called [task name], flag it, and verify the change.”
- “Set [task name] due tomorrow at 5 PM in my local timezone and verify the
  change.”

These workflows were tested against the released Homebrew build with Kimi K2.7
Code, and the inbox query with a second MCP-capable model. Updates target stable
OmniFocus IDs and can verify the saved result. If names are duplicated, ask to
see the candidates before changing anything.

FocusRelay 0.10.0-beta can:

- find and count tasks using dates, flags, tags, projects, availability, inbox
  state, completion, estimates, and text search;
- review projects, folders, tags, task counts, and stalled work;
- update names, notes, flags, dates, estimates, tags, project settings, and
  review intervals;
- complete, reactivate, change status, and move existing tasks and projects;
- preview a proposed change and verify the saved result.

The current beta updates existing tasks and projects. Creating or deleting
items is not part of this release; creation is tracked in
[#82](https://github.com/deverman/FocusRelayMCP/issues/82) and
[#83](https://github.com/deverman/FocusRelayMCP/issues/83).

## Why FocusRelay?

### Keep the assistant focused

FocusRelay exposes 14 model-facing tools—seven for reading and seven for making
supported changes. Internal diagnostics stay in the CLI, count commands avoid
returning long item lists, and field selection keeps responses compact.

### Native Swift speed at real-library scale

FocusRelay is compiled as native Swift and installed with Homebrew, with no
Node.js or Python runtime in the request path. Single-pass filtering and
early-stop pagination keep focused inbox reads near one second in testing at
thousands-of-tasks scale. The same core powers a CLI for precise, low-context
queries.

### Run where OmniFocus understands its data

The Swift server dispatches work to a lightweight bridge plug-in that runs
inside OmniFocus’s Omni Automation context. It uses documented APIs and native
statuses, keeping results aligned with OmniFocus without reading its private
database.

### Make changes you can check

Update tools target stable IDs and support previews, per-item results, compact
return fields, and optional verification. A failed save, update, or verification
is reported as a failure—not success.

Validation covered thousands of tasks and thousands of measured calls without
errors or timeouts in the final benchmark runs. See the
[0.10.0-beta release notes](docs/release-notes-v0.10.0-beta.md) for evidence and
limits.

## Install with Homebrew

Requirements:

- macOS on Apple silicon;
- OmniFocus 4;
- Homebrew;
- an MCP-compatible assistant or a shell-capable AI agent.

### 1. Install and trust the formula

Homebrew 6 requires explicit trust for formulae from non-official taps. Trust
only the FocusRelay formula, then install it:

```bash
brew tap deverman/focus-relay
brew trust --formula deverman/focus-relay/focusrelay
brew install focusrelay
```

Formula-specific trust authorizes FocusRelay without trusting every current or
future formula in the tap. See Homebrew’s
[Tap Trust documentation](https://docs.brew.sh/Tap-Trust) for details.

### 2. Install the OmniFocus plugin

```bash
mkdir -p "$HOME/Library/Containers/com.omnigroup.OmniFocus4/Data/Library/Application Support/Plug-Ins"
cp -R "$(brew --prefix focusrelay)/share/focusrelay/Plugin/FocusRelayBridge.omnijs" \
  "$HOME/Library/Containers/com.omnigroup.OmniFocus4/Data/Library/Application Support/Plug-Ins/"
```

The plugin and binary must stay on the same version. Repeat this copy step after
upgrading FocusRelay.

### 3. Restart OmniFocus

Quit OmniFocus completely and reopen it so the updated plugin is loaded:

```bash
osascript -e 'tell application "OmniFocus" to quit'
sleep 2
open -a "OmniFocus"
```

### 4. Add FocusRelay to your AI assistant

Configure a local stdio MCP server with:

- command: `/opt/homebrew/bin/focusrelay`
- arguments: `serve`

<details>
<summary>OpenCode configuration example</summary>

```json
{
  "mcp": {
    "focusrelay": {
      "type": "local",
      "command": ["/opt/homebrew/bin/focusrelay", "serve"],
      "enabled": true
    }
  }
}
```

</details>

On the first query, OmniFocus asks whether to allow the automation. Choose
**Run Script**. If the prompt is hidden, bring OmniFocus to the front.

### 5. Check the connection

```bash
focusrelay --version
focusrelay bridge-health-check
focusrelay list-tasks --fields id,name --limit 1
```

Then ask:

> How many flagged items do I have in OmniFocus?

<details>
<summary>Manual download or source build</summary>

Download the latest binary and `FocusRelayBridge.omnijs` from
[GitHub Releases](https://github.com/deverman/FocusRelayMCP/releases), or build
with the Swift 6.3.3 toolchain selected by the checked-in `.swift-version`:

```bash
git clone https://github.com/deverman/FocusRelayMCP.git
cd FocusRelayMCP
swift build -c release
./scripts/install-plugin.sh
```

After installing the plugin, restart OmniFocus completely.

</details>

## MCP when you want conversation. CLI when you want precision.

MCP lets compatible assistants discover FocusRelay and choose the right action.
The CLI is useful for scripts, debugging, and agents that already have shell
access.

```bash
# Count without returning every matching task
focusrelay task-counts --flagged true

# Return only three task names
focusrelay list-tasks \
  --inbox-only true \
  --available-only true \
  --limit 3 \
  --fields name

# Preview a change without touching OmniFocus
focusrelay update-tasks <task-id> \
  --flagged true \
  --preview-only \
  --return-fields id,name,flagged
```

Run `focusrelay --help` for the command list. For write examples and safety
rules, see [Safe Update Workflows for CLI and MCP](docs/mutation-workflows.md).

## How FocusRelay is different

FocusRelay combines a native Swift server with a bridge plug-in that executes
inside OmniFocus. Swift keeps MCP fast and compact; the bridge gets fresh data
and applies changes through documented OmniFocus APIs.

✅ Available · 🟡 Coming next · 🟠 Backlog · ◇ Project roadmap · — Not currently documented

| Capability | **FocusRelay** | [OmniFocus-MCP](https://github.com/themotionmachine/OmniFocus-MCP) | [Enhanced](https://github.com/jqlts1/omnifocus-mcp-enhanced) | [OmnifocusMCP](https://github.com/vitalyrodnenko/OmnifocusMCP) | [Operator](https://github.com/HelloThisIsFlo/omnifocus-operator) |
| --- | --- | --- | --- | --- | --- |
| Runtime | **Native Swift · Homebrew** | TypeScript · npx | TypeScript · npx | Native Rust · Homebrew; Python and TypeScript available | Python · uvx |
| OmniFocus access | **Bridge plug-in inside Omni Automation; documented APIs** | JXA and Omni Automation through `osascript` | Omni Automation through `osascript` | Omni Automation through `osascript` | Internal SQLite read cache; OmniJS fallback |
| Public MCP tools | **14 → 11 after [#91](https://github.com/deverman/FocusRelayMCP/issues/91), [#82](https://github.com/deverman/FocusRelayMCP/issues/82), and [#83](https://github.com/deverman/FocusRelayMCP/issues/83)** | 12 | 18 | 45 | 11 |
| Find, filter, and count tasks | ✅ | ✅ | ✅ | ✅ | ✅ |
| Update existing tasks | ✅ | ✅ | ✅ | ✅ | ✅ |
| Update existing projects | ✅ | ✅ | ✅ | ✅ | ◇ v1.5 roadmap |
| Preview and post-save verification | ✅ Every write tool; per-target results | — | — | — | — |
| Drop projects without deleting them | ✅ | ✅ | — | ✅ | — |
| Create tasks and subtasks | 🟡 [#82](https://github.com/deverman/FocusRelayMCP/issues/82) | ✅ | ✅ | ✅ | ✅ |
| Create projects | 🟡 [#83, including inbox-task conversion](https://github.com/deverman/FocusRelayMCP/issues/83) | ✅ | ✅ | ✅ | ◇ v1.5 roadmap |
| Planned-date updates | 🟠 [#16](https://github.com/deverman/FocusRelayMCP/issues/16) | ✅ | ✅ | ✅ | — |
| Repeating tasks | 🟠 [#93](https://github.com/deverman/FocusRelayMCP/issues/93) | ✅ | — | ✅ | ✅ |
| Custom perspective contents | 🟠 [#10](https://github.com/deverman/FocusRelayMCP/issues/10) | ✅ | ✅ | — | — |
| Permanently delete tasks and projects | — | ✅ | ✅ | ✅ | — |

This comparison reflects each project’s public documentation on July 15, 2026;
“Not documented” is not a claim that a feature is impossible. The other public
READMEs do not describe an equivalent per-target preview and post-save
verification contract.

Preview resolves IDs and validates the change without saving it. Verification
runs after OmniFocus saves, reads the affected values back, and reports a
mismatch as a failure. These are MCP tool arguments, so Codex, Claude Code,
OpenCode, and other standard stdio MCP clients can use them; whether a model
chooses them without being asked depends on the model and client. For important
changes, ask it to “preview first, then apply with verification.”

## Help shape FocusRelay

See [GitHub Issues](https://github.com/deverman/FocusRelayMCP/issues) for planned
work. If FocusRelay earns a place in your workflow,
[star the repository](https://github.com/deverman/FocusRelayMCP) so more
OmniFocus users can find it.

Want to help? Pick an issue, propose a use case, or open a focused pull request.
See [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

## Troubleshooting

### The bridge times out

1. Bring OmniFocus to the front and accept the first **Run Script** prompt.
2. Confirm FocusRelay Bridge is enabled under **Automation → Configure
   Plug-ins…**.
3. Recopy the plugin, quit OmniFocus completely, and reopen it.
4. Run `focusrelay bridge-health-check`.

### Results look stale after an upgrade

The plugin JavaScript is cached by OmniFocus. Reinstall the plugin and restart
OmniFocus completely. Project and tag catalogs cache for five minutes; task
queries are always fresh.

### A time-based result looks wrong after travel

Restart the MCP client and OmniFocus so FocusRelay picks up the current macOS
timezone.

## Development

```bash
swift build
swift test
```

FocusRelay uses Swift Testing from the Swift toolchain. Production query changes
must follow the documented
[Omni Automation contract](docs/omni-automation-contract.md).

## License

FocusRelay is available under the [MIT License](LICENSE).
