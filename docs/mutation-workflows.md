# AI-Optimized Mutation Workflows

This guide documents the v1 FocusRelay write surface for CLI and MCP clients.
It is designed for low-token AI workflows: read only the IDs and fields you need,
preview the intended write, then mutate with verification when the user approves.

## V1 Rules

- Mutations target IDs only. Do not mutate by name.
- Bulk writes are homogeneous: one operation kind, one shared patch/state/destination, many IDs.
- `update_*` tools edit fields only.
- `set_*_completion` tools own completion lifecycle transitions.
- `set_projects_status` owns project status transitions.
- `move_*` tools own structural moves.
- Mixed-operation batch mutation is intentionally out of scope for v1.
- Task queries are always fresh. Project and tag catalog caches are invalidated after successful non-preview writes.

## Shared Safety Options

Use these on every write workflow:

- `previewOnly`: validates targets and shared operation without mutating OmniFocus.
- `verify`: reads back the final state after mutation and reports verification failures.
- `returnFields`: returns only selected fields in per-item results to keep output compact.

Recommended default for AI clients:

```json
{
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name"]
}
```

After the user confirms the preview, send the same request with `previewOnly: false`.

## Tool Selection

| Intent | MCP tool | CLI command |
| --- | --- | --- |
| Edit task fields | `update_tasks` | `focusrelay update-tasks` |
| Complete or uncomplete tasks | `set_tasks_completion` | `focusrelay set-tasks-completion` |
| Move/reparent tasks | `move_tasks` | `focusrelay move-tasks` |
| Edit project fields | `update_projects` | `focusrelay update-projects` |
| Change project active/on-hold/dropped status | `set_projects_status` | `focusrelay set-projects-status` |
| Complete or reactivate projects | `set_projects_completion` | `focusrelay set-projects-completion` |
| Move projects to folder/root library | `move_projects` | `focusrelay move-projects` |

Do not use `update_tasks` or `update_projects` for completion, status, or move behavior.

## Read Before Write

Use the smallest read that can identify the correct target IDs:

```bash
focusrelay list-tasks --fields id,name --limit 20 --inbox-only true
focusrelay list-projects --fields id,name,status --status active --limit 20
focusrelay list-tags --fields id,name --limit 50
```

For MCP clients, request the same compact fields:

```json
{
  "fields": ["id", "name"],
  "page": { "limit": 20 }
}
```

When a mutation needs tag, project, or parent-task IDs, read those IDs first.
Do not ask the model to infer IDs from names already shown in prior conversation unless
the ID is still visible in context. Folder IDs are not exposed by a dedicated v1
read tool yet; use `move_projects` folder moves only when the folder ID is already
known, or omit `destinationID` to move projects to the root library.

## Task Field Patches

Use `update_tasks` for task field edits only.

Supported v1 fields:

- `name`
- `note`
- `noteAppend`
- `flagged`
- `estimatedMinutes`
- `dueDate`
- `clearDueDate`
- `deferDate`
- `clearDeferDate`
- `tags.add`
- `tags.remove`
- `tags.set`
- `tags.clear`

CLI preview:

```bash
focusrelay update-tasks task-id-1 task-id-2 \
  --flagged true \
  --due-date 2026-04-18T12:00:00Z \
  --preview-only \
  --verify \
  --return-fields id,name,flagged,dueDate
```

MCP preview:

```json
{
  "targetIDs": ["task-id-1", "task-id-2"],
  "taskPatch": {
    "flagged": true,
    "dueDate": "2026-04-18T12:00:00Z"
  },
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name", "flagged", "dueDate"]
}
```

To clear dates, use explicit clear flags:

```bash
focusrelay update-tasks task-id-1 --clear-due-date --verify --return-fields id,name,dueDate
```

## Task Completion Lifecycle

Use `set_tasks_completion` for complete and uncomplete.

CLI:

```bash
focusrelay set-tasks-completion task-id-1 task-id-2 \
  --state completed \
  --preview-only \
  --verify \
  --return-fields id,name,completed,completionDate
```

MCP:

```json
{
  "targetIDs": ["task-id-1", "task-id-2"],
  "completion": { "state": "completed" },
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name", "completed", "completionDate"]
}
```

Use `state: "active"` to uncomplete tasks. Repeating tasks may advance to the next
occurrence; the result message reports that behavior.

## Task Moves

