# AI Questions for OmniFocus MCP Testing

## General Productivity/Todo List Questions (Applicable to any task manager)

1. **"What should I be doing right now?"**
   - Tests ability to query available/next actions with time context

2. **"What should I be doing today?"**
   - Tests due date filtering and daily planning capabilities

3. **"What are my top 3 priorities for this week?"**
   - Tests prioritization logic and flagged/important item identification

4. **"Based on my projects, what are my overall life priorities?"**
   - Tests pattern recognition across project names and structure

5. **"What's the frog I should eat today?"** (Most important/difficult task)
   - Tests identification of high-impact, potentially procrastinated items

6. **"Give me something fun to work on"**
   - Tests tagging/filtering by energy level or task type preferences

7. **"What can I do in the next 15 minutes?"**
   - Tests duration estimation filtering and quick win identification

8. **"What tasks am I procrastinating on?"**
   - Tests defer date analysis and stale task identification

9. **"Create a morning routine checklist for me"**
   - Tests recurring task creation and template generation

10. **"Summarize what I accomplished this week"**
    - Tests completed task reporting and weekly review capabilities

## OmniFocus-Specific Questions (Leveraging OmniFocus features)

11. **"Please tag and organize my inbox items under my projects"**
    - Tests inbox processing, auto-categorization, and project assignment

12. **"Please estimate the duration for each task in my inbox and update it"**
    - Tests task metadata updates and time estimation

13. **"Take the current discussion and make action items in OmniFocus, add it to the related project or create a new one"**
    - Tests natural language processing to create tasks from conversation

14. **"Show me all available tasks grouped by project"**
    - Tests available action filtering with project grouping

15. **"What projects have no next actions defined?"**
    - Tests project status analysis and "stalled project" identification

16. **"Find all tasks with the 'Waiting' tag that are older than 3 days"**
    - Tests tag filtering with date criteria for follow-up reminders

17. **"Create a project for planning my vacation with sub-tasks for booking flights, hotels, and activities"**
    - Tests hierarchical project creation with sub-tasks

18. **"What are my due soon items sorted by project?"**
    - Tests due date perspective with project organization

19. **"Review my single action lists and suggest improvements"**
    - Tests SAL (Single Action List) identification and optimization suggestions

20. **"Sync my calendar events with OmniFocus and create preparation tasks for each meeting"**
    - Tests integration capabilities and task creation from external data

## Advanced/Complex Questions

21. **"Analyze my task completion rate by project for the last month"**
    - Tests analytics capabilities across completed items

22. **"Identify tasks that should be delegated based on my role and the task type"**
    - Tests intelligent categorization and delegation suggestions

23. **"Create a sequential project for onboarding a new employee with all necessary steps"**
    - Tests template creation with sequential/parallel action setup

24. **"What tags am I not using effectively?"**
    - Tests tag usage analysis and organization recommendations

25. **"Plan my ideal productive day based on my energy levels and task contexts"**
    - Tests time-blocking and energy-based task scheduling

## Notes for Testing

- Questions 11, 12, 13 require write capabilities (currently read-only)
- Questions 6, 7, 8 require metadata fields (estimatedMinutes, tags)
- Questions 3, 4, 5 require AI reasoning beyond simple filtering
- Questions 15, 19 are OmniFocus-specific (projects vs single actions)
- Questions 16, 21, 22, 24 require date analysis and pattern recognition
