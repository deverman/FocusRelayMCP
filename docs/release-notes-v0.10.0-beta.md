# FocusRelay 0.10.0-beta

FocusRelay now writes to OmniFocus. Any MCP-compatible assistant can read your
data and safely update existing tasks and projects instead of only suggesting
what you should change. This beta provides 14 purposeful tools: seven for
reading OmniFocus and seven for making changes.

## Highlights

- Update task and project names, notes, flags, dates, estimates, tags, review
  settings, and other supported fields.
- Complete, reactivate, change status, and move existing tasks or projects.
- Preview an important change before applying it and confirm afterward that
  OmniFocus saved it.
- Apply the same change to several selected tasks or projects in one request.
- Find tasks using words from either their names or notes.
- Find the right OmniFocus folder when moving a project.
- Get consistent answers when asking an assistant to show matching tasks or
  count them.
- Keep the assistant focused with a compact tool catalog that does not spend
  context on internal troubleshooting commands.

## Safety And Correctness

- FocusRelay changes the exact tasks and projects selected by their stable
  OmniFocus IDs.
- MCP clients can recognize which actions write to OmniFocus and show the
  appropriate approval prompt first.
- FocusRelay reports success only after OmniFocus applies and saves the requested
  change. When confirmation is requested, it checks the saved result too.
- Task and project results follow OmniFocus's own status rules, including
  on-hold or dropped projects and work beneath completed parent tasks.

Use `previewOnly=true` before broad changes and `verify=true` for real writes
when post-write confirmation matters. Omitting both performs an immediate,
unverified write.

## Performance And Reliability

FocusRelay is designed to be one of the fastest OmniFocus MCP integrations for
everyday use. We test performance against thousands of OmniFocus tasks—not a
tiny sample database.

- Focused inbox reads typically returned in about one second during testing.
- Single-pass filtering avoids repeatedly scanning the same tasks.
- Early-stop paging stops processing as soon as FocusRelay has enough results
  for the requested page.
- Five-minute project and tag caching makes repeated lookups much faster while
  task queries remain uncached and current.
- Updating several selected items at once and returning only the requested
  details avoids unnecessary round trips.
- Across more than 1,400 measured calls in smoke and sustained benchmark runs,
  FocusRelay completed every call without an error or timeout.

## Current Limits

This beta updates existing tasks and projects but does not create or delete
them. Task creation is tracked in
[#82](https://github.com/deverman/FocusRelayMCP/issues/82), and project creation
is tracked in [#83](https://github.com/deverman/FocusRelayMCP/issues/83). The
beta also does not edit repetition rules or planned dates. We will add those
capabilities only after defining equally clear safety and verification behavior.

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
