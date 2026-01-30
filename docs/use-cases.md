# FocusRelayMCP Use Cases

This document captures real-world use cases and questions users ask AI about their todo lists, organized by category.

## Use Case Categories

### 1. Daily Planning & Prioritization

**Goal**: Help users decide what to work on right now, today, or this week.

#### Questions:
- "What should I be doing right now?"
- "What should I be doing today?"
- "What are my top 3 priorities for this week?"
- "What's the frog I should eat today?" (Most important/difficult task)
- "What can I do in the next 15 minutes?"
- "Give me something fun to work on"
- "Give me something easy to start with"
- "What should I focus on this morning/afternoon?"
- "What's the most urgent thing on my plate?"

**MCP Tools Needed**:
- `list_tasks` with availability filtering
- `list_tasks` with due date filtering
- `list_tasks` with duration filtering
- `list_tasks` with tag filtering

---

### 2. Life Balance & Priority Analysis

**Goal**: Help users understand their overall life priorities based on their project structure.

#### Questions:
- "Based on my projects, what are my overall life priorities?"
- "Am I spending too much time on work vs personal projects?"
- "What areas of my life am I neglecting?"
- "Show me a breakdown of my projects by category"
- "What percentage of my tasks are for work vs personal?"
- "Do I have too many projects open?"
- "Which life areas need more attention based on my task distribution?"

**MCP Tools Needed**:
- `list_projects` (full catalog)
- `list_tasks` (cross-project analysis)
- `get_task_counts` (by project/category)

---

### 3. Inbox Processing & Organization

**Goal**: Help users process their inbox and organize items into appropriate projects.

#### Questions:
- "Please tag and organize my inbox items under my projects"
- "Process my inbox - categorize everything"
- "What project should this inbox item go to?"
- "Review my inbox and suggest actions for each item"
- "Create projects from these inbox items"
- "Batch process similar inbox items together"

**MCP Tools Needed**:
- `list_tasks` with inbox filter
- `list_projects` (for categorization context)
- Write tools (future): `update_task`, `move_task_to_project`

---

### 4. Task Estimation & Planning

**Goal**: Help users estimate task durations and plan their schedule.

#### Questions:
- "Please estimate the duration for each task in my inbox"
- "How long will all my tasks for today take?"
- "Can I fit all my due tasks into an 8-hour workday?"
- "Estimate how long this project will take"
- "Find all tasks without time estimates"
- "Suggest time estimates for unestimated tasks"

**MCP Tools Needed**:
- `list_tasks` with estimatedMinutes field
- `list_tasks` with due date filters
- Write tools (future): `update_task` to set estimates

---

### 5. Meeting & Discussion Action Items

**Goal**: Extract action items from conversations and create tasks.

#### Questions:
- "Take the current discussion and make action items in OmniFocus"
- "Create tasks from this meeting transcript"
- "Add these action items to the related project, or create a new one"
- "From this email/thread, extract my todo items"
- "Convert this conversation into a project with sub-tasks"

**MCP Tools Needed**:
- `list_projects` (to find related project)
- `get_task` (to check for duplicates)
- Write tools (future): `create_task`, `create_project`

---

### 6. Procrastination & Stale Task Detection

**Goal**: Help users identify tasks they're avoiding or have forgotten.

#### Questions:
- "What tasks am I procrastinating on?"
- "What tasks have I been deferring repeatedly?"
- "Show me old tasks I haven't completed"
- "What have I been avoiding?"
- "Find tasks that have been in my list for months"
- "What items are creating mental overhead?"

**MCP Tools Needed**:
- `list_tasks` with defer date filters
- `list_tasks` with creation date (for stale detection)
- `get_task_counts` (for pattern analysis)

---

### 7. Weekly Review & Retrospective

**Goal**: Help users review what they've accomplished and plan ahead.

#### Questions:
- "Summarize what I accomplished this week"
- "What did I complete yesterday?"
- "How productive was I this week?"
- "What projects made progress this week?"
- "What did I NOT get done that I planned to?"
- "Create a weekly review summary"

**MCP Tools Needed**:
- `list_tasks` with completed filter + date range
- `list_projects` (to see project progress)
- `get_task_counts` (completion statistics)

---

### 8. Project Health & Maintenance

**Goal**: Help users maintain healthy projects with clear next actions.

#### Questions:
- "What projects have no next actions defined?"
- "Which projects are stalled?"
- "Show me all available tasks grouped by project"
- "What projects need review?"
- "Find projects with too many tasks"
- "Identify projects that should be completed or dropped"
- "Review my single action lists"

**MCP Tools Needed**:
- `list_projects`
- `list_tasks` by project
- `get_project_counts`
- `get_task_counts`

---

### 9. Context & Location-Based Queries

