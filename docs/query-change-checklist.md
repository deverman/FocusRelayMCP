# Query Change Checklist

Use this before changing any production query path in FocusRelay.

Scope:
- `Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js`
- `Sources/OmniFocusAutomation/OmniFocusAutomation.swift`
- `Sources/OmniFocusAutomation/BridgeClient.swift`
- `Sources/FocusRelayCLI/BenchmarkGateCheckCommand.swift`

## 1. Freeze The Contract First

Before coding, write down:
- the documented Omni Automation APIs the change is allowed to use
- the semantic invariants that must not change
- the exact fallback path for out-of-scope scenarios

Reference:
- [`docs/omni-automation-contract.md`](./omni-automation-contract.md)

Minimum invariant list:
- task status comes from `task.taskStatus`
- project status comes from `project.status`
- pagination applies after filtering and sorting
- `nextCursor` is derived from the filtered result set
- `includeTotalCount` agrees with the matching count tool or contract check
- completed-window queries remain sorted by `completionDate` descending

## 2. Add Semantic Tripwire Tests

Add tests for the exact boundary or contract risk introduced by the change.

Preferred categories:
- inclusive vs exclusive date boundaries
- count/list parity for the same filter
- pagination continuity across page 1 -> page 2
- status edge cases: on-hold, dropped, done, completed parent
- bridge vs JXA parity for the same scenario

Recent regressions to treat as templates:
- `plannedBefore` exclusivity
- stale `list_tasks` cursors
- completed inbox filters accidentally defaulting to `availableOnly=true`

## 3. Gate Before Benchmarking

Do not run benchmarks until semantic checks pass.

Required sequence:
1. `swift test`
2. `swift run focusrelay benchmark-gate-check --tool <affected-tool>`
3. 10-minute smoke benchmark
4. 1-hour realistic validation if production behavior changed materially

If the change touches timeout handling or transport behavior:
- keep transport and query experiments isolated
- use the 3-hour profile only for diagnosis, not as the default success criterion

## 4. Define The Win Condition Up Front

A change is not a keeper because it improves a short run.

Write down the acceptance rule before implementation:
- semantic gate passes
- smoke run stays clean
- 1-hour validation does not regress reliability
- 1-hour validation shows a defensible latency win on the target path

If any of those fail:
- revert the change
- document the experiment

## 5. Validate User-Facing Flow When Docs Or Packaging Move

If the work changes install steps, plugin packaging, or approval behavior, verify:
1. binary installed
2. plugin installed
3. MCP configured
4. OmniFocus restarted
5. first query triggers the approval prompt when expected
6. first successful query returns real data after approval

Use plain-language docs, not shorthand that assumes prior project context.
