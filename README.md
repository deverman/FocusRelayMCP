# FocusRelay

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

These read, flag, and due-date workflows were tested against the released
Homebrew build with Kimi K2.7 Code; the inbox query was also verified with a
second MCP-capable model. In the tested update workflows, the assistant resolved
the item first, changed the stable OmniFocus ID, and read the result back before
reporting success.

The write prompts were tested with a unique task name. If more than one task
matches in your library, ask the assistant to show the candidates before
changing anything.

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

### Use one native tool two ways

The same Swift executable provides both the MCP server and a full CLI. Use MCP
from any compatible assistant, or let an agent with shell access call the CLI
and request only the counts or fields it needs. Both routes share the same
models, validation, and OmniFocus behavior.

### Work through documented OmniFocus APIs

Production queries use documented Omni Automation collections and native task
and project statuses. This keeps results aligned with OmniFocus’s own view of
available, completed, dropped, and on-hold work.

### Make changes you can check

Update tools target stable IDs and support previews, per-item results, compact
return fields, and optional verification. A failed save, update, or verification
is reported as a failure—not success.

### Stay fast at real-library scale

FocusRelay uses single-pass filtering, early-stop pagination, and a short-lived
project and tag cache. Focused inbox reads typically return in about one second.
Validation covered databases at the scale of thousands of tasks and thousands
of measured calls without errors or timeouts in the final benchmark runs. See
the [0.10.0-beta release notes](docs/release-notes-v0.10.0-beta.md) for the
current evidence and limits.

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

OmniFocus users have several good MCP options. This snapshot is based on each
project’s public documentation on July 14, 2026.

| Project | Runtime and install | Model-facing tools | Current emphasis |
| --- | --- | ---: | --- |
| **FocusRelay** | Swift · Homebrew | 14 | Focused reads and verified updates through documented OmniFocus APIs, with MCP and CLI in one binary |
| [OmniFocus-MCP](https://github.com/themotionmachine/OmniFocus-MCP) | TypeScript · npx | 12 | Broad creation, editing, deletion, batches, resources, and perspectives |
| [omnifocus-mcp-enhanced](https://github.com/jqlts1/omnifocus-mcp-enhanced) | TypeScript · npx | 18 | Specialized task views, full CRUD, custom perspectives, batches, and attachments |
| [OmnifocusMCP](https://github.com/vitalyrodnenko/OmnifocusMCP) | Rust via Homebrew, plus Python and TypeScript implementations | 45 | Broad task, project, tag, folder, Forecast, and perspective coverage |
| [OmniFocus Operator](https://github.com/HelloThisIsFlo/omnifocus-operator) | Python · uvx | 11 | Fast SQLite-cached reads, task creation and editing, and guided setup |

Choose FocusRelay when you want a native Swift CLI and MCP in one package,
focused model context, documented OmniFocus APIs, and carefully verified
updates. Other projects may be a better fit today if you need deletion,
attachments, recurrence, or custom perspectives immediately.

## Help shape FocusRelay

The next work is tracked in
[GitHub Issues](https://github.com/deverman/FocusRelayMCP/issues), including:

- [a smaller MCP and CLI edit surface](https://github.com/deverman/FocusRelayMCP/issues/91);
- [guided Homebrew setup](https://github.com/deverman/FocusRelayMCP/issues/92);
- [task and subtask creation](https://github.com/deverman/FocusRelayMCP/issues/82);
- [project creation and inbox-task conversion](https://github.com/deverman/FocusRelayMCP/issues/83);
- [smaller project-health queries](https://github.com/deverman/FocusRelayMCP/issues/87);
- [project folder membership and root filtering](https://github.com/deverman/FocusRelayMCP/issues/88).

If FocusRelay earns a place in your workflow,
[star the repository](https://github.com/deverman/FocusRelayMCP). Stars help
other OmniFocus users find it.

Want to improve it? Pick an issue, propose a use case, add a regression test,
improve the documentation, or open a focused pull request. See
[CONTRIBUTING.md](CONTRIBUTING.md) for setup and validation guidance.

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
