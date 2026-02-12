# Project Agent Notes

- Use the Swift Testing framework built into the Swift toolchain (`Testing` module, `@Test`, `#expect`).
- Do not add `swift-testing` as a package dependency.
- Add or update Swift tests when new functionality is added.
- Run `swift test` after changes.

## Plugin Installation

When the FocusRelayBridge plugin needs to be updated in OmniFocus, **always use the install script**:

```bash
./scripts/install-plugin.sh
```

This script automatically detects the correct OmniFocus plugin directory (iCloud, sandboxed, or legacy).

⚠️ **Critical**: After installation, **restart OmniFocus completely** (not just reload):

```bash
osascript -e 'tell application "OmniFocus" to quit' && sleep 2 && open -a "OmniFocus"
```

The plugin JavaScript is cached by OmniFocus and requires a full restart to pick up changes.

## Timezone Handling

The MCP server automatically detects the user's local timezone from macOS system settings:

- **Detection**: `TimeZone.current.identifier` (e.g., "Asia/Singapore", "America/New_York")
- **Propagation**: Passed via `userTimeZone` field in every `BridgeRequest`
- **Usage**: JavaScript plugin can calculate morning/afternoon/evening in local time before converting to UTC

This ensures that time-based queries ("What should I do this morning?") work correctly regardless of the user's location.

## Performance Optimizations

### JavaScript Layer (BridgeLibrary.js)
- **Single-pass filtering**: All filter conditions checked in one iteration (was 10+ passes)
- **Early exit**: Stop processing after reaching page limit (e.g., 10 tasks instead of 2874)
- **Pre-parsed dates**: Parse filter dates once, reuse timestamps

### Swift Layer
- **Faster polling**: Reduced `waitForResponse` interval from 100ms to 50ms
- **Removed debug overhead**: Cleaned up print statements and logging

### Impact
- Task filtering: Now sub-millisecond (was 50-100ms with multiple passes)
- End-to-end latency: Still ~1s (dominated by IPC/file I/O, not code)

## Caching Strategy

The MCP server implements an **actor-based caching layer** (`CatalogCache`) for frequently accessed, slowly-changing data:

### Current Implementation
- **Location**: `Sources/OmniFocusAutomation/CatalogCache.swift`
- **TTL**: 300 seconds (5 minutes) for projects and tags
- **Cache Keys**: Based on pagination (limit, cursor) and requested fields
- **Thread Safety**: Uses Swift `actor` for safe concurrent access

### What's Cached
- ✅ **Projects** (`list_projects`) - Cached with 5-minute TTL
- ✅ **Tags** (`list_tags`) - Cached with 5-minute TTL
- ❌ **Tasks** (`list_tasks`) - Not cached (changes frequently)

### Cache Invalidation
- Automatic expiration after TTL
- No manual invalidation currently implemented
- Future: Invalidate on write operations when write tools are added

### Performance Impact
- Projects/Tags queries: ~300ms → ~10ms (30x faster on cache hit)
- Task queries: No caching (always fresh data)

## Release Process

When creating a new release (via GitHub Actions or manually), follow these steps:

### 1. Create Release Tag
```bash
git tag -a vX.X.X -m "Release vX.X.X: Description of changes"
git push origin vX.X.X
```

### 2. Update Homebrew Formula (⚠️ CRITICAL - MUST DO AFTER EVERY RELEASE!)

**⚠️ WARNING: You MUST update the SHA256 after EVERY release, even for the same version!**

Every time you create or re-create a release, GitHub rebuilds the tarball and the SHA256 changes. If you skip this step, Homebrew installations will fail with checksum errors.

**Step 1: Get the new SHA256 from the release**
```bash
curl -sL https://github.com/deverman/FocusRelayMCP/releases/download/vX.X.X/focusrelay-X.X.X.sha256
```

**Step 2: Update the formula in `deverman/homebrew-focus-relay`**
```bash
cd ~/homebrew-focus-relay  # or wherever you cloned it

# Edit focusrelay.rb and update BOTH:
# - version number in the URL (if changed)
# - sha256 value (MUST be updated every time!)
# 
# Example: Change this line:
# sha256 "OLD_SHA256_HERE"
# To:
# sha256 "NEW_SHA256_FROM_STEP_1"

# Then commit and push:
git add focusrelay.rb
git commit -m "Update SHA256 for vX.X.X"
git push origin main
```

**Step 3: Verify the tap works**
```bash
brew update
brew install focusrelay
# OR if reinstalling:
brew reinstall focusrelay
```

**🔴 COMMON MISTAKE:** Forgetting to update the SHA256 when re-releasing the same version (e.g., fixing a bug and re-tagging v0.9.0-beta). The tarball is rebuilt every time, so the SHA256 will change even if the version number stays the same.

**🔴 TROUBLESHOOTING:** If Homebrew still reports the OLD checksum after you updated the formula, the tap is cached locally. Force a fresh tap:
```bash
rm -rf /opt/homebrew/Library/Taps/deverman/homebrew-focus-relay
brew tap deverman/focus-relay
brew install focusrelay
```

**🔴 MIGRATION FROM OLD NAME:** If you have the old `focus-relay-mcp` installed:
```bash
brew uninstall focus-relay-mcp
brew untap deverman/focus-relay
rm -rf /opt/homebrew/Library/Taps/deverman/homebrew-focus-relay
brew tap deverman/focus-relay
brew install focusrelay
```

### 3. GitHub Release Notes
The GitHub Actions workflow auto-generates release notes, but add:
- Summary of major changes
- Breaking changes (if any)
- Link to CHANGELOG.md
- **Contributor mentions**: When including changes from pull requests, @mention the contributor (e.g., "Thanks to @username for the fix") to give credit and notify them

### Future Improvements
- Add task caching with shorter TTL (30-60 seconds)
- Implement cache warming for startup
- Add cache statistics/metrics endpoint
- Add cache control parameter (`skipCache: true`) for users needing fresh data
- **INVESTIGATE:** Use task/project notes field effectively with MCP for additional context
  - Research how to extract meaningful context from notes
  - Consider semantic search or summarization of note content
  - Potential use cases: finding tasks by note content, summarizing project notes
  - Challenge: Notes can be large, need efficient indexing/search strategy
