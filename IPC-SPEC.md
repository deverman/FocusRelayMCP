# FocusRelayMCP IPC Spec (Draft)

This document defines a file-based IPC protocol between the Swift MCP server and the OmniFocus plug-in bridge. The goal is to ensure reliable, low-latency communication without URL payload limits.

## Goals

- Large payloads supported (no URL size limits)
- Safe against partial writes and duplicate processing
- Deterministic request/response mapping
- Simple to debug on disk

## Directories

Default base directory (configurable):

```
~/Library/Containers/com.omnigroup.OmniFocus4/Data/Documents/FocusRelayIPC
```

Subdirectories:

```
requests/
responses/
locks/
logs/
```

## File Naming

Each request uses a UUID v4 string (requestId).

- Request file: `requests/<requestId>.json`
- Response file: `responses/<requestId>.json`
- Lock file: `locks/<requestId>.lock`
- Temp file: `requests/<requestId>.json.tmp` (and similar for responses)

## Atomic Write Rules

All writers MUST:

1) Write to `*.tmp`
2) `fsync` (if possible)
3) Atomic rename to final filename

Readers MUST:

- Ignore any `*.tmp` files
- Only read final filenames

## Locking

To prevent duplicate processing, the OmniFocus plug-in should create a lock file using exclusive create semantics:

- If `locks/<requestId>.lock` exists, the request is already being processed (or stuck).
- If lock creation fails, skip or retry later.

The plug-in removes the lock after writing the response.

## Request Schema

```json
{
  "schemaVersion": 1,
  "requestId": "uuid-v4",
  "op": "list_inbox",
  "timestamp": "2026-01-29T12:00:00Z",
  "id": null,
  "filter": {
    "completed": false,
    "availableOnly": false,
    "inboxView": "available",
    "inboxOnly": false,
    "projectView": "remaining",
    "project": "Project Name or ID",
    "tags": ["Tag A", "Tag B"],
    "includeTotalCount": true
  },
  "fields": ["id", "name"],
  "page": { "limit": 50, "cursor": "0" }
}
```

## Response Schema

```json
{
  "schemaVersion": 1,
  "requestId": "uuid-v4",
  "ok": true,
  "data": {
    "items": [ { "id": "...", "name": "..." } ],
    "returnedCount": 1,
    "totalCount": 123,
    "nextCursor": "50"
  },
  "timingMs": 82,
  "warnings": []
}
```

Error response:

```json
{
  "schemaVersion": 1,
  "requestId": "uuid-v4",
  "ok": false,
  "error": {
    "code": "INBOX_QUERY_FAILED",
    "message": "..."
  }
}
```

## Request Lifecycle (Happy Path)

1) MCP server writes request file.
2) MCP server triggers OmniFocus plug-in with requestId.
3) Plug-in reads request, creates lock, writes response.
4) MCP server polls for response file, reads it, returns tool output.

## Timeouts + Retries

- Default timeout: 10 seconds
- Poll interval: 100–200 ms
- MCP server deletes request/lock if timeout exceeded (optional cleanup)

## Cleanup

- Stale request/response/lock files older than 10 minutes may be deleted by the MCP server.

## Idempotency Rules

- Plug-in must check for existing response file; if it exists, return without reprocessing.
- MCP server should treat multiple identical responses as safe.

## Versioning

- `schemaVersion` is required.
- Incompatible versions should return a structured error response.

## Security

- Files are local only.
- No secrets should be written unless explicitly required.
- Requests/responses are readable by the current user.

## Notes

- The URL trigger should only send `requestId` and operation name (if needed).
- File-based IPC is the source of truth for payloads.
