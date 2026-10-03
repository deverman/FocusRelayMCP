# Partial Task Forecast

For “How many items are in Forecast?”, use `get_task_counts` with
`filter.forecast="past-and-today"`. Explain the returned warnings. This is an
explicit partial task count, not OmniFocus's native Forecast total. Never call
a due-date-only query Forecast or treat one page's `returnedCount` as a total.

```bash
focusrelay task-counts --forecast past-and-today
focusrelay list-tasks --forecast past-and-today --include-total-count --fields id,name,dueDate,plannedDate,deferDate --limit 15
```

Both CLI and MCP use the same filter. No new tool is added. The scope is a
deduplicated union of remaining actions with any of these signals:

- due or planned before the next local midnight (past or today);
- defer date within today's half-open local day, including later today;
- native `effectiveFlagged` state;
- membership in the tag referenced by documented `Tag.forecastTag`, regardless
  of its name. If no Forecast tag is configured, that source is empty.

Completed/dropped tasks and children of completed/dropped parents are excluded.
Unavailable scheduled actions are included by default; `availableOnly=true`
explicitly restricts the union using the existing native availability helpers.
Every other filter, including inbox, project, tags, IDs, and dates, intersects
with that union. Pagination follows filtering; `includeTotalCount` and the
matching count query agree while data and the local day remain unchanged.

Every response warns that calendar events, future-day items, and project
headers are excluded. Native Forecast visibility preferences are not applied:
flagged, tagged, and unavailable actions may differ from the displayed view.
This includes potential over-inclusion, not just missing items. A caller needing
the exact native view should inspect OmniFocus; a partial count must retain its
qualification even when it happens to match.

Foundation's Gregorian calendar computes start-of-day and next-day boundaries
in the server's local timezone (the same `userTimeZone` sent with requests).
The Bridge consumes explicit epoch-millisecond boundaries and never guesses
timezones or adds 24 hours across daylight-saving transitions. Due/planned
upper bounds are exclusive; defer lower bounds are inclusive. A task due after
midnight tomorrow is excluded by this source even if its status is DueSoon.
Other signals can still include that task. Cursors are bound to the Forecast
scope; as with other queries, they do not provide snapshot isolation. Restart
paging across a local-day rollover.

## Documented API Boundary

- [Forecast](https://omni-automation.com/omnifocus/forecast.html) exposes day
  badges and window selection, not a preference-aware task membership query.
- [Tags](https://omni-automation.com/omnifocus/tag.html) documents
  `Tag.forecastTag` as the configured Forecast tag, or null.
- [Tasks](https://omni-automation.com/omnifocus/task.html) supplies task dates,
  status, parent/project, tags, and effective flags. This contract uses local
  task dates; inherited date scheduling is not reconstructed and can differ
  from native Forecast. Warnings explicitly disclose that limitation.

Validation impact: `query`. Acceptance: an MCP count question selects the
explicit scope, explains limitations, and its count matches the full paginated
list. Deterministic Bridge/MCP tests precede native semantic comparison,
canary, and the targeted 10-minute smoke. The frozen release candidate retains
the required realistic release validation; feature checks do not certify a
release.
