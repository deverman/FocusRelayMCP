# Task Creation Contract

Issue [#82](https://github.com/deverman/FocusRelayMCP/issues/82) owns the
implementation and validation checklist. The candidate exposes `add_tasks`
and `focusrelay add-tasks`. Availability in a released Homebrew build depends
on the release version; draft implementation is not release certification.
Validation impact is `mutation`.

## Bounded User Journey

An assistant proposes ordered tasks or subtasks in the inbox, an existing
project, or beneath an existing task. Preview validates the entire hierarchy
and resolves dates to concrete local and UTC values. The user approves that
preview. Execution creates, saves and verifies IDs, parent/destination, native
sibling order, and requested fields. Unapproved plans leave OmniFocus unchanged.

Project creation/conversion (#83), missing tags (#128), and unrestricted or
ordinal natural-language date parsing are outside this slice. Existing projects
returned by #83 can later use the same project-ID destination; #82 does not
need to know how the project was created.

## Typed Request

The compact `add_tasks` / `add-tasks` adapters share one service:

```json
{
  "creationKey": "7186bc33-067a-44c6-afab-9a5659c5f953",
  "destination": {"kind": "parent_task", "id": "existing-task-id"},
  "previewOnly": true,
  "tasks": [
    {
      "clientID": "research",
      "name": "Research options",
      "due": {"on": "2026-10-06", "time": {"policy": "omnifocus_default"}},
      "tagIDs": ["existing-tag-id"]
    },
    {
      "clientID": "draft",
      "name": "Draft proposal",
      "children": [{"clientID": "review", "name": "Review draft"}]
    }
  ]
}
```

- Destination defaults to inbox. Project and parent-task destinations require
  a stable ID, never a guessed name; existence and eligibility are Bridge
  preflight checks.
- Task arrays preserve requested sibling order and append to the destination's
  existing children. Constructor traversal is preorder, parents before children.
- A request contains at most 20 tasks including descendants and five hierarchy
  levels. Every node has a globally unique `clientID` within that request, using
  1–64 ASCII letters, digits, underscores or hyphens.
- Fields are name, optional note, local flag, non-negative estimate, existing
  tag IDs, due/defer intent, and children. No planned-date write is introduced.
- Missing `previewOnly` means preview. Execution requires a UUID
  `approvedPreviewID` from a successful preview; a well-formed UUID alone is not
  proof of approval. The durable receipt must bind it to the exact plan.
- Normalize UUID casing before lookup so aliases cannot bypass duplicate checks.
- Names, stable IDs, parent IDs, native order and resolved due/defer values are
  always returned. `returnFields` defaults to `["name"]` and can additionally
  select `note`, `flagged`, `estimatedMinutes`, `tagIDs`, `dueDate`, `deferDate`.
- MCP must reject unknown fields through closed schemas, with paired CLI and
  direct argument/wire coverage. Model decoding alone does not prove this gate.

## Dates And Frozen Approval

An exact date uses `{"at":"2026-10-06T17:00:00+08:00"}`. A date-only intent uses
`{"on":"2026-10-06","time":{"policy":"omnifocus_default"}}`. Exactly one
form is required. Date-only strings are real Gregorian `YYYY-MM-DD` dates;
normalization of nonexistent dates, overflowing times, or implicit timezone
guesses is rejected.
Exact timestamps support at most millisecond precision, matching JavaScript
Date storage; excess precision is rejected rather than silently rounded.

During Bridge preview, date-only intent reads the current
`settings.objectForKey("DefaultDueTime")` or `DefaultStartTime` and uses
documented `Calendar.current` and `DateComponents`. Missing or invalid settings
fail; there is no invented noon/midnight fallback. Check timezone consistency
with the server's propagated identifier and validate component round trips
across DST. Return the original intent, local date/time, timezone, and UTC
timestamp. No additional bridge call is needed solely to resolve a date.

Approved execution must use the frozen preview timestamps, not resolve them
again from a changed clock, setting, or timezone. If the exact plan cannot be
preserved, fail rather than silently changing the approved result.

## Duplicate-Safe Execution Design

`creationKey` is a caller-supplied UUID reused across preview, apply and
reconciliation. Transport request IDs remain separate. Retrying with a new key
is a new creation, not recovery, and must never be suggested as an automatic
response to uncertainty.

The Bridge uses these durable transitions:

1. Preview preflights every field, tag and destination, then freezes the intent
   fingerprint, resolved dates and hierarchy against an approval ID.
2. Apply validates the matching approval and plan, rechecks destination/tag
   eligibility, and durably enters `applying` **before the first constructor**.
3. Record each created stable ID immediately. Only report success after save
   and full readback verification, including native order.
4. Completed replay reads and verifies known IDs; it never invokes constructors.
5. An incomplete, damaged or uncertain receipt never authorizes another apply.
   Return known IDs, what was verified, and actionable reconciliation guidance.
   A crash between constructor and ID journaling may leave an unknown created
   item; disclose that uncertainty instead of claiming no write occurred.

Receipts do not live in `FocusRelayIPC`: startup maintenance purges unknown
entries and clears temporary protocol files on version changes. Use a separate
owner-private sibling `FocusRelayState/creation-v1` directory accessible to the
installed Bridge. Both directory levels are mode `0700`; admission files are
`0600`. Receipts persist only fingerprints, approval/date metadata, destination
parent ID and created stable IDs, not task names or notes.

Receipts and admission tombstones are retained indefinitely and are never
expired by IPC cleanup or upgrades. Same-key admission uses an OS file lock
across processes, plus synchronous native journal transitions. Lock files are
never unlinked or replaced. A surviving admission tombstone with a missing
receipt fails before dispatch, including preview. A failed native preview can
therefore consume its key without writing a task; review a fresh proposal with
a fresh key. An approved apply without a receipt always fails.

Do not delete this state directory to troubleshoot IPC. If the entire state
store is lost, restore it from backup or inspect OmniFocus and explicitly
review a new proposal; callers must not automatically generate replacement
keys. No system can recognize old keys after all their durable history is
deliberately removed.

OmniFocus execution/journal admission across distinct MCP processes is separate
from the server's process-local FIFO. Partial results
must distinguish created-but-unverified items from verified success. Prefer
precise recoverable partial results over an unsupported all-or-nothing claim.

## Implementation And Validation Boundary

`add_tasks` uses a closed, bounded schema and the same typed service contract as
the CLI. Creation is a write, non-destructive (no deletion/rollback), and
idempotent for repeated identical keyed intent. Unknown fields fail in either
adapter. Verification is mandatory; there is no unverified-success switch.

CLI example: save the JSON above as `proposal.json`, then run:

```bash
focusrelay add-tasks --request-file proposal.json
```

After the user approves the returned concrete preview, retain the exact same
proposal, change only `previewOnly` to `false`, add `approvedPreviewID` using the
returned `previewID`, and run the same command. `--request-json` is an alternative
to file input. Never use both. Partial/uncertain output is structured JSON with
a nonzero CLI exit status or MCP `isError=true`.

All reported `verified` tasks have passed field/hierarchy/order readback after
save. `unverified` means a known created ID or a constructor that may have
started; `not_created` means that node was not attempted. Save failure does not
claim persistence even if the task is currently visible. Reconciliation reads
known state only; it does not repair fields, save again, construct missing
nodes, or delete partial results. Such recovery needs an explicit reviewed
follow-up using existing edit tools or native OmniFocus, not blind retry.

Required gates include production JavaScriptCore fixtures and failures at
constructor, journal, field apply, save and verification; direct MCP arguments
and annotations; CLI parity; changed preview intent; duplicate/restarted and
cross-process retries. Then perform reversible live create/verify/cleanup for
inbox, project and parent-task destinations, ordered multi-level hierarchies,
and date-only input at a non-default configured due/defer time. Run Kimi and
comparison-model journeys. The final release candidate retains realistic
validation.

Documented references:

- [Task constructor and insertion locations](https://omni-automation.com/omnifocus/task.html)
- [Current database settings](https://omni-automation.com/omnifocus/settings.html)
- [Calendar and DateComponents](https://omni-automation.com/shared/calendar.html)
