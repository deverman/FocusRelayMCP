# OmniFocus JavaScript API Reference

This document catalogs the OmniFocus JavaScript API properties and methods used by FocusRelayMCP.

## Task Object

### Status Properties

| Property         | Type          | Description                             |
| ---------------- | ------------- | --------------------------------------- |
| `taskStatus`     | `Task.Status` | OmniFocus-calculated status (see below) |
| `completed`      | `boolean`     | Whether task is marked complete         |
| `completionDate` | `Date`        | When task was completed                 |
| `dropDate`       | `Date`        | When task was dropped                   |

### Task.Status Values

```javascript
Task.Status.Available; // Task is actionable now
Task.Status.Next; // Next action in sequential project
Task.Status.DueSoon; // Due within 24 hours
Task.Status.Overdue; // Due date has passed
Task.Status.Blocked; // Blocked by incomplete prerequisites
Task.Status.Completed; // Task is marked complete
Task.Status.Dropped; // Task has been dropped
```

### Date Properties

| Property             | Type      | Description                                        |
| -------------------- | --------- | -------------------------------------------------- |
| `deferDate`          | `Date`    | Raw defer date (may be null)                       |
| `effectiveDeferDate` | `Date`    | Calculated defer date (respects parent/sequential) |
| `dueDate`            | `Date`    | Task due date                                      |
| `dueSoon`            | `boolean` | Whether task is due within 24 hours                |

### Hierarchy Properties

| Property            | Type          | Description                     |
| ------------------- | ------------- | ------------------------------- |
| `parent`            | `Task`        | Parent task (null if top-level) |
| `containingProject` | `Project`     | Project containing this task    |
| `children`          | `Array<Task>` | Child tasks                     |
| `hasChildren`       | `boolean`     | Whether task has subtasks       |

### Other Properties

| Property           | Type         | Description                                          |
| ------------------ | ------------ | ---------------------------------------------------- |
| `name`             | `string`     | Task name                                            |
| `note`             | `string`     | Task notes                                           |
| `flagged`          | `boolean`    | Whether task is flagged                              |
| `estimatedMinutes` | `number`     | Time estimate in minutes                             |
| `blocked`          | `boolean`    | Whether task is blocked (deprecated: use taskStatus) |
| `tags`             | `Array<Tag>` | Tags assigned to task                                |
| `sequential`       | `boolean`    | Whether children are sequential                      |

## Project Object

### Status Properties

| Property    | Type             | Description                  |
| ----------- | ---------------- | ---------------------------- |
| `status`    | `Project.Status` | Project status (see below)   |
| `completed` | `boolean`        | Whether project is completed |
| `onHold`    | `boolean`        | Whether project is on hold   |
| `dropDate`  | `Date`           | When project was dropped     |

### Project.Status Values

```javascript
Project.Status.Active; // Project is active
Project.Status.OnHold; // Project is on hold
Project.Status.Dropped; // Project has been dropped
Project.Status.Done; // Project is completed
```

### Task Collections

| Property                   | Type          | Description                           |
| -------------------------- | ------------- | ------------------------------------- |
| `tasks`                    | `Array<Task>` | Top-level tasks in project            |
| `flattenedTasks`           | `Array<Task>` | All tasks including nested            |
| `nextTask`                 | `Task`        | Next available task (null if stalled) |
| `containsSingletonActions` | `boolean`     | True for Single Actions lists         |

Note: FocusRelay treats `nextTask` and `containsSingletonActions` as optional project-health extras. Core query paths and benchmark gates must not depend on them for correctness.

### Review Properties

| Property         | Type     | Description                    |
| ---------------- | -------- | ------------------------------ |
| `lastReviewDate` | `Date`   | Last time project was reviewed |
| `nextReviewDate` | `Date`   | When project is due for review |
| `reviewInterval` | `Object` | Review interval configuration  |

## Tag Object

| Property         | Type          | Description                      |
| ---------------- | ------------- | -------------------------------- |
| `id`             | `ID`          | Tag identifier                   |
| `name`           | `string`      | Tag name                         |
| `status`         | `Tag.Status`  | Active / on-hold / dropped state |
| `tasks`          | `Array<Task>` | Tasks with this tag              |
| `flattenedTasks` | `Array<Task>` | Tasks including subtags          |
| `parent`         | `Tag`         | Parent tag                       |
| `children`       | `Array<Tag>`  | Child tags                       |

## Folder Object

| Property   | Type             | Description        |
| ---------- | ---------------- | ------------------ |
| `name`     | `string`         | Folder name        |
| `projects` | `Array<Project>` | Projects in folder |
| `children` | `Array<Folder>`  | Subfolders         |
| `parent`   | `Folder`         | Parent folder      |

## Global Objects

### document

```javascript
document.inbox; // Inbox tasks
document.projects; // All projects
document.tags; // All tags
document.folders; // All folders
```

### Application

```javascript
Application("OmniFocus"); // Application object for automation
```

## Best Practices

1. **Always use `task.taskStatus`** instead of manual checks
2. **Always check `project.status`** for project state
3. **Use `safe()` wrapper** for all property access to handle nulls
4. **Respect parent relationships** - check parent status for child tasks
5. **Use effective dates** - prefer `effectiveDeferDate` over `deferDate`

## Migration Notes

### From Manual Checks to Native Status

**Before (incorrect):**

```javascript
function isTaskAvailable(task) {
  if (task.blocked) return false;
  if (task.deferDate && task.deferDate > Date.now()) return false;
  return true;
}
```

**After (correct):**

```javascript
function isTaskAvailable(task) {
  // Check project status
  if (task.containingProject?.status === Project.Status.OnHold) return false;

  // Check parent status
  if (task.parent?.completed) return false;

  // Use native status
  const status = task.taskStatus;
  return (
    status === Task.Status.Available ||
    status === Task.Status.Next ||
    status === Task.Status.DueSoon ||
    status === Task.Status.Overdue
  );
}
```

## Resources

- [OmniFocus JavaScript Reference](https://omni-automation.com/plugins/omnifocus/)
- [Omni Automation Documentation](https://omni-automation.com/)
