# FocusRelay 0.11.0-beta

This release makes everyday OmniFocus cleanup and review work safer and easier.

## What’s new

- Clean up your task list without losing history by dropping and restoring
  tasks instead of marking them completed.
- Finish weekly reviews faster or declare review bankruptcy by letting
  FocusRelay mark active or on-hold projects as reviewed using OmniFocus’s
  normal review schedule.
- Find the right project by name before changing it, even when it is on hold,
  completed, or dropped.
- Make bulk changes with confidence: if any requested task or project cannot be
  updated, nothing in that batch is changed.
- Get more trustworthy results from searches, Review queries, and multi-page
  lists—invalid requests now fail clearly instead of returning misleading data.
- Leave more context for your actual work: seven editing tools are now combined
  into two, reducing the full tool catalog from 14 tools to 9 and cutting
  context usage by 7–13% in controlled model tests.

## Before upgrading

Task and project editing is now handled through the two clearer `edit_tasks` and
`edit_projects` tools. If you have saved automations using older editing tools,
update them using the
[migration table](mutation-workflows.md#breaking-migration).

After upgrading, reinstall the packaged OmniFocus plugin and restart OmniFocus
so the plugin and FocusRelay binary stay in sync.
