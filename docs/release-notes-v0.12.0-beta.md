# FocusRelay 0.12.0-beta

This release makes it easier for an AI assistant to help you reach inbox zero
without losing control of what changes.

## What’s new

- Process your inbox in manageable batches with a guided workflow that starts
  with unresolved captures, asks before changing anything, and verifies
  approved updates.
- Keep ordinary inbox cleanup focused on unfinished captures instead of
  unexpectedly mixing in completed or dropped history.
- Resolve nested tags more confidently by seeing the parent path for matching
  tags.
- Trust compact and multi-page results: unsupported fields and mismatched page
  cursors now fail clearly instead of returning misleading data.
- Keep OmniFocus updates reliable during busy conversations and client
  restarts—work is handled in order, overload is reported clearly, and
  disconnected FocusRelay processes exit cleanly.

In OpenCode, run `/process_inbox` to start the guided workflow.

## Before upgrading

FocusRelay now requires macOS 26 or later.

After upgrading, reinstall the packaged OmniFocus plugin and restart OmniFocus
so the plugin and FocusRelay binary stay in sync.
