# FocusRelay 0.10.0-beta

FocusRelay now brings its first write tools to OmniFocus. Any MCP-compatible
assistant can read OmniFocus and use 14 focused tools: seven for reading and
seven for making supported changes to existing tasks and projects.

## Highlights

- Update task and project names, notes, flags, dates, estimates, tags, review
  settings, and other supported fields.
- Complete, reactivate, change status, and move existing tasks or projects.
- Preview changes before applying them and verify that OmniFocus saved them.
- Apply the same change to several selected tasks or projects in one request.
- Search task names and notes, and find folders when moving projects.
- Get consistent task lists and counts from the same filters.
- Match OmniFocus's Flagged view, including flags inherited from a project or
  parent task.
- Keep the assistant focused with a compact catalog that excludes internal
  diagnostics.

## Safe And Fast By Design

FocusRelay targets stable OmniFocus IDs, identifies write actions so MCP clients
can request approval, and reports success only after OmniFocus applies and saves
the change. Queries follow OmniFocus's native status rules, including on-hold or
dropped projects and completed parent tasks.

Use `previewOnly=true` before broad changes and `verify=true` for real writes
when confirmation matters. Omitting both applies the change immediately.
MCP clients can send only the fields they intend to change; unrelated values
are left untouched.

FocusRelay aims to be one of the fastest OmniFocus MCP integrations. Testing
covered thousands of tasks and more than 2,000 measured calls without an error
or timeout; focused inbox reads typically returned in about one second.
Single-pass filtering, early-stop paging, project/tag caching, and bulk updates
keep common requests efficient while task queries remain current.

## Current Limits

This beta does not create or delete tasks or projects, edit repetition rules, or
write planned dates. Task and project creation are tracked in
[#82](https://github.com/deverman/FocusRelayMCP/issues/82) and
[#83](https://github.com/deverman/FocusRelayMCP/issues/83).

## Upgrade Notes

The plugin JavaScript and binary must stay in sync. After upgrading:

1. Reinstall `FocusRelayBridge.omnijs` in OmniFocus.
2. Quit OmniFocus completely and reopen it.
3. Run `focusrelay --version` and `focusrelay bridge-health-check`.
4. If OmniFocus asks for automation approval on the first query, choose
   **Run Script**.

## Validation

- All 126 Swift Testing tests and task-list, task-count, and project-count
  semantic gates pass with Swift 6.3.3.
- Smoke and sustained benchmarks completed with full scenario coverage and no
  errors, timeouts, or parity mismatches in the final validation.

## Contributors

Thanks to [@osamu2001](https://github.com/osamu2001) for the catalog-cache key
correctness fix, and to [@Lumenbeing](https://github.com/Lumenbeing) for the
ISO8601 date-decoding fix and regression coverage incorporated into the final
implementation.
