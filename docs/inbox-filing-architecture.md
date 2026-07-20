# Inbox Filing Architecture (Projects + Tags)

Goal: let the AI file inbox tasks into projects and apply tags without flooding context.

## Constraints
- 300+ projects, many tags.
- Must avoid large context dumps.
- Minimize tool calls while keeping results accurate.

## Recommended Flow (Read-Only Prep)

1) Fetch project catalog with pagination
- Call `list_projects` with `limit=150` and `fields=["id","name"]`.
- Continue until `nextCursor` is null.
- Cache the project list in memory for the session.

2) Fetch tag catalog with pagination
- Call `list_tags` with `limit=150`.
- Cache for the session.

3) Fetch inbox tasks in pages
- Use `list_tasks` with `inboxOnly=true` and `inboxView=available`.
- `fields=["id","name","note"]` if notes are needed; otherwise omit.

4) Classify in batches
- Run classification per page (e.g., 50 tasks at a time).
- Only keep minimal metadata in context.

## Optimizations for Token Budget

1) Compact catalogs
- Use only `id` + `name` for projects/tags.
- Optionally include a short alias field (server-side precomputed).

2) Server-side lookup helpers
- Add a tool to search projects by name substring: `search_projects(query)`.
- Add a tool to search tags by name substring: `search_tags(query)`.
- This avoids sending the full catalog into context if not needed.

3) Low-entropy prompting
- Ask the model to map each inbox item to a project ID and tag IDs.
- Avoid passing full project descriptions or notes.

4) Cache results
- Keep the project/tag catalogs cached in the MCP server for N minutes.

## Suggested Tool Additions (Future)

1) `get_catalog_snapshot`
- Returns `{projects:[{id,name}], tags:[{id,name}]}` with paging or compression.

2) `search_projects` and `search_tags`
- Queryable endpoints to reduce catalog size in context.

3) `classify_inbox`
- Server-side helper that returns suggested project/tag IDs for inbox items.
- Keeps AI reasoning within the server to reduce token output.

## Example Client Strategy

```
projects = []
cursor = null
do {
  page = list_projects(limit=100, cursor, fields=["id","name"])
  projects += page.items
  cursor = page.nextCursor
} while (cursor)

tags = []
cursor = null
do {
  page = list_tags(limit=100, cursor)
  tags += page.items
  cursor = page.nextCursor
} while (cursor)

inbox = []
cursor = null
do {
  page = list_tasks(filter:{inboxOnly:true,inboxView:"available"}, limit=50, fields=["id","name"])
  inbox += page.items
  cursor = page.nextCursor
} while (cursor)
```

## Notes
- For existing inbox tasks, use homogeneous `edit_tasks` `update` and `move`
  operations and require explicit confirmation for broad changes.
- Creating a missing project, tag, or destination remains future work.
- Avoid sending full catalogs into the prompt unless asked.
