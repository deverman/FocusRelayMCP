# FocusRelay 0.10.0-beta

FocusRelay can now safely update existing OmniFocus tasks and projects as well
as read them. This beta keeps the model-facing surface intentionally compact:
14 product tools cover task, project, tag, and folder reads plus seven focused
task/project mutation operations.

## Highlights

- Update task and project names, notes, flags, dates, estimates, tags, review
  settings, and other supported fields.
- Complete, reactivate, change status, and move existing tasks or projects.
- Preview risky or bulk changes, verify real writes, and request compact
  post-write fields without a second model round trip.
- Discover folder IDs for project moves with `list_folders`.
- Search task names and notes with the same filter contract used by
  `list_tasks` and `get_task_counts`.
- Keep internal health and inbox probes out of the public MCP catalog while
  retaining them as operator CLI diagnostics.

## Safety And Correctness

- Writes target stable OmniFocus IDs and apply one homogeneous operation per
  call; name-based and mixed-operation mutations are intentionally unsupported.
- All mutation tools now advertise truthful destructive/write annotations so
  MCP clients can present appropriate approval UX.
- Save, per-target apply, verification, and returned-field failures cannot be
  reported as successful writes.
- Task and project availability/counts use OmniFocus native status values and
  respect completed or dropped parent chains.

Use `previewOnly=true` before broad changes and `verify=true` for real writes
when post-write confirmation matters. Omitting both performs an immediate,
unverified write.

## Performance And Reliability

- Plugin URL dispatch remains the production architecture after corrected
  transport comparisons and the current release validation. Pure JXA remains
  an internal parity/benchmark reference for now.
- Focused inbox reads are typically around one second through the plugin in the
  current database, versus roughly six to eight seconds through JXA.
- Projects and tags retain five-minute actor-backed caching; tasks stay fresh.
- Bulk mutations and compact verified return fields avoid unnecessary bridge
  round trips.

## Current Limits

This v1 write surface does not create or delete tasks/projects, edit repetition
rules, or write planned dates. Those operations remain out of scope until their
contracts and safety UX are designed separately.

## Upgrade Notes

The plugin JavaScript and binary must stay in sync. After upgrading:

1. Reinstall `FocusRelayBridge.omnijs` in OmniFocus.
2. Quit OmniFocus completely and reopen it.
3. Run `focusrelay --version` and `focusrelay bridge-health-check`.
4. If OmniFocus asks for automation approval on the first query, choose
   **Run Script**.

## Validation

- 120 Swift Testing tests pass with Swiftly-managed Swift 6.3.3.
- All task-list, task-count, and project-count semantic gates pass.
- The combined pre-follow-up realistic suite completed 750 measured calls with
  zero errors or timeouts.
- Corrected task-search smokes completed 192 measured calls with complete
  scenario coverage and no error, timeout, or parity mismatch.
- The post-search 30-minute realistic list phase completed 266 measured calls
  across all ten scenarios with no error, timeout, or parity mismatch.
- The corresponding 30-minute realistic count phase completed 278 measured
  calls across all six scenarios with no error, timeout, or parity mismatch;
  OmniFocus ended 447 MB below its phase-start RSS.

## Contributors

Thanks to [@osamu2001](https://github.com/osamu2001) for the catalog-cache key
correctness fix, and to [@Lumenbeing](https://github.com/Lumenbeing) for the
ISO8601 date-decoding fix and regression coverage incorporated into the final
implementation.
