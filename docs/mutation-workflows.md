# Mutation Workflows For CLI And MCP

FocusRelay exposes two edit commands for existing OmniFocus items:

- `edit_tasks` / `focusrelay edit-tasks`
- `edit_projects` / `focusrelay edit-projects`

Every request identifies existing items by ID, declares one explicit operation,
and supplies exactly one matching payload. One call applies the same operation
and payload to every target ID.

## Core Rules

- Use read tools first to resolve names to IDs. Do not mutate by name.
- Use `previewOnly=true` before risky or broad writes.
- Use `verify=true` when post-write readback matters.
- Use compact `returnFields` for only the state needed next.
- Do not combine field, lifecycle, status, or move payloads in one request.
- Use task `set_status` for drop/restore. Never translate drop, discard,
  abandon, or cancel into task completion.
- Repeating task drops require `recurrenceScope=occurrence` or `series`;
  non-repeating drops reject that field as irrelevant.

## Operation Routing

| Intent | Tool | Operation | Matching payload |
| --- | --- | --- | --- |
| Change task fields or tags | `edit_tasks` | `update` | `taskPatch` |
| Drop or restore tasks | `edit_tasks` | `set_status` | `taskStatus` |
| Complete or reopen tasks | `edit_tasks` | `set_completion` | `completion` |
| Move tasks | `edit_tasks` | `move` | `move` |
| Change project fields | `edit_projects` | `update` | `projectPatch` |
| Mark active or on-hold projects reviewed | `edit_projects` | `update` | `projectPatch.reviewedNow=true` |
| Activate, hold, or drop projects | `edit_projects` | `set_status` | `projectStatus` |
| Complete or reopen projects | `edit_projects` | `set_completion` | `completion` |
| Move projects | `edit_projects` | `move` | `move` |

Use `list_folders` before a project folder move when the destination ID is not
already known. Omit `destinationID` to move a project to the root library.

## Read Before Write

1. Read only the fields needed to identify candidates.
2. Ask the user to disambiguate when multiple items could match.
3. Preview the exact IDs and operation when the write is risky or broad.
4. Execute with `verify=true` and compact `returnFields`.

```bash
focusrelay list-tasks --search "intro call" --fields id,name,projectName --limit 5
focusrelay edit-tasks task-1 --operation update --flagged true --preview-only --return-fields id,name,flagged
focusrelay edit-tasks task-1 --operation update --flagged true --verify --return-fields id,name,flagged

focusrelay list-projects --search "drop test" --status all --fields id,name,status --limit 5
focusrelay edit-projects project-1 --operation set_status --status dropped --preview-only --return-fields id,name,status
focusrelay edit-projects project-1 --operation set_status --status dropped --verify --return-fields id,name,status
```

Project search matches a trimmed, case-insensitive literal substring against
project names only. Follow `nextCursor` while it is present, disambiguate
multiple matches, and pass only the resolved stable IDs to `edit_projects`.

Equivalent MCP call:

```json
{
  "tool": "edit_tasks",
  "arguments": {
    "operation": "update",
    "targetIDs": ["task-1"],
    "taskPatch": { "flagged": true },
    "verify": true,
    "returnFields": ["id", "name", "flagged"]
  }
}
```

## CLI Examples

### Tasks

```bash
focusrelay edit-tasks task-1 task-2 --operation update --estimated-minutes 30 --verify --return-fields id,name,estimatedMinutes
focusrelay edit-tasks task-1 --operation update --tag-add tag-1 --verify --return-fields id,name,tagIDs,tagNames
focusrelay edit-tasks task-1 --operation set_status --status dropped --verify --return-fields id,name,taskStatus,dropDate,completionDate
focusrelay edit-tasks repeating-task-1 --operation set_status --status dropped --recurrence-scope occurrence --verify --return-fields id,name,taskStatus,dropDate,completionDate
focusrelay edit-tasks task-1 --operation set_status --status active --verify --return-fields id,name,taskStatus,dropDate,completionDate
focusrelay edit-tasks task-1 --operation set_completion --state completed --verify --return-fields id,name,completed,completionDate
focusrelay edit-tasks task-1 --operation set_completion --state active --verify --return-fields id,name,completed,completionDate
focusrelay edit-tasks task-1 --operation move --destination-kind inbox --verify --return-fields id,name,projectID
focusrelay edit-tasks task-1 --operation move --destination-kind project --destination-id project-1 --position ending --verify --return-fields id,name,projectID,projectName
```

### Projects

