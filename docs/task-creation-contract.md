# Task Creation Contract In Development

Issue [#82](https://github.com/deverman/FocusRelayMCP/issues/82) owns the
implementation and validation checklist. This document defines the initial
contract; it is **not a claim that task creation is available**. No creation
tool is currently exposed. Validation impact is `mutation`.

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

The future compact `add_tasks` / `add-tasks` adapters will share one service:

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

Before enabling writes, implement and test these durable transitions:

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

Receipts must not live in `FocusRelayIPC`: startup maintenance purges unknown
entries and clears temporary protocol files on version changes. Use a separate
owner-private state directory accessible to the installed Bridge. Minimize
persisted data to intent fingerprints, approval/date/hierarchy metadata and
stable IDs; do not retain task names or notes as diagnostics. Specify retention
and recovery after state loss explicitly—expiring a receipt must not silently
enable its old key to create again.

OmniFocus execution/journal admission across distinct MCP processes must be
tested, not inferred from the server's process-local FIFO. Partial results
must distinguish created-but-unverified items from verified success. Prefer
precise recoverable partial results over an unsupported all-or-nothing claim.

## Implementation And Validation Boundary

The initial code adds typed requests, strict pure validation, ordered
traversal, versioned intent fingerprints, and a pure replay-admission policy
that never permits another apply after `applying`. It does not yet resolve
native settings, persist receipts, construct
tasks, or expose `add_tasks`. These are separate implementation checkpoints on
the same product branch, not satisfied acceptance criteria.

Before feature UAT: test production JavaScriptCore fixtures and failures at
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
