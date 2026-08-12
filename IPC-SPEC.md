# FocusRelayMCP IPC Spec (Draft)

This document defines a file-based IPC protocol between the Swift MCP server and the OmniFocus plug-in bridge. The goal is to ensure reliable, low-latency communication without URL payload limits.

## Goals

- Large payloads supported (no URL size limits)
- Safe against partial writes and duplicate processing
- Deterministic request/response mapping
- Simple to debug on disk

## Directories

Fixed base directory (not configurable):

```
~/Library/Containers/com.omnigroup.OmniFocus4/Data/Documents/FocusRelayIPC
```

The bridge plug-in can only write inside OmniFocus's sandbox container, so
there is no usable alternative location. When the OmniFocus 4 container is
absent, path resolution fails fast with an actionable error instead of
letting requests time out.

Subdirectories and files:

```
requests/
responses/
locks/
dispatch/
bridge-version.json
```

Any other top-level entry is out of policy and is deleted during startup
maintenance (legacy examples: `logs/`, `pid-*/`, `default/`, `*.trace.json`).

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

1) MCP server writes `requests/<requestId>.json`.
2) MCP server passes `requestId` as the OmniFocus URL argument. The inline
   bootstrap reads that argument and calls `BridgeLibrary.handleRequest` with
   the request ID and IPC base path.
3) Plug-in reads the UUID-named request, creates its matching lock, writes the
   UUID-named response, then removes the lock and request.
4) MCP server polls for the matching response file, reads it, deletes the
   response (plus any remaining request/lock), and returns tool output. A
   successful round trip leaves no artifacts on disk.

## Timeouts + Retries

- Default timeout: 10 seconds
- Poll interval: 100–200 ms
- MCP server deletes request/lock if timeout exceeded (optional cleanup)

## Retention

| Path | Policy | Enforced |
| --- | --- | --- |
| Non-allowlisted top-level entries | delete always | startup maintenance |
| `requests/<id>.json` | plug-in deletes after response; client deletes after successful decode and on non-timeout error; else stale > 10 min | per-request + throttled sweep |
| `responses/<id>.json` | client deletes immediately after successful decode; timeout artifacts kept for late-arrival recovery | per-request + throttled sweep |
| `locks/<id>.lock` | plug-in deletes after response; client belt-and-braces after success; else stale > 10 min | per-request + throttled sweep |
| `dispatch/request.json` | compatibility artifact written by the client but not read by the current URL/bootstrap/plug-in path; client deletes after response, else stale > 10 min | per-request + throttled sweep |
| `bridge-version.json` | persistent; rewritten on version change | startup maintenance |

The stale sweep runs at most once per stale interval (10 minutes), never on
every request. Startup maintenance runs once per process before the first
bridge request.

## Idempotency Rules

- Plug-in must check for existing response file; if it exists, return without reprocessing.
- MCP server should treat multiple identical responses as safe.
- The response-exists check only matters during the in-flight window
  (duplicate dispatch from stranded-request redispatch or late recovery).
  The client deletes the response only after a successful decode and never
  re-dispatches that request ID afterwards, so consumption does not affect
  the check.

## Versioning

- `schemaVersion` is required.
- Incompatible versions should return a structured error response.
- `bridge-version.json` records the binary version (and the last observed
  plug-in version) that owns the directory:
  `{"schemaVersion":1,"swiftVersion":"…","pluginVersion":"…","updatedAt":"…"}`.
  A mismatch at startup — or a changed plug-in version observed during a
  health check — clears the contents of all protocol directories once and
  rewrites the marker, so no artifacts written by one version are ever read
  by another.

## Security

- Files are local only and hold OmniFocus content (task and project data) in
  cleartext while they exist; retention keeps that window minimal (successful
  round trips leave no artifacts).
- The Swift side is authoritative for permissions: directories are created
  and repaired to `0700`; Swift-written files are set to `0600` after each
  atomic write (atomic replace discards modes, so this is chmod-after-write —
  the directory is the enforcement boundary, not file creation modes).
- Plug-in-written files may carry the default mode; they live inside `0700`
  directories and are deleted as soon as they are consumed.
- The plug-in writes no log files; plug-in diagnostics return as response
  data only.

## Concurrency And Admission Scope

- The request ID passed as the URL argument and its UUID-named request file are
  the authoritative request selector. Per-request locks prevent duplicate
  processing of one request ID; they do not serialize different request IDs.
- The process-wide Bridge lane coordinates all service instances inside one
  `focusrelay serve` process. Independent server executables do not share that
  in-memory lane, and the file protocol does not currently provide a global
  admission lock or broker.
- `dispatch/request.json` remains a client-written compatibility artifact. The
  current production URL bootstrap and `BridgeLibrary.handleRequest` do not
  read it, so it must not be treated as a request selector or concurrency
  control. Removing it is a separate transport-reliability change.
- Cross-process admission behavior is not yet established by the existing
  single-process burst evidence. The bounded measurement and decision gate are
  tracked in [#216](https://github.com/deverman/FocusRelayMCP/issues/216).

## Notes

- The URL trigger selects the file payload with `requestId`; operation and tool
  arguments remain in the request file.
- File-based IPC is the source of truth for payloads.
