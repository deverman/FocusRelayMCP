# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
