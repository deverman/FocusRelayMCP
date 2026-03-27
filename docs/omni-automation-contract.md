# Omni Automation Contract

This document defines the Omni Automation APIs that are allowed in FocusRelay query engines.

Scope:
- `Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js`
- `Sources/OmniFocusAutomation/OmniFocusAutomation.swift`
- Any future query-engine helper that reads OmniFocus data

Workflow companion:
- [`docs/query-change-checklist.md`](./query-change-checklist.md)

Primary source:
- [OmniFocus Omni Automation index](https://omni-automation.com/omnifocus/index.html)

Relevant reference pages:
- [Database](https://omni-automation.com/omnifocus/database.html)
- [Project](https://omni-automation.com/omnifocus/project.html)
- [Task](https://omni-automation.com/omnifocus/task.html)

## Rules
- Use only documented Omni Automation APIs in production query paths.
- If an API or collection is not documented on the official site, do not use it in core query logic.
- Prefer documented collection enumeration plus documented status filtering over convenience pools.
- Keep plugin and JXA query semantics aligned to the same documented model.

## Allowed documented surfaces

### Database enumeration
- `flattenedTasks`
- `flattenedProjects`
- `flattenedFolders`
- `inbox`
- `projects`
- `tags`

### Project enumeration and status
- `project.flattenedTasks`
- `project.tasks`
- `project.status`
- `project.task`
- `project.tags`
- `project.id`
- `project.name`

### Task enumeration and status
- `task.taskStatus`
- `task.containingProject`
- `task.parent`
- `task.tags`
- `task.id`
- `task.name`
- `task.note`
- `task.flagged`
- `task.completed`
- `task.completionDate`
- `task.dueDate`
- `task.deferDate`
- `task.plannedDate`
- `task.estimatedMinutes`
- `task.inInbox`

## Allowed derived patterns
- Enumerate `flattenedTasks` and filter by `task.taskStatus`.
- Enumerate `flattenedProjects` and filter by `project.status`.
- Resolve project-scoped task queries from `project.flattenedTasks`.
- Derive remaining/available/completed views from documented status values.

## Banned undocumented core-query patterns
Do not use these as the primary production query path unless the official docs explicitly document them in the future.

- `project.remainingTasks`
- `project.availableTasks`
- database/global `remainingTasks`
- database/global `availableTasks`
- Any query path that depends on undocumented convenience collections for correctness

## Review checklist
Before merging query-engine changes, verify:
- The change started from [`docs/query-change-checklist.md`](./query-change-checklist.md), not from a benchmark result alone.
- Every OmniFocus collection/property used by the query path appears on the official docs pages above.
- `task.taskStatus` is the source of truth for task state.
- `project.status` is the source of truth for project state.
- Boundary semantics are covered by tests before benchmarking.
- Benchmarks are not run unless parity and count-contract gates pass.