```bash
focusrelay edit-projects project-1 --operation update --sequential true --verify --return-fields id,name
focusrelay edit-projects project-1 --operation update --reviewed-now --preview-only --return-fields id,name,status,lastReviewDate,nextReviewDate,reviewInterval
focusrelay edit-projects project-1 --operation update --reviewed-now --verify --return-fields id,name,status,lastReviewDate,nextReviewDate,reviewInterval
focusrelay edit-projects project-1 --operation set_status --status on_hold --verify --return-fields id,name,status
focusrelay edit-projects project-1 --operation set_status --status dropped --verify --return-fields id,name,status
focusrelay edit-projects project-1 --operation set_completion --state completed --verify --return-fields id,name,status,completionDate
focusrelay edit-projects project-1 --operation set_completion --state active --verify --return-fields id,name,status,completionDate
focusrelay edit-projects project-1 --operation move --destination-kind folder --destination-id folder-1 --verify --return-fields id,name,status
focusrelay edit-projects project-1 --operation move --destination-kind folder --verify --return-fields id,name,status
```

## MCP Examples

Drop a non-repeating task without recording completion:

```json
{
  "operation": "set_status",
  "targetIDs": ["task-1"],
  "taskStatus": { "status": "dropped" },
  "previewOnly": true,
  "verify": true,
  "returnFields": ["id", "name", "taskStatus", "dropDate", "completionDate"]
}
```

Complete tasks:

```json
{
  "operation": "set_completion",
  "targetIDs": ["task-1", "task-2"],
  "completion": { "state": "completed" },
  "verify": true,
  "returnFields": ["id", "name", "completed", "completionDate"]
}
```

Move tasks to a project:

```json
{
  "operation": "move",
  "targetIDs": ["task-1"],
  "move": {
    "destinationKind": "project",
    "destinationID": "project-1",
    "position": "ending"
  },
  "verify": true
}
```

Put a project on hold:

```json
{
  "operation": "set_status",
  "targetIDs": ["project-1"],
  "projectStatus": { "status": "on_hold" },
  "verify": true,
  "returnFields": ["id", "name", "status"]
}
```

Mark an active or on-hold project reviewed:

```json
{
  "operation": "update",
  "targetIDs": ["project-1"],
  "projectPatch": { "reviewedNow": true },
  "verify": true,
  "returnFields": ["id", "name", "status", "lastReviewDate", "nextReviewDate", "reviewInterval"]
}
```

`reviewedNow` must be the only project patch field. FocusRelay preflights the
whole batch, uses one request-level review timestamp, preserves each review
interval, and lets OmniFocus calculate each next review date.

Move a project to a folder:

```json
{
  "operation": "move",
  "targetIDs": ["project-1"],
  "move": {
    "destinationKind": "folder",
    "destinationID": "folder-1",
    "position": "ending"
  },
  "verify": true
}
```

## Breaking Migration

There are no compatibility aliases. Add the discriminator and keep the former
payload unchanged:

| Removed MCP tool | Replacement MCP arguments | Removed CLI command | Replacement CLI example |
| --- | --- | --- | --- |
| `update_tasks` | `edit_tasks`: `{"operation":"update","targetIDs":["ID"],"taskPatch":{"flagged":true}}` | `update-tasks` | `edit-tasks ID --operation update --flagged true` |
| `set_tasks_completion` | `edit_tasks`: `{"operation":"set_completion","targetIDs":["ID"],"completion":{"state":"completed"}}` | `set-tasks-completion` | `edit-tasks ID --operation set_completion --state completed` |
| `move_tasks` | `edit_tasks`: `{"operation":"move","targetIDs":["ID"],"move":{"destinationKind":"inbox"}}` | `move-tasks` | `edit-tasks ID --operation move --destination-kind inbox` |
| `update_projects` | `edit_projects`: `{"operation":"update","targetIDs":["ID"],"projectPatch":{"flagged":true}}` | `update-projects` | `edit-projects ID --operation update --flagged true` |
| `set_projects_status` | `edit_projects`: `{"operation":"set_status","targetIDs":["ID"],"projectStatus":{"status":"on_hold"}}` | `set-projects-status` | `edit-projects ID --operation set_status --status on_hold` |
| `set_projects_completion` | `edit_projects`: `{"operation":"set_completion","targetIDs":["ID"],"completion":{"state":"completed"}}` | `set-projects-completion` | `edit-projects ID --operation set_completion --state completed` |
| `move_projects` | `edit_projects`: `{"operation":"move","targetIDs":["ID"],"move":{"destinationKind":"folder","destinationID":"FOLDER_ID"}}` | `move-projects` | `edit-projects ID --operation move --destination-kind folder --destination-id FOLDER_ID` |

Default mutation responses remain compact. For repeating tasks or projects,
OmniFocus may complete an occurrence and advance the original item; use
`verify=true` and inspect the returned per-target message.
