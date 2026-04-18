# Omni Automation Write Contract

This document defines the Omni Automation APIs and product rules that are allowed in FocusRelay v1 mutation paths.

Scope:
- Any future task or project mutation helper in `Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js`
- Any future mutation helper in `Sources/OmniFocusAutomation/OmniFocusAutomation.swift`
- Any future shared mutation core used by CLI and MCP

Workflow companion:
- [`docs/mutation-change-checklist.md`](./mutation-change-checklist.md)

Primary source:
- [OmniFocus Omni Automation index](https://omni-automation.com/omnifocus/index.html)

Relevant reference pages:
- [Database](https://omni-automation.com/omnifocus/database.html)
- [Project](https://omni-automation.com/omnifocus/project.html)
- [Task](https://omni-automation.com/omnifocus/task.html)

## Rules
- Use only documented Omni Automation APIs in production mutation paths.
- If an API or mutation pattern is not documented on the official site, do not make it part of the default write path.
- Keep CLI and MCP mutation semantics aligned to one shared contract.
- v1 mutations are homogeneous bulk only: one call, one operation kind, one patch or destination or state applied to all passed IDs.
- v1 mutations are ID-only. Name lookup remains a read-side concern.
- `update_*` is for field patches only.
- `set_*_completion` owns completion lifecycle transitions.
- `set_projects_status` owns project status transitions.
- `move_*` owns structural location changes.
- Successful mutations must invalidate cached `list_projects` and `list_tags` results before later reads.

## Locked V1 Public Surface

### Task tools
- `update_tasks`
- `set_tasks_completion`
- `move_tasks`

### Project tools
- `update_projects`
- `set_projects_status`
- `set_projects_completion`
- `move_projects`

## Shared Request Semantics

### Targeting
- Inputs target existing objects by ID only.
- A request fails validation if any referenced ID cannot be resolved.
- v1 does not support name-based mutation targeting or fuzzy matching.

### Bulk behavior
- All targets in one request receive the same operation.
- v1 does not support mixed-operation batches such as “complete these, move those, patch those others.”
- Single-item CLI and MCP commands should reuse the same bulk-capable internal models.

### Preview and verification
- `previewOnly=true` validates and resolves targets without mutating OmniFocus.
- `verify=true` performs a post-write readback using the documented read path and returns the resolved post-state.
- `returnFields` is opt-in and limits post-write payload shape.
- Mutation tools should default to compact result summaries rather than full object payloads.

### Failure semantics
- Validation failures should be reported before any mutation is attempted.
- Errors must be structured and actionable.
- v1 should prefer all-or-nothing behavior for one homogeneous request unless a later issue explicitly introduces partial success semantics.

## Allowed Documented Mutation Surfaces

### Task field patches
- `task.name`
- `task.note`
- `task.appendStringToNote(...)`
- `task.flagged`
- `task.estimatedMinutes`
- `task.dueDate`
- `task.deferDate`
- `task.addTag(...)`
- `task.addTags(...)`
- `task.removeTag(...)`

### Task lifecycle
- `task.markComplete(date)`
- `task.markIncomplete()`
- `task.active`

### Task moves
- `moveTasks(tasks, position)`
- Allowed destination shapes for v1:
  - inbox insertion locations
  - project destinations
  - parent task destinations
  - documented task child insertion locations

### Project field patches
- `project.name`
- `project.flagged`
- `project.completedByChildren`
- `project.containsSingletonActions`
- `project.sequential`
- `project.reviewInterval`
- `project.dueDate`
- `project.deferDate`
- `project.appendStringToNote(...)`
- `project.addTag(...)`
- `project.addTags(...)`
- `project.removeTag(...)`
- `project.task.<task-like property>` only when needed to implement a documented project property while keeping the public API project-shaped

### Project lifecycle
- `project.status`
- `project.markComplete(date)`
- `project.markIncomplete()`

### Project moves
- `moveSections(sections, position)`
- Allowed destination shapes for v1:
  - folder destinations
  - documented folder child insertion locations

### General deletion support
- `deleteObject(...)` is documented, but deletion is out of scope for the current v1 mutation roadmap and should not be exposed by the tools above.

## Allowed Derived Patterns
- Resolve task IDs to task objects and apply one homogeneous patch across all targets.
- Resolve project IDs to project objects and apply one homogeneous patch across all targets.
- Use `task.markComplete(...)` and `task.markIncomplete()` rather than synthesizing completion by direct date assignment.
- Use `project.markComplete(...)` and `project.markIncomplete()` rather than synthesizing completion by direct date assignment.
- Use `project.status` for project active/on-hold/dropped transitions.
- Use `moveTasks(...)` and `moveSections(...)` for structural moves instead of delete/recreate flows.
- Hide project root-task implementation details behind project-oriented public inputs and outputs.

## Out Of Scope For V1
- Mixed-operation `batch_mutate_tasks`
- Name-based target resolution for writes
- Creating new tasks, projects, folders, or tags as part of these tools
- Deleting tasks or projects
- Attachment or file-link mutation
- Notification mutation
- Repetition-rule mutation
- Project review date direct mutation using undocumented surfaces
- Tag reordering as part of update tools
- Placement controls beyond documented move destinations unless a later issue validates a concrete use case
- `plannedDate` writes

## Special Notes And Caveats

### Repeating completion semantics
- `markComplete(...)` on repeating tasks and projects can clone the repeated item and mark that clone complete.
- `set_*_completion` must treat repeating items as lifecycle operations that require post-write verification rather than assuming a simple boolean flip.

### Project root-task details
- Omni Automation documents that many “task-like” project properties are ultimately held on the project’s root task.
- FocusRelay may use that documented implementation detail internally, but the public tool surface should remain project-shaped.

### Planned date writes
- The task docs currently describe `plannedDate` with mixed signals about setter support and migration requirements.
- Because the documentation is ambiguous and the current roadmap does not need it, planned-date writes stay out of scope for v1.

## Review Checklist
Before merging mutation-path changes, verify:
- The change started from [`docs/mutation-change-checklist.md`](./mutation-change-checklist.md), not from ad hoc schema choices.
- Every OmniFocus property, function, and move API used by the mutation path appears on the official docs pages above.
- The public tool shape still matches the locked v1 surface in this document.
- Bulk semantics remain homogeneous.
- Preview, verify, and `returnFields` behavior remain consistent across CLI and MCP.
- Successful writes invalidate cached `list_projects` and `list_tags` results.
- Repeating-item completion behavior is covered by tests before merge.
