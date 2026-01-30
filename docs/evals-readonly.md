# FocusRelayMCP Evaluation Framework (Evals)

This document defines structured evaluations to test MCP tool effectiveness against real user questions.

## Evaluation Structure

Each eval consists of:
- **Question**: The natural language user query
- **Required Tools**: MCP tools needed to answer
- **Tool Calls**: Exact tool invocations required
- **Success Criteria**: How to measure correct response
- **Current Status**: ✅ Implemented | ⚠️ Partial | ❌ Missing

## Read-Only Evals (Phase 1)

### Eval 1: "What should I be doing right now?"
**Required Tools**: `list_tasks` with availability filtering

**Tool Calls**:
```json
{
  "tool": "list_tasks",
  "arguments": {
    "filter": {
      "inboxOnly": false,
      "availableOnly": true
    },
    "page": {"limit": 5},
    "fields": ["id", "name", "projectName", "dueDate", "flagged"]
  }
}
```

**Success Criteria**:
- Returns 1-5 available actions (not blocked/deferred)
- Prioritized by due date (if any), then flagged status
- Execution time < 2 seconds

**Current Status**: ✅ Implemented

---

### Eval 2: "What should I be doing today?"
**Required Tools**: `list_tasks` with due date filtering

**Tool Calls**:
```json
{
  "tool": "list_tasks",
  "arguments": {
    "filter": {
      "dueBefore": "2026-01-31T23:59:59Z",
      "dueAfter": "2026-01-30T00:00:00Z",
      "completed": false
    },
    "page": {"limit": 20},
    "fields": ["id", "name", "dueDate", "projectName", "estimatedMinutes"]
  }
}
```

**Success Criteria**:
- Returns tasks due today (or overdue)
- Sorted by due time
- Shows estimated duration for planning

**Current Status**: ⚠️ Partial - Need date range filtering in bridge

---

### Eval 3: "What are my top 3 priorities for this week?"
**Required Tools**: `list_tasks` with flagged + due date

**Tool Calls**:
```json
{
  "tool": "list_tasks",
  "arguments": {
    "filter": {
      "flagged": true,
      "completed": false
    },
    "page": {"limit": 3},
    "fields": ["id", "name", "dueDate", "projectName"]
  }
}
```

**Success Criteria**:
- Returns 3 flagged items
- If fewer than 3 flagged, include due-soon items

**Current Status**: ✅ Implemented (flagged filter exists)

---

### Eval 4: "Based on my projects, what are my overall life priorities?"
**Required Tools**: `list_projects` + analysis

**Tool Calls**:
```json
{
  "tool": "list_projects",
  "arguments": {
    "page": {"limit": 150},
    "fields": ["id", "name"]
  }
}
```

**Success Criteria**:
- Returns all project names
- AI can categorize by keywords (Career, Personal, Health, etc.)
- Groups projects into life areas

**Current Status**: ✅ Implemented

---

### Eval 5: "What's the frog I should eat today?"
**Required Tools**: `list_tasks` with multi-factor prioritization

**Tool Calls**:
```json
{
  "tool": "list_tasks",
  "arguments": {
    "filter": {
      "availableOnly": true,
      "completed": false
    },
    "page": {"limit": 10},
    "fields": ["id", "name", "dueDate", "flagged", "estimatedMinutes", "note"]
  }
}
```

**Success Criteria**:
- Returns available tasks
- AI identifies "frog" based on: overdue + flagged + large estimate
- May need note content for context

**Current Status**: ⚠️ Partial - Need note field in response

---

### Eval 6: "Give me something fun to work on"
**Required Tools**: `list_tasks` with tag filtering

**Tool Calls**:
```json
{
  "tool": "list_tags",
  "arguments": {
    "page": {"limit": 50}
  }
}
```
Then:
```json
{
  "tool": "list_tasks",
  "arguments": {
    "filter": {
      "tags": ["fun", "creative", "hobby"],
      "availableOnly": true
    },
    "page": {"limit": 5}
  }
}
```

**Success Criteria**:
- Lists available tags first
- Filters by fun/creative tags
- Returns 1-5 "fun" tasks

**Current Status**: ❌ Missing - Need tag-based filtering in list_tasks

---

