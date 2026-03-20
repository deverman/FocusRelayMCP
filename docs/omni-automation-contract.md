# Omni Automation Contract

This document defines the Omni Automation APIs that are allowed in FocusRelay query engines.

Scope:

- `Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js`
- `Sources/OmniFocusAutomation/OmniFocusAutomation.swift`
- Any future query-engine helper that reads OmniFocus data

Primary source:

- [OmniFocus Omni Automation index](https://omni-automation.com/omnifocus/index.html)

Relevant reference pages:

- [Database](https://omni-automation.com/omnifocus/database.html)
- [Project](https://omni-automation.com/omnifocus/project.html)
- [Task](https://omni-automation.com/omnifocus/task.html)
- [Tag](https://omni-automation.com/omnifocus/tag.html)

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

### Tag enumeration and status

- `tag.id`
- `tag.name`
- `tag.status`
- `tag.tasks`
- `tag.flattenedTasks`
- `tag.children`
- `tag.parent`

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
- Enumerate `flattenedTags`, or fall back to root `tags` plus recursive `tag.children` traversal when `flattenedTags` is unavailable.
- Derive tag available/remaining/total counts from tag-scoped task enumeration plus `task.taskStatus`.
- Derive remaining/available/completed views from documented status values.

## Contract boundary for project health extras

- `project.nextTask` and `project.containsSingletonActions` may be available on some OmniFocus builds, but FocusRelay does not treat them as contract-backed core-query fields.
- If a caller explicitly requests those extras on a build that returns `undefined`, the query path must fail explicitly instead of silently coercing them to `nil` or `false`.
- `isStalled` is a best-effort derived extra built from those fields and is excluded from benchmark-gate and parity matrices.

## Banned undocumented core-query patterns

Do not use these as the primary production query path unless the official docs explicitly document them in the future.

- `project.remainingTasks`
- `project.availableTasks`
- database/global `remainingTasks`
- database/global `availableTasks`
- Any query path that depends on undocumented convenience collections for correctness

## Review checklist

Before merging query-engine changes, verify:

- Every OmniFocus collection/property used by the query path appears on the official docs pages above.
- `task.taskStatus` is the source of truth for task state.
- `project.status` is the source of truth for project state.
- `list_projects` benchmark and parity scenarios use only contract-backed fields (`id`, `name`, `hasChildren`) plus documented task-derived counts.
- Benchmarks are not run unless parity and count-contract gates pass.
