# MCP Server Best Practices (General + Swift)

## General MCP Best Practices

1) Keep tool surface small and stable
- Prefer a few tools with structured inputs and outputs.
- Avoid overlapping tools; create predictable schemas.

2) Minimize tokens by default
- Default to small pages (e.g., 50–100).
- Support `fields` selection and only return requested fields.
- Return IDs and names by default; avoid large notes/attachments unless asked.

3) Use pagination everywhere
- Always return `nextCursor` if more data exists.
- Never dump entire datasets in one call.
 - Document pagination clearly in tool descriptions.

4) Provide cheap summary/count endpoints
- e.g., `get_task_counts` to help plan queries without fetching all items.

5) Deterministic schemas, explicit errors
- Errors should be structured with `code` + `message`.
- Make errors actionable (missing id, permission denied, timeout).

6) Avoid tool chatter
- Batch operations when possible (e.g., list projects once, then reuse).
- Use caching on the server to reduce repeated tool calls.

7) Explicit safety boundaries
- For write actions, include dry-run or preview modes.
- Require explicit confirmation for bulk writes.
- For FocusRelay mutations, use `previewOnly`, `verify`, and compact `returnFields`; see [`mutation-workflows.md`](./mutation-workflows.md).

8) Timeouts + retries
- Short timeouts with clear errors.
- Use small retries where safe and idempotent.

9) Observable performance
- Include timing metadata for large operations.
- Log only small summaries to avoid leaking large payloads.

## Swift-Specific Best Practices

1) Strong typing at boundaries
- Decode tool inputs into typed structs.
- Encode outputs with `JSONEncoder` using ISO-8601 dates.

2) Use async/await for tool calls
- Keep blocking operations off the main thread.
- Use `Task.sleep` for small poll loops instead of busy wait.

3) Small, testable modules
- Core models in a standalone module.
- Automation layer separate from MCP layer.

4) Resource-safe IPC
- Use atomic writes for request/response files.
- Cleanup stale files on startup or before requests.

5) Cache where it matters
- Short TTL cache for lists of projects/tags.
- Invalidate project/tag catalog caches after successful non-preview write operations.

6) Avoid macOS UI activation
- Use `open -g` when triggering OmniFocus.
- Keep user-facing alerts limited to permission prompts.

7) Structured logs
- Use `swift-log` with clear event tags (bridge, ipc, tool).
