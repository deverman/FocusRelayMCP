# Mutation Workflows For CLI And MCP

FocusRelay v1 write tools are designed to be low-token, deterministic, and easy for AI agents to route correctly. The core split is:

- Use `update_*` for field patches.
- Use `set_*_completion` for complete or uncomplete lifecycle changes.
- Use `set_projects_status` for project active, on-hold, or dropped state.
- Use `move_*` for structural moves.

## Core Rules

- Mutations target IDs only. Use read tools first to find IDs; do not mutate by name.
- Bulk calls are homogeneous. One call applies one shared patch, state, or destination to every ID.
- Single-item writes use the same tools as bulk writes with one ID.
- Use `previewOnly=true` before risky or bulk writes.
- Use `verify=true` for real writes when the agent needs readback confidence.
- Use `returnFields` to keep responses compact.
- Do not mix unrelated writes in one call. `batch_mutate_tasks` is intentionally out of scope for v1.

## Tool Routing

| Intent | MCP tool | CLI command |
| --- | --- | --- |
| Rename, flag, note, due/defer date, estimate, or task tags | `update_tasks` | `focusrelay update-tasks` |
| Complete or uncomplete tasks | `set_tasks_completion` | `focusrelay set-tasks-completion` |
| Move tasks to inbox, project, or parent task | `move_tasks` | `focusrelay move-tasks` |
| Rename, flag, note, due/defer date, sequential, or review interval | `update_projects` | `focusrelay update-projects` |
| Set project active, on-hold, or dropped | `set_projects_status` | `focusrelay set-projects-status` |
| Complete or uncomplete projects | `set_projects_completion` | `focusrelay set-projects-completion` |
| Move projects to a folder or root library | `move_projects` | `focusrelay move-projects` |

## Read Before Write

Use this pattern for both CLI and MCP:

1. Read candidates with only the fields needed to identify the target.
2. Ask the user to confirm if the target is ambiguous or the write is broad.
3. Preview the mutation with the target IDs.
4. Execute with `verify=true` and minimal `returnFields`.

CLI example:

```bash
focusrelay list-tasks --search "intro call" --fields id,name,projectName,tagNames --limit 5
focusrelay update-tasks task-1 --flagged true --preview-only --return-fields id,name,flagged
focusrelay update-tasks task-1 --flagged true --verify --return-fields id,name,flagged
```

MCP example:

```json
{
  "tool": "update_tasks",
  "arguments": {
    "targetIDs": ["task-1"],
    "taskPatch": { "flagged": true },
    "previewOnly": true,
    "returnFields": ["id", "name", "flagged"]
  }
}
```

## Low-Token Output

Default mutation responses are compact. Add `returnFields` only when the next step needs those fields.

Good field sets:

- Task patch: `["id", "name", "flagged", "dueDate", "deferDate"]`
- Task completion: `["id", "name", "completed", "completionDate"]`
- Task move: `["id", "name", "projectID", "projectName"]`
- Project patch/status: `["id", "name", "status", "flagged"]`
- Project completion: `["id", "name", "status", "completionDate"]`

Avoid returning notes unless the user needs note content.

## CLI Examples

### Task Patches

Set and clear fields:

```bash
focusrelay update-tasks task-1 task-2 --flagged true --verify --return-fields id,name,flagged
focusrelay update-tasks task-1 --due-date 2026-04-18T16:00:00Z --verify --return-fields id,name,dueDate
focusrelay update-tasks task-1 --clear-due-date --verify --return-fields id,name,dueDate
focusrelay update-tasks task-1 --estimated-minutes 30 --verify --return-fields id,name,estimatedMinutes
```

Rename and note changes:

```bash
focusrelay update-tasks task-1 --name "Send intro call notes" --verify --return-fields id,name
focusrelay update-tasks task-1 --note-append "Follow up after call." --verify --return-fields id,name
```

Tags use tag IDs:

```bash
focusrelay list-tags --include-task-counts
focusrelay update-tasks task-1 --tag-add tag-1 --verify --return-fields id,name,tagIDs,tagNames
focusrelay update-tasks task-1 --tag-remove tag-1 --verify --return-fields id,name,tagIDs,tagNames
```

