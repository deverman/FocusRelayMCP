# Timeout/Concurrency Investigation Notes (Feb 19, 2026)

## Status
Deferred for follow-up PR. Current branch focus was correctness fixes for PR #6 and related bridge payload issues.

## What We Observed
Live bridge tests intermittently fail with `executionFailed("Bridge response timed out")` under `FOCUS_RELAY_BRIDGE_TESTS=1`.

### Repro Commands
```bash
FOCUS_RELAY_BRIDGE_TESTS=1 swift test
FOCUS_RELAY_BRIDGE_TESTS=1 swift test --parallel --num-workers 1
```

### Example Failures Seen
- `bridgeHealthCheckLive`
- `bridgeListInboxLive`
- `bridgeTaskCountsLive`
- `bridgeProjectCountsLive`
- `bridgeProjectsPagingLive`
- `bridgeTagsPagingLive`
- `bridgeInboxViewCountsMatchListTasksLive`
- `bridgeAvailableTasksCountConsistencyLive`
- `bridgeTaskStatusValuesAreValidLive`
- `bridgeProjectTaskCountsIncludedLive`
- `bridgeTaskCountsRespectsProjectViewLive`
- `bridgeCompletedInboxFilterDoesNotDefaultToAvailableOnlyLive`

### Transport/IPC Errors Captured
In addition to timeouts, logs contained:
- `_LSOpenURLsWithCompletionHandler ... error -1712` when opening `omnifocus:///omnijs-run?...`
- Request write failure:
  - `NSCocoaErrorDomain Code=512`
  - underlying `NSPOSIXErrorDomain Code=4 "Interrupted system call"`
  - file write target under `.../FocusRelayIPC/requests/<uuid>.json`

## Why Manual Queries Can Still Pass
Single interactive MCP queries (one-at-a-time) often succeed. The failures above are more visible during repeated live test sequences and transport stress.

## Working Hypothesis
Primary issue is not task-filter correctness now; it is bridge/transport robustness under repeated invocation:
- URL dispatch/open path to OmniFocus occasionally times out (`-1712`)
- request file IO can be interrupted
- fixed 10s timeout is still fragile for some operations/host states

## Proposed Follow-Up PR Scope
1. Add resilient retry for idempotent bridge operations on open/timeout/file-interrupted errors.
2. Introduce per-operation timeout policy with safer defaults for read-heavy ops.
3. Improve bridge diagnostics:
   - request id
   - operation name
   - open/dispatch timing
   - wait timing
   - response decode timing
4. Split live tests into:
   - correctness lane (short deterministic smoke)
   - stress lane (explicitly flaky-tolerant, captures diagnostics)

## Out Of Scope For Current PR
- Full timeout/concurrency architecture redesign
- test-runner-level orchestration changes

