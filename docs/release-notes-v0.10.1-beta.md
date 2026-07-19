# FocusRelay 0.10.1-beta

FocusRelay 0.10.1-beta is a maintenance release focused on truthful queries,
reliable MCP pagination, concurrent Bridge requests, and one supported
OmniFocus automation architecture.

## Highlights

- Follow list pagination cursors without repeating the page limit. FocusRelay
  now applies the documented default for each list tool.
- Retrieve completed projects in date windows without the default active status
  filter hiding them.
- Treat `completed=false` consistently as remaining work, excluding dropped
  tasks and work beneath completed or dropped parents.
- Send fractional-second ISO8601 timestamps from MCP clients.
- Receive Bridge warnings in list responses and server logs.
- Handle concurrent requests without blocking Swift's cooperative executor on
  file-response polling.

## One Bridge Architecture

FocusRelay now develops, validates, benchmarks, and ships one OmniFocus path:
the installed FocusRelay Bridge plugin invoked through Omni Automation URL
dispatch. The incomplete direct-JXA engine, OSAKit linkage, alternate dispatch,
and dual-transport benchmark code have been removed.

This does not change the MCP configuration or supported tool names. It removes
unused internal paths that duplicated query semantics and complicated release
validation.

## Query And Safety Corrections

- Completed-project filters imply completed projects and compose with inclusive
  date bounds.
- Project completion-window task counts include actions exactly on the
  `completedBefore` boundary.
- Non-positive page limits fail at the MCP argument boundary and are also
  defensively clamped in the Bridge.
- Project fields that are not implemented no longer produce successful-looking
  no-op updates.
- Default tag catalog reads skip expensive task-count properties unless counts
  are explicitly requested.

## Upgrade Notes

The plugin JavaScript and binary must stay in sync. After upgrading:

1. Reinstall `FocusRelayBridge.omnijs` using the packaged installer.
2. Quit OmniFocus completely and reopen it.
3. Run `focusrelay --version` and `focusrelay bridge-health-check`.
4. Run a small query and approve the Omni Automation script if OmniFocus asks.

No MCP tool names or configuration paths changed in this release.

## Validation

The release candidate is certified through Swift tests, direct MCP wire probes,
Bridge semantic contracts, release builds, Bridge-only architecture checks, a
real MCP cursor-pagination journey, and the frozen 1.5-hour realistic benchmark
profile. Final measured counts and artifact verification are recorded in the
GitHub release and release tracker [#131](https://github.com/deverman/FocusRelayMCP/issues/131).

## Contributors

The release includes the ISO8601 bridge-decoding foundation previously
contributed by [@Lumenbeing](https://github.com/Lumenbeing), now reused at the
MCP argument boundary. Thanks also to
[@osamu2001](https://github.com/osamu2001) for earlier status and cache work that
continues to underpin the corrected query contracts.
