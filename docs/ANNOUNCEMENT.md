# FocusRelayMCP - Beta Release Announcement

## For OmniFocus Forum/Reddit

### Headline Options:
1. "Query Your OmniFocus Data with Natural Language - Beta Release"
2. "Tired of Clicking Through OmniFocus? Try AI-Powered Task Queries"
3. "FocusRelayMCP: Finally, Talk to Your OmniFocus Like a Human (Beta)"

### Main Post:

**What if you could ask OmniFocus questions in plain English?**

I'm excited to share the beta release of **FocusRelayMCP** - a free, open-source bridge that lets AI assistants (like Claude, ChatGPT) query your OmniFocus data using natural language.

**The Problem We All Face:**

Ever found yourself:
- 📱 Scrolling through hundreds of tasks trying to find what to do next?
- 🤔 Wondering "What did I actually accomplish this week?" but too lazy to manually check?
- 🌍 Traveling and unsure what's available to work on in your current timezone?
- 🚫 Staring at projects that seem stuck but can't figure out why?

**What FocusRelayMCP Solves:**

✅ **"What should I do today?"** - Gets tasks due today, filtered by your local timezone
✅ **"What about this morning?"** - Filters by time periods (6am-12pm, 12pm-6pm, 6pm-10pm)
✅ **"What projects have no next actions?"** - Identifies stalled projects instantly
✅ **"What contexts do I have available?"** - Shows tags with actionable tasks
✅ **"What have I been avoiding?"** - Finds tasks deferred for 30/90/365 days
✅ **"What did I accomplish this week?"** - Completed task summaries

**How It Works:**

1. Install the plugin (takes 2 minutes)
2. Connect to your AI assistant via MCP
3. Ask questions in plain English
4. Get instant, intelligent answers

**Technical Innovation:**

Unlike traditional Omni Automation approaches that can be slow, we built a **novel Bridge Library architecture** that:

- Runs directly inside OmniFocus's JavaScript context (not external scripting)
- Uses **single-pass filtering** - all query conditions evaluated in one iteration
- **Early exit optimization** - stops processing once it finds your requested number of results
- File-based IPC for fast communication between the MCP server and OmniFocus
- **Timezone-aware calculations** done locally before filtering

**Result:** Sub-second query responses even with thousands of tasks. No more waiting for OmniFocus to slowly return results.

**Technical Details:**

- Runs locally on your Mac (privacy-first, no cloud)
- Integrates via Model Context Protocol (MCP)
- Works with Claude Desktop, opencode, and other MCP clients
- Timezone-aware (handles travel seamlessly)
- Read-only for now (write support coming in v1.0)

**Try the Beta:**

Homebrew (easiest):
```bash
brew tap deverman/focus-relay
brew install focus-relay-mcp
```

Or download from GitHub: https://github.com/deverman/FocusRelayMCP/releases

**Important:** First time you run a query, OmniFocus will ask you to approve the automation script. Click "Run Script" (this is normal for security).

**What's Next:**

This is a beta (v0.9.0) - read support is solid, write support (adding tasks) is coming in v1.0. I'd love your feedback on what queries you'd find most useful!

Questions? Issues? https://github.com/deverman/FocusRelayMCP

---

## MCP Registries to Submit To

### 1. Official MCP Registry (Most Important)
**URL:** https://registry.modelcontextprotocol.io/
**How to Submit:** Create a PR at https://github.com/modelcontextprotocol/registry
**What to Include:**
- Server name: FocusRelayMCP
- Description: Query OmniFocus tasks via natural language
- Repository: https://github.com/deverman/FocusRelayMCP
- Tags: productivity, gtd, macos, omnifocus
- Installation: brew install focus-relay-mcp

### 2. GitHub MCP Registry (GitHub Blog)
**URL:** https://github.com/modelcontextprotocol/registry
**Note:** Same as above, official Anthropic registry

### 3. Glama MCP Registry
**URL:** https://glama.ai/mcp/servers
**How to Submit:** Usually via GitHub repo submission or contact form
**Good For:** Discoverability by Claude users

### 4. Smithery (MCP Registry)
**URL:** https://smithery.ai/
**Note:** Alternative MCP server registry

### 5. TrueFoundry MCP Registry
**URL:** https://www.truefoundry.com/blog/what-is-mcp-registry
**Note:** Enterprise-focused but good visibility

### 6. Reddit Communities
- r/omnifocus
- r/productivity
- r/macapps
- r/selfhosted

### 7. OmniFocus Communities
- OmniFocus Discourse Forum
- Learn OmniFocus community
- OmniFocus Slack/Discord channels

---

## Quick Registry Submission Template

**For Official MCP Registry PR:**

```json
{
  "name": "FocusRelayMCP",
  "description": "Query OmniFocus tasks, projects, and tags using natural language via AI assistants",
  "repository": {
    "type": "git",
    "url": "https://github.com/deverman/FocusRelayMCP"
  },
  "license": "MIT",
  "tags": [
    "productivity",
    "gtd",
    "macos",
    "omnifocus",
    "task-management"
  ],
  "installation": {
    "brew": "brew tap deverman/focus-relay && brew install focus-relay-mcp"
  },
  "examples": [
    "What should I do today?",
    "What projects have no next actions?",
    "What have I been avoiding?"
  ]
}
```

---

## Pain Points Summary (For Marketing)

**User Pain Points Addressed:**
1. Information overload - too many tasks to manually review
2. Context switching - hard to find relevant tasks quickly
3. Travel/timezone confusion - due dates don't account for travel
4. Project stagnation - hard to spot stalled projects
5. Procrastination awareness - no easy way to see avoided tasks
6. Weekly reviews - manual checking of completed work is tedious
7. Context availability - forgetting what tags/contexts you can use

**Solutions Provided:**
1. Natural language queries - ask like you'd ask a human
2. Time-based filtering - morning/afternoon/evening queries
3. Timezone awareness - automatic local time handling
4. Stalled project detection - automatic identification
5. Stale task thresholds - 30d/90d/365d procrastination queries
6. Completed task summaries - "What did I accomplish?"
7. Context analytics - "What contexts do I have available?"
