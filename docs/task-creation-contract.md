# Task Creation Contract

Issue [#82](https://github.com/deverman/FocusRelayMCP/issues/82) owns the
implementation and validation evidence. The candidate exposes `add_tasks`
and `focusrelay add-tasks`; a tested PR is not release certification.
Validation impact: `transport-reliability`.

## User Journey

The client previews ordered tasks and subtasks in the inbox, an existing
project, or beneath an existing task. It shows the hierarchy and resolved
dates to the user. After approval, it submits the returned `applyRequest`
once. FocusRelay creates, saves, and verifies the tasks.

Approval belongs to the client, like the edit tools. Omitted `previewOnly`
means **apply**, not preview. An explicit preview creates and saves nothing.
Ignoring a preview leaves OmniFocus unchanged.

Project creation/conversion (#83), missing tag creation (#128), and unrestricted
natural-language date parsing are outside this feature.

## Request

MCP and CLI share the same closed request contract:

```json
{
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
  existing stable IDs; the Bridge preflights eligibility and every tag reference
  before the first constructor.
- Arrays preserve sibling order and append to existing children. Parents are
  created before descendants.
- Requests contain at most 20 total tasks and five hierarchy levels.
  Each node requires a unique `clientID`: 1–64 ASCII letters, digits,
  underscores, or hyphens.
- Supported fields are name, note, flag, non-negative estimated minutes,
  existing tag IDs, due/defer dates, and children.
- `returnFields` defaults to `["name"]`; optional confirmation fields are
  `note`, `flagged`, `estimatedMinutes`, `tagIDs`, `dueDate`, and `deferDate`.
- Unknown fields are rejected. There are no creation keys or approval tokens.

## Dates And Apply Request

Exact dates use `{"at":"2026-10-06T17:00:00+08:00"}`. Date-only inputs use
`{"on":"2026-10-06","time":{"policy":"omnifocus_default"}}`.
Exactly one form is required. Exact timestamps require seconds, an explicit
offset or Z, and at most millisecond precision. Invalid or normalized calendar
dates and overflowing times are rejected.

Date-only values are accepted **only in previews**. The Bridge reads current
`DefaultDueTime` or `DefaultStartTime` through documented settings APIs and
uses `Calendar.current` and `DateComponents`. Missing settings, timezone
mismatches, and nonexistent DST wall times fail without creating tasks.
There is no invented default time.

A preview returns original date intent, resolved local time, timezone, UTC
timestamp, and a complete `applyRequest`. That request preserves destination,
task fields, hierarchy, order, and return fields while replacing date-only
values with exact `at` timestamps and setting `previewOnly: false`.
Submit it after user approval; do not calculate offsets or reconstruct the
tree with the model. Changed OmniFocus defaults cannot change those exact
instants.

Direct apply is allowed when dates are absent or exact. An apply containing
date-only values is rejected before dispatch. The apply payload is ordinary
request data, not server-side proof of prior preview or approval.

## One Attempt, Verified Results

Creation retains no persistent history, receipts, retry window, or replay
store. Existing development history files are neither used nor automatically
deleted. Ordinary temporary Bridge IPC maintenance remains unchanged.

An apply is dispatched at most once. Creation apply disables both stranded
redispatch and late redispatch recovery; other operations retain their existing
recovery behavior. The server still waits for the original response within its
normal deadline.

**Repeating an apply may create duplicates.** If a response is lost or cannot
be confirmed, check OmniFocus before submitting another creation request.
Neither server nor client should automatically repeat an uncertain write.
Known pre-dispatch busy/queue rejections remain distinct and may be retried
after their suggested delay.

`completed` means every task was created, saved, and read back successfully,
including fields, parent IDs, and relative sibling order. Verification is
mandatory. Failures stop the attempt without automatic repair, rollback,
or another constructor pass.

Results distinguish `verified`, `unverified`, and `not_created`.
Known created IDs are returned when available. A constructor may have started
without producing a known ID; disclose uncertainty rather than claiming no
write occurred. Save failure never claims verified persistence.
A lost transport response returns `uncertain` with no invented IDs.

## CLI And MCP

Save the preview JSON as `proposal.json`:

```bash
focusrelay add-tasks --request-file proposal.json
```

After approval, save the returned `applyRequest` as `apply.json` and submit once:

```bash
focusrelay add-tasks --request-file apply.json
```

`--request-json` is an alternative; never supply both input options.
Partial/uncertain output is structured JSON with nonzero CLI exit status or
MCP `isError=true`. MCP annotations identify creation as a non-destructive,
non-idempotent write.

## Validation

Required coverage includes model and CLI defaults; direct MCP decoding,
closed fields and annotations; production JavaScriptCore hierarchy, dates,
special client IDs, and constructor/field/save/verification failures;
single-dispatch transport faults; and unchanged query recovery.

Live UAT must preview, approve, apply once, independently verify, and remove
disposable fixtures across inbox, project, and parent-task destinations.
Exercise date-only values, ordered descendants, ignored previews, and
controlled lost-response handling through actual MCP clients. A targeted
ten-minute preview/query smoke precedes the separate frozen release gate.

Documented references:

- [Task constructor and insertion locations](https://omni-automation.com/omnifocus/task.html)
- [Current database settings](https://omni-automation.com/omnifocus/settings.html)
- [Calendar and DateComponents](https://omni-automation.com/shared/calendar.html)
