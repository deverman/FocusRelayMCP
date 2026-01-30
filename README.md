# FocusRelayMCP

A Model Context Protocol (MCP) server for OmniFocus on macOS. Query tasks, projects, and tags using natural language through AI assistants like Claude.

## Features

- **Time-based Queries**: "What should I do today?", "What about this morning/afternoon/evening?"
- **Project Health**: "What projects have no next actions?", "Show me stalled projects"
- **Context Awareness**: "What contexts do I have available?" (Mac, Calls, Online, etc.)
- **Stale Task Detection**: "What have I been avoiding?", "What am I procrastinating on?"
- **Smart Filtering**: By tags, due dates, defer dates, completion status, duration, and more
- **Timezone Aware**: Automatically detects your local timezone for accurate time queries

## Installation

### Prerequisites

- macOS with OmniFocus installed (4.x recommended)
- Swift 5.9+ toolchain
- opencode or Claude Desktop (for MCP integration)

### Step 1: Clone and Build

```bash
git clone <repository-url>
cd FocusRelayMCP
swift build -c release
```

### Step 2: Install the OmniFocus Plugin

```bash
./scripts/install-plugin.sh
```

This installs the FocusRelay Bridge plugin to your OmniFocus plugin directory.

### Step 3: Configure MCP

Add to your opencode.json or Claude Desktop config:

```json
{
  "mcp": {
    "focus-relay-mcp": {
      "type": "local",
      "command": ["/path/to/FocusRelayMCP/.build/release/focus-relay-mcp"],
      "enabled": true
    }
  }
}
```

### Step 4: Restart OmniFocus

⚠️ **Important**: After installing or updating the plugin, you **must restart OmniFocus**:

```bash
osascript -e 'tell application "OmniFocus" to quit' && sleep 2 && open -a "OmniFocus"
```

Or manually: Quit OmniFocus completely and reopen it.

### Step 5: Verify Installation

Run the health check:

```bash
swift run focus-relay-mcp --health-check
```

Or through your AI assistant: "Check OmniFocus bridge health"

## Usage Examples

### Daily Planning
- "What should I be doing today?"
- "What about this morning?" (6am-12pm)
- "What can I do this afternoon?" (12pm-6pm)
- "What should I work on this evening?" (6pm-10pm)

### Project Management
- "What projects have no next actions?"
- "Show me my stalled projects"
- "What tasks do I have in my Leave DFS project?"

### Context Switching
- "What contexts do I have available?"
- "Show me tasks I can do on my Mac"
- "What calls do I need to make?"

### Task Discovery
- "What have I been avoiding?" (tasks deferred >365 days)
- "What am I procrastinating on?" (tasks deferred recently)
- "Find my flagged items"

### Status Queries
- "What did I accomplish this week?"
- "How many tasks are in my inbox?"
- "Show me completed tasks"

## Available Tools

### list_tasks
Query tasks with various filters:
- `dueBefore`, `dueAfter`: Filter by due dates
- `deferBefore`, `deferAfter`: Filter by defer dates
- `tags`: Filter by specific tags
- `project`: Filter by project
- `flagged`: Show only flagged tasks
- `completed`: Show completed or remaining tasks
- `staleThreshold`: Convenience filter (7days, 30days, 90days, 180days, 270days, 365days)

### list_projects
Query projects with status and task counts:
- `statusFilter`: active, onHold, dropped, done, all
- `includeTaskCounts`: Get available/remaining/completed task counts
- Returns: hasChildren, isStalled, nextTask for project health

### list_tags
Query tags with task counts:
- `statusFilter`: active, onHold, dropped, all
- `includeTaskCounts`: Get task counts per tag

### get_task_counts
Get aggregate counts for any filter combination.

### get_project_counts
Get counts of projects and actions.

## Timezone Handling

FocusRelayMCP automatically detects your local timezone and uses it for time-based queries. When you ask:

- "What should I do this morning?" → Returns tasks available 6am-12pm **your local time**
- Tasks due today → Tasks due before end of day **in your timezone**

The timezone is detected from your macOS system settings and passed to OmniFocus for accurate filtering.

## Performance

- **Cached Queries**: Projects and tags are cached for 5 minutes (faster repeat queries)
- **Single-Pass Filtering**: All filters applied in one iteration (optimized for speed)
- **Early Exit**: Stops processing once page limit is reached
- **Typical Response Time**: ~1 second (limited by OmniFocus IPC)

## Troubleshooting

### "Plugin not responding"
- **Solution**: Restart OmniFocus completely (not just reload)

### "Wrong time period results"
- **Cause**: Timezone detection may need refresh after travel
- **Solution**: Restart both OmniFocus and opencode/Claude Desktop

### "Tasks not appearing"
- Check that tasks have proper defer/due dates set
- Verify task is not marked as completed or dropped
- Try querying with `inboxView: "available"` for available tasks

### Cache Issues
- Projects/Tags cache for 5 minutes
- Task queries are never cached (always fresh)
- Restart opencode/Claude to clear any client-side caching

## Development

### Build
```bash
swift build
```

### Test
```bash
swift test
```

### Package Plugin
```bash
./scripts/package-plugin.sh
```

## Architecture

- **Swift Layer**: MCP server, request handling, caching
- **OmniFocus Plugin (JavaScript)**: Executes within OmniFocus, queries database
- **IPC**: File-based communication between Swift and OmniFocus
- **Timezone**: Detected in Swift, passed to plugin for local-time calculations

## License

MIT

## Contributing

Issues and PRs welcome! See AGENTS.md for development notes.
