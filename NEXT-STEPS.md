# FocusRelayMCP Next Steps

This file tracks planned work and completion status.

## Completed

- [x] Bridge mode working end-to-end (health check, inbox, projects, tags)
- [x] Inbox filtering aligns with OmniFocus "Available" view (parent dropped/completed excluded)
- [x] IPC cleanup for stale files + timeout cleanup

## In Progress

- [x] Decide final defaults for inboxView and availableOnly behavior
- [x] Add `get_task` (bridge + MCP)
- [x] Add `get_task_counts` (bridge + MCP)

## Next Up

- [x] Add paging tests for projects/tags in bridge mode
- [x] Add lock file cleanup policy in plug-in (optional)
- [x] Document bridge install/test flow in README (short checklist)
- [ ] Add completion date support for tasks (return `completedDate` and allow filtering by completed time)
- [ ] After next release, update the Homebrew tap to the new tarball/SHA that includes the `focusrelay` binary (`focusrelay serve` for MCP).

## Backlog (Post PR6 Hardening)

- [ ] Clarify inbox filter contract (`inboxView` vs `inboxOnly`)
  - Problem: `inboxView` currently changes only view mode, not scope; inbox scope requires `inboxOnly=true`.
  - Candidate fix: add explicit `scope`/`taskScope` field, or reject `inboxView` without inbox scope with a clear error.
  - Acceptance: MCP schema/docs/tests clearly enforce one contract; no ambiguous "inbox" behavior in client prompts.

- [ ] Align project "available" counts with OmniFocus availability semantics
  - Problem: project counts currently treat only `Task.Status.Available`/`Task.Status.Next` as available.
  - Candidate fix: use shared availability helper semantics (include `DueSoon`/`Overdue` where appropriate) and verify against OmniFocus expectations.
  - Acceptance: `list_projects(includeTaskCounts=true)` available counts are consistent with task-level availability rules.

- [ ] Stabilize live bridge transport under repeated calls
  - Problem: intermittent timeouts and IPC/URL dispatch failures in live test mode.
  - Details: see `docs/timeout-concurrency-investigation-2026-02-19.md`.
  - Acceptance: repeatable live bridge test runs with materially reduced timeout and interrupted-system-call failures.

- [ ] Add guidance for OmniFocus count freshness (`cleanUp()` caveat)
  - Problem: OmniFocus collection counts (especially tag/task aggregate counts) can be stale immediately after edits unless the database is cleaned up.
  - Candidate fix: document escalation path (detect suspected stale counts -> optionally run `cleanUp()` manually/off critical path -> re-query), and add a debug endpoint/checklist.
  - Acceptance: stale-count reports have a deterministic runbook; no automatic `cleanUp()` on normal read paths.

- [ ] Add `focusrelay --version` command and versioning workflow
  - Problem: users cannot quickly verify installed binary version; release version currently comes from Git tags.
  - Candidate fix: add top-level `--version` output wired to build metadata, and define release-time injection strategy (e.g., compile-time constant from tag or generated source during CI).
  - Research: review how popular Swift CLI tools handle semantic version reporting with tag-based releases.
  - Acceptance: `focusrelay --version` returns a predictable value for local builds and release builds, with documented behavior.

- [ ] Execute Query Engine V2 refactor program (breaking cleanup + SOLID alignment)
  - Plan doc: `docs/refactor-query-engine-v2-plan.md`
  - Delivery model: incremental PRs on long-term branch (`refactor/query-engine-v2`), no immediate release tag.
  - Key outcomes: unified list/count query pipeline, explicit scope/view contract, deterministic validation errors, stronger parity tests.

## Backlog (Query Capability Gaps vs OmniFocus-MCP)

### High Usage

