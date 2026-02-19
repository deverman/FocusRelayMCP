# FocusRelayMCP Next Steps

This file tracks planned work and completion status.

## Completed

- [x] Bridge mode working end-to-end (health check, inbox, projects, tags)
- [x] Inbox filtering aligns with OmniFocus "Available" view (parent dropped/completed excluded)
- [x] IPC cleanup for stale files + timeout cleanup

## In Progress

- [x] Decide final defaults for inboxView and availableOnly behavior
- [x] Add `get_task` (bridge + MCP)
- [x] Add `get_task_counts` (bridge + MCP)

## Next Up

- [x] Add paging tests for projects/tags in bridge mode
- [x] Add lock file cleanup policy in plug-in (optional)
- [x] Document bridge install/test flow in README (short checklist)
- [ ] Add completion date support for tasks (return `completedDate` and allow filtering by completed time)
- [ ] After next release, update the Homebrew tap to the new tarball/SHA that includes the `focusrelay` binary (`focusrelay serve` for MCP).

## Backlog (Post PR6 Hardening)

- [ ] Clarify inbox filter contract (`inboxView` vs `inboxOnly`)
  - Problem: `inboxView` currently changes only view mode, not scope; inbox scope requires `inboxOnly=true`.
  - Candidate fix: add explicit `scope`/`taskScope` field, or reject `inboxView` without inbox scope with a clear error.
  - Acceptance: MCP schema/docs/tests clearly enforce one contract; no ambiguous "inbox" behavior in client prompts.

- [ ] Align project "available" counts with OmniFocus availability semantics
  - Problem: project counts currently treat only `Task.Status.Available`/`Task.Status.Next` as available.
  - Candidate fix: use shared availability helper semantics (include `DueSoon`/`Overdue` where appropriate) and verify against OmniFocus expectations.
  - Acceptance: `list_projects(includeTaskCounts=true)` available counts are consistent with task-level availability rules.

- [ ] Stabilize live bridge transport under repeated calls
  - Problem: intermittent timeouts and IPC/URL dispatch failures in live test mode.
  - Details: see `docs/timeout-concurrency-investigation-2026-02-19.md`.
  - Acceptance: repeatable live bridge test runs with materially reduced timeout and interrupted-system-call failures.
