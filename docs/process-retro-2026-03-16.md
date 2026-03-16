# Process Retro: 2026-03-16

## Purpose

This retro documents what slowed down the performance/reliability effort, what actually worked, and what process rules should prevent the same drift next time.

## What Slowed Us Down

### 1. Too many variables changed at once

We mixed:
- query optimization
- transport experiments
- approval-dialog work
- benchmark harness changes
- timeout policy changes

That made it hard to trust results because each run was answering more than one question at a time.

### 2. We benchmarked before semantics were frozen

At several points we optimized paths that were not yet parity-stable.

That created two kinds of waste:
- good benchmark numbers on the wrong behavior
- time spent diagnosing “performance” that was really contract drift

### 3. We relied on undocumented Omni Automation behavior

The biggest technical mistake was treating undocumented collections and behaviors as safe production building blocks.

That increased the chance of:
- plugin/JXA divergence
- misleading fast paths
- transport-specific behavior differences

### 4. We trusted an invalid transport comparison at first

The first transport A/B looked useful, but the JXA-dispatch path was not actually being exercised.

That delayed the final architecture decision and forced a corrected A/B later.

### 5. We used a stress profile as if it were the main product benchmark

The stress profile was useful for exposing queue pressure and runtime degradation, but it was harsher than likely single-user usage.

That sometimes made us chase problems that were real under synthetic load but not necessarily the right priority for product decisions.

## What Worked

### 1. Contract-first benchmarking

The semantic gate checks were one of the most useful improvements:
- bridge health
- JXA probe
- bridge/JXA parity
- count/list contract checks

These should stay mandatory.

### 2. One-tool-at-a-time optimization

The work accelerated once it was reduced to:
1. pick one tool
2. lock semantics
3. optimize
4. smoke
5. 1-hour validate
6. only then escalate

### 3. Explicit restart and readiness steps

The benchmark scripts became more trustworthy only after:
- explicit OmniFocus restart
- readiness checks
- logged semantic gates

### 4. Reverting failed experiments quickly

The right move with the failed `list_tasks` availability memoization was to revert it immediately once the 1-hour run regressed.

That discipline should continue.

## Process Rules Going Forward

1. One experiment per branch
- query optimization
- transport experiment
- caching
- approval/security UX
- benchmark/tooling

2. No undocumented Omni Automation APIs in production paths

3. Never keep a speculative optimization unless:
- gate passes
- smoke stays clean
- 1-hour realistic validation stays clean
- 1-hour realistic validation shows a real win

4. Never compare transports and query changes in the same benchmark program

5. Treat stress benchmarks as diagnostic, not default release criteria

## Benchmark Policy Going Forward

### Default release benchmark

Use the realistic single-user profile:
- total duration: `1.5h`
- per tool: `30m`
- warmup: `10`
- interval: `5000ms`
- cooldown: `5000ms`
- memory sampling: `60s`

### Diagnostic benchmark

Use the stress profile only when:
- transport changed
- timeout handling changed
- queue pressure is under investigation
- the realistic benchmark regressed

Recommended stress profile:
- total duration: `3h`
- warmup: `20`
- interval: `1500ms`
- cooldown: `3000ms`
- memory sampling: `30s`

## Release Stage Guidance

### Before merge
- `swift test`
- semantic gate for affected tools
- smoke benchmark on affected tools
- 1-hour realistic benchmark if production query behavior changed

### Before tagging
- run the realistic suite if the release touches production query/transport logic
- otherwise run smoke only

### After tagging
- verify GitHub release asset exists
- update Homebrew SHA256
- refresh tap locally if stale
- reinstall formula
- verify `focusrelay --help`

## Final Takeaway

The main lesson is simple:

**Reduce the number of open questions in each experiment.**

The work moved slowly when one benchmark tried to answer multiple architectural questions at once. It moved faster once each run answered exactly one question.