### Eval 7: "What can I do in the next 15 minutes?"
**Required Tools**: `list_tasks` with duration filtering

**Tool Calls**:
```json
{
  "tool": "list_tasks",
  "arguments": {
    "filter": {
      "availableOnly": true,
      "maxEstimatedMinutes": 15
    },
    "page": {"limit": 10},
    "fields": ["id", "name", "estimatedMinutes"]
  }
}
```

**Success Criteria**:
- Returns only tasks with estimatedMinutes ≤ 15
- Quick wins for short time blocks

**Current Status**: ❌ Missing - Need maxEstimatedMinutes filter

---

### Eval 8: "What tasks am I procrastinating on?"
**Required Tools**: `list_tasks` with defer date analysis

**Tool Calls**:
```json
{
  "tool": "list_tasks",
  "arguments": {
    "filter": {
      "availableOnly": true,
      "completed": false
    },
    "page": {"limit": 20},
    "fields": ["id", "name", "deferDate", "dueDate"]
  }
}
```

**Success Criteria**:
- Returns tasks with deferDate in the past
- Or tasks with old creation dates (stale)
- Shows items that have been deferred multiple times

**Current Status**: ⚠️ Partial - Need creation date field

---

### Eval 9: "Summarize what I accomplished this week"
**Required Tools**: `list_tasks` with completion filter + date range

**Tool Calls**:
```json
{
  "tool": "list_tasks",
  "arguments": {
    "filter": {
      "completed": true,
      "completedAfter": "2026-01-23T00:00:00Z",
      "completedBefore": "2026-01-30T23:59:59Z"
    },
    "page": {"limit": 100},
    "fields": ["id", "name", "projectName", "completed"]
  }
}
```

**Success Criteria**:
- Returns all completed tasks this week
- Groups by project
- Shows completion count

**Current Status**: ❌ Missing - Need completedAfter/Before filters

---

### Eval 10: "Show me all available tasks grouped by project"
**Required Tools**: `list_tasks` + `list_projects` + grouping

**Tool Calls**:
```json
{
  "tool": "list_projects",
  "arguments": {
    "page": {"limit": 150},
    "fields": ["id", "name"]
  }
}
```
Then for each project:
```json
{
  "tool": "list_tasks",
  "arguments": {
    "filter": {
      "project": "<project-id>",
      "availableOnly": true
    },
    "page": {"limit": 50}
  }
}
```

**Success Criteria**:
- Gets all projects
- Queries tasks per project
- Groups results hierarchically
- Total time < 10 seconds for 200 projects

**Current Status**: ✅ Implemented (can be done with multiple calls)

---

### Eval 11: "What projects have no next actions defined?"
**Required Tools**: `list_projects` + `get_task_counts` per project

**Tool Calls**:
```json
{
  "tool": "get_project_counts",
  "arguments": {
    "filter": {
      "projectView": "available"
    }
  }
}
```

**Success Criteria**:
- Identifies projects with 0 available actions
- These are "stalled" projects needing review

**Current Status**: ⚠️ Partial - Need per-project available action count

---

## Gaps Identified

### Missing Filters Needed:

1. **Date Range Filters** (Eval 2, 9)
   - `dueBefore`, `dueAfter`
   - `completedAfter`, `completedBefore`
   - `deferBefore`, `deferAfter`

2. **Duration Filtering** (Eval 7)
   - `maxEstimatedMinutes`
   - `minEstimatedMinutes`

3. **Tag-Based Filtering** (Eval 6)
   - `tags` array in filter
   - Match any/all tags

4. **Completion Date** (Eval 9)
   - Need `completedDate` field in TaskItem

5. **Creation Date** (Eval 8)
   - Need `createdDate` field for stale detection

### Missing Tools Needed:

1. **search_projects** - Find projects by name substring
2. **search_tags** - Find tags by name substring
3. **list_available_tasks_by_project** - Batch query available tasks per project

## Recommended Priority

**High Priority** (Unlocks most evals):
1. Add date range filters to `list_tasks`
2. Add `maxEstimatedMinutes` filter
3. Add `tags` filter to `list_tasks`

**Medium Priority**:
4. Add `createdDate` and `completedDate` fields
5. Add `search_projects` tool

**Low Priority**:
6. Per-project task counts
7. Advanced analytics queries