### Task Completion

```bash
focusrelay set-tasks-completion task-1 task-2 --state completed --verify --return-fields id,name,completed,completionDate
focusrelay set-tasks-completion task-1 --state active --verify --return-fields id,name,completed,completionDate
```

For repeating tasks, OmniFocus may complete an occurrence and advance the original task. Use `verify=true` and read the returned message.

### Task Moves

```bash
focusrelay move-tasks task-1 --destination-kind inbox --verify --return-fields id,name,projectID,projectName
focusrelay move-tasks task-1 task-2 --destination-kind project --destination-id project-1 --verify --return-fields id,name,projectID,projectName
focusrelay move-tasks task-1 --destination-kind parent_task --destination-id parent-task-1 --position ending --verify --return-fields id,name
```

### Project Patches

```bash
focusrelay update-projects project-1 --flagged true --verify --return-fields id,name,flagged
focusrelay update-projects project-1 --due-date 2026-04-30T16:00:00Z --verify --return-fields id,name,dueDate
focusrelay update-projects project-1 --sequential true --verify --return-fields id,name
focusrelay update-projects project-1 --review-steps 1 --review-unit weeks --verify --return-fields id,name,reviewInterval
```

### Project Status And Completion

Use status for active/on-hold/dropped. Use completion for done/active lifecycle.

```bash
focusrelay set-projects-status project-1 --status on_hold --verify --return-fields id,name,status
focusrelay set-projects-status project-1 --status active --verify --return-fields id,name,status
focusrelay set-projects-completion project-1 --state completed --verify --return-fields id,name,status,completionDate
focusrelay set-projects-completion project-1 --state active --verify --return-fields id,name,status,completionDate
```

### Project Moves

Move to a known folder ID, or omit `--destination-id` to move to the root library.

```bash
focusrelay move-projects project-1 --destination-kind folder --destination-id folder-1 --verify --return-fields id,name,status
focusrelay move-projects project-1 --destination-kind folder --verify --return-fields id,name,status
```

V1 does not include a public folder discovery tool. Agents must not invent folder IDs; use `move_projects` only when the destination folder ID is known, or omit `destinationID` for a root-library move.

## MCP Examples

The JSON blocks below are MCP tool arguments. Call the tool named in each heading.

### Bulk Task Update

```json
{
  "targetIDs": ["task-1", "task-2"],
  "taskPatch": {
    "flagged": true,
    "dueDate": "2026-04-18T16:00:00Z"
  },
  "previewOnly": true,
  "returnFields": ["id", "name", "flagged", "dueDate"]
}
```

Call `update_tasks` again with `"previewOnly": false` and `"verify": true` after confirmation.

### Complete Tasks

```json
{
  "targetIDs": ["task-1", "task-2"],
  "completion": { "state": "completed" },
  "verify": true,
  "returnFields": ["id", "name", "completed", "completionDate"]
}
```

### Move Tasks To A Project

```json
{
  "targetIDs": ["task-1", "task-2"],
  "move": {
    "destinationKind": "project",
    "destinationID": "project-1",
    "position": "ending"
  },
  "verify": true,
  "returnFields": ["id", "name", "projectID", "projectName"]
}
```

### Update Project Status

```json
{
  "targetIDs": ["project-1"],
  "projectStatus": { "status": "on_hold" },
  "verify": true,
  "returnFields": ["id", "name", "status"]
}
```

### Move Projects

```json
{
  "targetIDs": ["project-1"],
  "move": {
    "destinationKind": "folder",
    "destinationID": "folder-1",
    "position": "ending"
  },
  "verify": true,
  "returnFields": ["id", "name", "status"]
}
```

For root-library moves, omit `destinationID`.

## Safety Notes

- Prefer preview for every bulk write.
- Ask for confirmation before real writes when the user has not explicitly approved the exact IDs and operation.
- Do not use `update_tasks` to complete tasks; use `set_tasks_completion`.
- Do not use `update_projects` to complete, drop, or move projects; use the lifecycle/status/move tools.
- Do not mutate by name. Names are only for read-side discovery and user confirmation.
- Do not attempt create/delete/repeat-rule/planned-date writes in v1.
