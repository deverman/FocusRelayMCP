# FocusRelay 0.11.0-beta

FocusRelay 0.11.0-beta makes bulk OmniFocus cleanup and review workflows safer,
more discoverable, and harder for MCP clients to misuse.

## Highlights

- Drop and restore tasks without creating false completion history, including
  explicit occurrence/series handling for repeating tasks.
- Mark active or on-hold projects reviewed with native OmniFocus review-date
  behavior and verified readback.
- Resolve project names to stable IDs with deterministic, case-insensitive
  `list_projects` search before previewing a mutation.
- Reject malformed MCP arguments instead of silently returning plausible
  unfiltered data.
- Keep bulk writes all-or-nothing when any requested target is unknown or
  ineligible.
- Keep Review perspective active and on-hold batches disjoint and correctly
  counted.
- Bind opaque pagination cursors to their originating query so changing filters
  cannot silently skip or duplicate targets.

## Breaking Tool Consolidation

The seven legacy task/project mutation tools have been replaced by two explicit
operation-based tools:

- `edit_tasks` with `update`, `set_status`, `set_completion`, or `move`
- `edit_projects` with `update`, `set_status`, `set_completion`, or `move`

Each request supplies one operation, stable target IDs, and exactly one matching
payload. CLI users use `edit-tasks` and `edit-projects`. See
[Mutation Workflows](mutation-workflows.md) for the migration table and
read-before-write examples.

## Safer Agent Workflows

FocusRelay now closes every public MCP argument object and validates the same
schemas returned by `tools/list` before query or mutation dispatch. A misplaced
task search receives a path-specific correction, unknown nested properties fail
clearly, and malformed mutations never reach the Bridge.

Project lookup no longer requires walking the complete catalog:

```bash
focusrelay list-projects --search "drop test" --status all --fields id,name,status
focusrelay edit-projects PROJECT_ID --operation set_status --status dropped --preview-only --return-fields id,name,status
```

Search is a trimmed, literal, case-insensitive substring match against project
names only. Follow `nextCursor` while it is present before concluding that no
additional filtered matches exist.

## Upgrade Notes

The plugin JavaScript and binary must stay in sync. After upgrading:

1. Reinstall `FocusRelayBridge.omnijs` using the packaged installer.
2. Quit OmniFocus completely and reopen it.
3. Run `focusrelay --version` and `focusrelay bridge-health-check`.
4. Run a small query and approve the Omni Automation script if OmniFocus asks.

Existing saved raw numeric pagination cursors are intentionally invalid. Restart
pagination from page one to receive a query-bound cursor.

## Validation

The release candidate is certified through Swift Testing, direct MCP wire
probes, deterministic JavaScriptCore contracts, Bridge semantic gates, live
read-before-write and mutation UAT, a release build, and the frozen realistic
release benchmark. Final benchmark and artifact evidence is recorded in release
tracker [#152](https://github.com/deverman/FocusRelayMCP/issues/152).