- [ ] Add custom perspective support (query saved OmniFocus perspectives directly)
  - Issue: `#10` https://github.com/deverman/FocusRelayMCP/issues/10
  - Why this category: custom perspectives are a primary power-user workflow (Today/Next/Errands/Waiting/Someday patterns) and reduce prompt complexity.
  - Preferred design: minimize new tools by adding one discovery tool (`list_perspectives`) and reusing existing query tools (`list_tasks`, `list_projects`, `get_task_counts`) with an optional `perspective` filter.
  - Native approach: use OmniAutomation `Perspective.Custom/BuiltIn` APIs for listing/resolution and execute queries in perspective context (no custom rule parser for MVP).
  - User stories:
    - As a user, I want to list my saved custom perspectives and query one by name/id.
    - As a user, I want perspective task counts that match what I see in OmniFocus.
  - Likely prompts:
    - "List my custom perspectives."
    - "Show tasks from my `Today` perspective."
    - "Get counts for my `Waiting` perspective."
    - "Show first 20 tasks from `On-The-Go` with dueDate and tagNames."

- [ ] Add task status filter support (`Next`, `Blocked`, `DueSoon`, `Overdue`, `Available`, `Completed`, `Dropped`)
  - Why this category: common daily planning and triage workflows rely on status-specific views.
  - User stories:
    - As a user, I want only `Next` actions so I can start work quickly.
    - As a user, I want only `Blocked` tasks so I can unblock dependencies.
    - As a user, I want `Overdue` and `DueSoon` tasks for urgency triage.
  - Likely prompts:
    - "Show me my next actions."
    - "What tasks are blocked right now?"
    - "What is overdue or due soon today?"

- [ ] Add configurable sorting controls for task/project queries (`sortBy`, `sortOrder`)
  - Why this category: users frequently ask to prioritize by due date, recency, or estimate.
  - User stories:
    - As a user, I want tasks sorted by due date ascending to plan execution order.
    - As a user, I want tasks sorted by last modified date to review stale items.
  - Likely prompts:
    - "Show my available tasks sorted by due date."
    - "List uncompleted tasks sorted by last modified date."

- [ ] Add folder-aware query support (query folders directly and filter tasks/projects by folder)
  - Why this category: folder context is a common top-level planning dimension in OmniFocus.
  - User stories:
    - As a user, I want to list my folder structure to audit organization.
    - As a user, I want tasks in a specific folder for context-based planning.
  - Likely prompts:
    - "Show me all folders in OmniFocus."
    - "What are my next actions in the Work folder?"

### Medium Usage

- [ ] Add `hasNote` filtering for tasks/projects
  - Why this category: useful for review and quality checks, but less universal than status/due workflows.
  - User stories:
    - As a user, I want tasks without notes so I can fill missing context.
    - As a user, I want tasks with notes to quickly review detailed items.
  - Likely prompts:
    - "Show tasks with no notes."
    - "Find available tasks that include notes."

- [ ] Add exact-day shorthand filters (`dueOn`, `deferOn`) in addition to timestamp ranges
  - Why this category: common phrasing from users ("due tomorrow"), easier than constructing ISO timestamps.
  - User stories:
    - As a user, I want tasks due tomorrow without manually building date ranges.
    - As a user, I want tasks deferred until today for morning planning.
  - Likely prompts:
    - "What is due tomorrow?"
    - "Show tasks that become available today."

### Medium-to-Growing Usage

- [ ] Add planned date support (`plannedDate` field + planned filters like `plannedWithin`/`plannedOn`)
  - Why this category: increasing usage with OmniFocus planned-date workflows, but not universal yet.
  - User stories:
    - As a user, I want tasks planned for today to build my daily agenda.
    - As a user, I want tasks planned this week to do weekly capacity planning.
  - Likely prompts:
    - "What tasks are planned for today?"
    - "Show everything planned in the next 7 days."

### Low-to-Medium Usage

- [ ] Add parent/child graph query fields for advanced task hierarchy analysis (`parentId`, `childIds`, `hasChildren`)
  - Why this category: high value for power users and automation, lower demand for day-to-day users.
  - User stories:
    - As a power user, I want parent/child IDs to detect broken or overly deep task trees.
    - As an automation user, I want hierarchy metadata for structured exports.
  - Likely prompts:
    - "Show tasks with subtasks and include parent/child IDs."
    - "Find parent tasks that have too many children."
