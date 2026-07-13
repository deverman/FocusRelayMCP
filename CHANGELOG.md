# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Release packaging now produces and verifies the `focusrelay` binary, plugin,
  archive, checksum, prerelease metadata, and tag-derived version consistently.
- Homebrew formula ownership now points exclusively to the external
  `deverman/homebrew-focus-relay` tap.

### Fixed

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
- Catalog cache keys now distinguish filter state.
- Bridge timeout diagnostics now report pickup state and stranded redispatch
  information.
- CI artifact upload and manual/tag release version selection now fail clearly
  instead of silently publishing incomplete assets.

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


## [1.0.0] - 2026-01-31

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