Use `move_tasks` for inbox, project, and parent-task moves.

CLI:

```bash
focusrelay move-tasks task-id-1 task-id-2 \
  --destination-kind project \
  --destination-id project-id \
  --position ending \
  --preview-only \
  --verify \
  --return-fields id,name,projectID,projectName
```

MCP:

```json
{
  "targetIDs": ["task-id-1", "task-id-2"],
  "move": {
    "destinationKind": "project",
    "destinationID": "project-id",
    "position": "ending"
  },
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name", "projectID", "projectName"]
}
```

Destination kinds:

- `inbox`: omit `destinationID`.
- `project`: set `destinationID` to a project ID.
- `parent_task`: set `destinationID` to a parent task ID.

## Project Field Patches

Use `update_projects` for project field edits only.

Supported v1 fields:

- `name`
- `note`
- `noteAppend`
- `flagged`
- `dueDate`
- `clearDueDate`
- `deferDate`
- `clearDeferDate`
- `sequential`
- `reviewInterval`

CLI:

```bash
focusrelay update-projects project-id-1 \
  --note-append "Reviewed by AI assistant." \
  --review-steps 1 \
  --review-unit weeks \
  --preview-only \
  --verify \
  --return-fields id,name,note,reviewInterval
```

MCP:

```json
{
  "targetIDs": ["project-id-1"],
  "projectPatch": {
    "noteAppend": "Reviewed by AI assistant.",
    "reviewInterval": { "steps": 1, "unit": "weeks" }
  },
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name", "note", "reviewInterval"]
}
```

## Project Status

Use `set_projects_status` for active/on-hold/dropped transitions.

CLI:

```bash
focusrelay set-projects-status project-id-1 \
  --status on_hold \
  --preview-only \
  --verify \
  --return-fields id,name,status
```

MCP:

```json
{
  "targetIDs": ["project-id-1"],
  "projectStatus": { "status": "on_hold" },
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name", "status"]
}
```

Supported statuses: `active`, `on_hold`, `dropped`.

## Project Completion Lifecycle

Use `set_projects_completion` for complete and reactivate.

CLI:

```bash
focusrelay set-projects-completion project-id-1 \
  --state completed \
  --preview-only \
  --verify \
  --return-fields id,name,status,completionDate
```

MCP:

```json
{
  "targetIDs": ["project-id-1"],
  "completion": { "state": "completed" },
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name", "status", "completionDate"]
}
```

Use `state: "active"` to reactivate projects. Repeating projects may advance to the
next occurrence; the result message reports that behavior.

## Project Moves

Use `move_projects` to move projects to a folder or back to the root library.

Move to a folder:

```bash
focusrelay move-projects project-id-1 \
  --destination-kind folder \
  --destination-id folder-id \
  --position ending \
  --preview-only \
  --verify \
  --return-fields id,name,status
```

Move to the root library by omitting `destinationID`:

```bash
focusrelay move-projects project-id-1 \
  --destination-kind folder \
  --position ending \
  --preview-only \
  --verify \
  --return-fields id,name,status
```

MCP folder move:

```json
{
  "targetIDs": ["project-id-1"],
  "move": {
    "destinationKind": "folder",
    "destinationID": "folder-id",
    "position": "ending"
  },
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name", "status"]
}
```

MCP root-library move:

```json
{
  "targetIDs": ["project-id-1"],
  "move": {
    "destinationKind": "folder",
    "position": "ending"
  },
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name", "status"]
}
```

## Low-Token AI Patterns

Prefer this sequence:

1. Read candidates with `fields: ["id", "name"]` and a small `limit`.
2. Ask the user to confirm the intended target names if the write is destructive or bulk.
3. Run the mutation with `previewOnly: true`, `verify: true`, and minimal `returnFields`.
4. Summarize the preview count and target names.
5. After confirmation, rerun with `previewOnly: false`.
6. Report only failed items and a compact success summary.

Avoid this sequence:

1. Reading all projects, tags, tasks, notes, and counts up front.
2. Sending long notes back in `returnFields` unless the user explicitly asked for note content.
3. Combining field edits, lifecycle changes, and moves in one conceptual instruction.

## Out Of Scope In V1

- Name-based mutation targeting.
- Mixed `batch_mutate_tasks` operations.
- Creating tasks, projects, tags, or folders.
- Planned-date writes.
- Project tag mutations.
- Folder creation or folder rename/delete.