**Goal**: Help users find tasks they can do in their current context.

#### Questions:
- "What can I do at home?"
- "What errands can I run?"
- "What phone calls do I need to make?"
- "What tasks require my computer?"
- "What can I do while commuting?"
- "Show me tasks tagged with 'Mac Computer'"

**MCP Tools Needed**:
- `list_tags` (to see available contexts)
- `list_tasks` with tag filtering
- `search_tags` (future)

---

### 10. Due Date & Deadline Management

**Goal**: Help users stay on top of deadlines and due dates.

#### Questions:
- "What is due today?"
- "What is due this week?"
- "What is overdue?"
- "What is due soon?"
- "Find all tasks without due dates"
- "What deadlines are approaching?"
- "Show me a timeline of upcoming due dates"

**MCP Tools Needed**:
- `list_tasks` with due date filters
- `list_tasks` sorted by due date

---

### 11. Tag & Context Organization

**Goal**: Help users organize and optimize their tag system.

#### Questions:
- "What tags am I not using effectively?"
- "Show me all my tags"
- "Which tags have the most tasks?"
- "Find tasks without any tags"
- "Suggest better tagging for my tasks"
- "What contexts do I have available?"

**MCP Tools Needed**:
- `list_tags`
- `list_tasks` with tag filtering
- `get_task_counts` by tag

---

### 12. Motivation & Energy Management

**Goal**: Help users choose tasks based on their current energy and motivation.

#### Questions:
- "Give me something fun to work on"
- "Give me something challenging"
- "Give me something mindless for when I'm tired"
- "What high-impact task should I tackle?"
- "Find me a quick win"
- "What creative tasks do I have?"
- "Show me tasks that require deep focus"

**MCP Tools Needed**:
- `list_tags` (fun, creative, challenging tags)
- `list_tasks` with tag + duration filtering
- Task metadata (energy level, priority)

---

### 13. Analytics & Insights

**Goal**: Provide data-driven insights about productivity patterns.

#### Questions:
- "Analyze my task completion rate by project"
- "What times of day am I most productive?"
- "How many tasks do I complete per week?"
- "What projects am I making progress on?"
- "Am I capturing more than I'm completing?"
- "What is my average task completion time?"

**MCP Tools Needed**:
- `get_task_counts` with filters
- `list_tasks` with date ranges
- Historical data analysis

---

### 14. Delegation & Collaboration

**Goal**: Help users identify tasks to delegate and track waiting items.

#### Questions:
- "Identify tasks that should be delegated"
- "What am I waiting for from others?"
- "Find tasks tagged with 'waiting' that are old"
- "What can I outsource or delegate?"
- "Show me tasks assigned to others"
- "What should I follow up on?"

**MCP Tools Needed**:
- `list_tasks` with tag filtering ("waiting")
- `list_tasks` with defer date (for follow-up timing)

---

### 15. Goal Setting & Project Creation

**Goal**: Help users create projects and structure goals.

#### Questions:
- "Create a project for planning my vacation with sub-tasks"
- "Break down this goal into actionable steps"
- "Create a sequential project for onboarding a new employee"
- "Plan my ideal productive day"
- "Create a morning routine checklist"
- "Generate sub-tasks for this complex task"

**MCP Tools Needed**:
- `list_projects` (to avoid duplicates)
- Write tools (future): `create_project`, `create_task`, `add_subtask`

---

## Implementation Status

### Read-Only Use Cases (Current Capabilities)
✅ **Working Today**:
- Daily planning with available tasks
- Project priority analysis
- Basic task listing by project
- Flagged item identification

⚠️ **Partial** (Needs Enhancement):
- Date-based queries (need date range filters)
- Duration filtering (need min/max filters)
- Tag-based queries (need tag filter)
- Completed task analysis (need completion dates)

❌ **Not Yet** (Requires Write Access):
- Inbox processing/organization
- Task estimation updates
- Creating tasks from discussions
- Project creation

## Priority Roadmap

### Phase 1: Read-Only Enhancement (High Priority)
1. Add date range filters (`dueBefore`, `dueAfter`, etc.)
2. Add duration filtering (`maxEstimatedMinutes`)
3. Add tag-based filtering
4. Add creation and completion dates

### Phase 2: Search & Discovery (Medium Priority)
1. Add `search_projects` tool
2. Add `search_tags` tool
3. Add per-project task counts
4. Add analytics endpoints

### Phase 3: Write Operations (Future)
1. Task creation tools
2. Task update tools
3. Inbox processing automation
4. Project management tools

## Success Metrics

For each use case to be considered "working":
- Response time < 3 seconds for simple queries
- Response time < 10 seconds for complex queries (multi-tool)
- Correct data returned 95%+ of the time
- Natural language question maps to correct tool(s)
