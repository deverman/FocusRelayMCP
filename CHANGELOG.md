# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Active and on-hold projects can be marked reviewed through
  `projectPatch.reviewedNow=true`; FocusRelay preflights the complete batch,
  preserves review intervals, uses one request-level timestamp, and verifies the
  OmniFocus-generated next review date.

### Changed

- **Breaking:** Seven task and project mutation tools and CLI commands were
  consolidated into `edit_tasks` / `edit-tasks` and
  `edit_projects` / `edit-projects`. Each request now selects an explicit
  operation and supplies exactly one matching payload; legacy aliases were
  removed. See the
  [migration table](docs/mutation-workflows.md#breaking-migration).

## [0.10.1-beta] - 2026-07-19

### Added

- Bridge response warnings now appear in server logs and list responses instead
  of being silently discarded.
- Impact-based development and release validation commands, explicit benchmark
  profiles, production fingerprint reports, and Markdown link validation.
- MCP Registry metadata, contribution guidance, and an MIT license.

### Changed

- FocusRelay now has one OmniFocus architecture: the installed Bridge plugin
  invoked through plugin URL dispatch. Retired direct-JXA and OSAKit runtime,
  diagnostic, and benchmark paths were removed from debug and release builds.
- Blocking Bridge response waits run outside Swift's cooperative thread pool so
  concurrent MCP requests do not monopolize executor threads.
- Bridge-only benchmark commands share one implementation while preserving
  established scenarios and artifact fields.
- Default tag listing avoids calculating per-tag task counts unless
  `includeTaskCounts=true`.

### Fixed

- Completed-project date-window queries no longer disappear under the default
  active-project status filter.
- `completed=false` now means remaining work and excludes dropped tasks and
  children of completed or dropped parents.
- `get_project_counts` uses the documented inclusive `completedBefore` bound for
  task counts.
- MCP arguments accept ISO8601 timestamps with fractional seconds.
- List tools reject non-positive page limits instead of producing empty or
  backwards pagination, and cursor-only page objects use each tool's documented
  default limit.
- Unsupported project patch fields fail clearly instead of appearing to succeed
  as no-ops.

## [0.10.0-beta] - 2026-07-14

### Added

- A preview-first write surface for homogeneous bulk task and project updates,
  completion changes, status changes, and moves, with compact verified return
  fields.
- Public folder discovery through `list_folders` for project move destinations.
- `focusrelay --version`, shared CLI/MCP build metadata, and release-time version
  synchronization for the binary and OmniFocus plugin.
- Write contracts, mutation workflow guidance, query/benchmark gates, and release
  engineering checklists.

### Changed

- `list_tasks` and `get_task_counts` now publish the same complete task-filter
  schema, including estimate bounds, enum choices, date formats, and count
  behavior.
- Internal bridge health and inbox diagnostics remain available to operators
  through the CLI but are no longer part of the model-facing MCP tool catalog.
- Builds now use Swift 6.3.3 through Swiftly and CI, with Swift tools 6.3 and
  `swift-sdk` 0.12 compatibility.
- Project task counts now use the same native OmniFocus status semantics as task
  queries, including parent and project status constraints.
- Successful writes invalidate project and tag caches so subsequent reads show
  the saved changes immediately.
- Release packaging now produces and verifies the `focusrelay` binary, plugin,
  archive, checksum, prerelease metadata, and tag-derived version consistently.
- Homebrew formula ownership now points exclusively to the external
  `deverman/homebrew-focus-relay` tap.

### Fixed

- The list-task benchmark now rotates scenarios per plugin/JXA pair and fails
  when any declared scenario lacks measured coverage.
- Task name/note search now applies case-insensitive substring filtering in
  both task listing and task counts, with matching plugin and JXA semantics.
- MCP mutation annotations now identify edits, lifecycle changes, and moves as
  destructive updates so clients can present appropriate approval UX; schemas
  also state when omitting preview or verification performs an immediate write.
- Mutation save, per-target apply, verification, and returned-field failures can
  no longer be reported as successful writes.
- Children of completed or dropped parent tasks no longer appear as remaining or
  available.
- Tagged project roots are retained in task query results.
- Project-scoped task results and project task counts now agree across bridge and
  documented JXA fallback paths.
- Flagged task filters and counts now match OmniFocus's visible flag state,
  including flags inherited from parent tasks or projects, without counting
  invisible project roots as actions.
- Catalog cache keys now distinguish filter state.
- Bridge timeout diagnostics now report pickup state and stranded redispatch
  information.
- CI artifact upload and manual/tag release version selection now fail clearly
  instead of silently publishing incomplete assets.
- Sparse MCP task, project, and tag patches now decode omitted clear switches
  as `false`, so clients can send only the fields they intend to change (#89).

## [0.9.4beta] - 2026-03-16

### Changed

- Rebuilt task and project count/query paths around documented Omni Automation
  collections and native status values.
- Added single-pass filtering, early-stop paging, completion-sorted top-K
  paging, and targeted count fast paths.
- Kept plugin URL dispatch as the production transport after a corrected
  transport comparison; retained JXA as a parity and benchmark reference.

### Fixed

- Hardened list-task timeout recovery and added semantic gates, timeout
  diagnostics, and decision-safe benchmark tooling.

## [0.9.3-beta] - 2026-02-28

### Added

- Task planned-date reads and filters across the plugin, Swift API, CLI, and MCP
  schema.

## [0.9.2-beta] - 2026-02-19

### Fixed
- **Task count reliability/performance**: `get_task_counts` now prefers native OmniFocus task collections before falling back to full flattened scans, reducing timeout risk on larger databases.
- **Project task count mapping**: Ensured `list_projects(includeTaskCounts=true)` consistently returns numeric `availableTasks`, `remainingTasks`, `completedTasks`, `droppedTasks`, and `totalTasks`.

### Added
- **Regression coverage**: Added live integration tests for default/completed count parity between `get_task_counts` and `list_tasks(includeTotalCount=true)`.
- **Schema guidance improvements**: Clarified `inboxView` vs `inboxOnly` scope behavior and documented `includeTotalCount` in MCP tool schema metadata.

## [0.9.1-beta] - 2026-02-11

### Fixed
- **MCP transport stability**: Fixed critical issue where server logs written to stdout caused MCP transport disconnects. Logs now correctly route to stderr, preventing JSON-RPC stream corruption.

### Added
- **Automatic counting in list_tasks responses**: New `returnedCount` field always shows how many items are in the current response
- **Optional total count with includeTotalCount**: Set `includeTotalCount: true` in the filter to get `totalCount` (total matching items without pagination)
- **CLI support**: Added `--include-total-count` flag to `focusrelay list-tasks` command
- **Prevents LLM counting errors**: Explicit counts eliminate manual counting mistakes
- **Project completion date support**: Added `completionDate` field to projects (returned when requested)
- **Project completion filtering**: Filter projects by `completed`, `completedAfter`, `completedBefore` to find completed projects in time windows
- **Automatic sorting by completion date**: Results sorted by `completionDate` descending when filtering by completion (matches OmniFocus Completed perspective)
- **Enhanced get_task_counts**: Now supports full filtering including completion date windows for accurate time-window counts
- **Regression test**: Added test to ensure MCP logs go to stderr not stdout

### Removed
- **Removed staleThreshold**: Removed deprecated convenience filter in favor of explicit date windows


## [0.9.0-beta] - 2026-02-02

### Added
- Complete MCP server implementation
- OmniFocus Bridge plugin for automation
- Time-based task queries (morning/afternoon/evening)
- Project health tracking (isStalled, nextTask)
- Tag-based task counts
- Stale threshold filtering (7days, 30days, 90days, 180days, 270days, 365days)
- Homebrew formula for easy installation
- Comprehensive documentation

### Features
- Query tasks by due dates, defer dates, completion status
- Filter by tags, projects, duration
- Timezone detection for accurate time queries
- Single-pass filtering for performance
- Cache layer for projects and tags
- Security prompt handling for first-time users
