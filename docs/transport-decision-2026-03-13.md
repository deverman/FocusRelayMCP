# Transport Decision: Keep `plugin-url` As Default

Date: 2026-03-13

Finalized by #80 on 2026-07-18: the Bridge plugin is now the only executable
architecture. Direct JXA and OSAKit code were removed after deterministic
Bridge fixtures and live list/count contracts replaced its remaining value.

Branch at decision time:
- `exp/master-documented-query-baseline`

Decision:
- Keep `plugin-url` as the default production transport.
- Do not switch the product to `plugin-jxa-dispatch`.
- Do not replace the plugin architecture with pure JXA.

## Context

This decision was made after:
- rebuilding the benchmark process on the clean baseline branch
- enforcing documented Omni Automation usage for query logic
- stabilizing benchmark orchestration with a foreground `caffeinate` run
- running a corrected transport A/B on the same commit and database

Corrected benchmark root:
- `docs/benchmarks/transport-ab-safe-20260312-210547`

Corrected benchmark commit:
- `744dfac568c3beaa090ed91e2d6650545c9909d6`

## Important Correction

An earlier transport A/B result was invalid and must not be used for architecture decisions.

Why it was invalid:
- the benchmark metadata recorded `FOCUS_RELAY_BRIDGE_DISPATCH_TRANSPORT`
- but the clean-branch `BridgeClient` was still always using URL dispatch
- so the earlier "plugin-jxa-dispatch" run was not actually exercising the JXA dispatch path

Fix commit:
- `8ff72be` `Implement real bridge transport selection`

After that fix, a real JXA-dispatch smoke benchmark for `list_tasks` passed and proved the transport switch was active:
- `docs/benchmarks/list-tasks-smoke-jxa-dispatch-real-20260310-084429/summary.md`

## Corrected A/B Result

### `get_task_counts`

Artifacts:
- `docs/benchmarks/transport-ab-safe-20260312-210547/plugin-url/get_task_counts/summary.md`
- `docs/benchmarks/transport-ab-safe-20260312-210547/plugin-jxa-dispatch/get_task_counts/summary.md`

Result:
- `plugin-url`
  - plugin error rate: `0.47%`
  - plugin p50: `9170ms`
  - plugin p95: `12858ms`
- `plugin-jxa-dispatch`
  - plugin error rate: `0.58%`
  - plugin p50: `11440ms`
  - plugin p95: `14551ms`

Conclusion:
- `plugin-url` is better for `get_task_counts`

### `list_tasks`

Artifacts:
- `docs/benchmarks/transport-ab-safe-20260312-210547/plugin-url/list_tasks/summary.md`
- `docs/benchmarks/transport-ab-safe-20260312-210547/plugin-jxa-dispatch/list_tasks/summary.md`

Result:
- `plugin-url`
  - plugin timeouts: `8`
  - plugin errors concentrated across multiple scenarios
- `plugin-jxa-dispatch`
  - plugin timeouts: `11`
  - plugin errors also concentrated across multiple scenarios

Conclusion:
- neither transport is good enough yet
- `plugin-jxa-dispatch` did not solve the main reliability problem

### `get_project_counts`

Artifacts:
- `docs/benchmarks/transport-ab-safe-20260312-210547/plugin-url/get_project_counts/summary.md`
- `docs/benchmarks/transport-ab-safe-20260312-210547/plugin-jxa-dispatch/get_project_counts/summary.md`

Result:
- `plugin-url`
  - plugin error rate: `0.68%`
  - plugin p50: `12398ms`
  - plugin p95: `26592ms`
- `plugin-jxa-dispatch`
  - plugin error rate: `7.69%`
  - plugin p50: `11768ms`
  - plugin p95: `16238ms`

Interpretation:
- JXA dispatch reduced plugin latency tail in some cases
- but the reliability regression is too large to accept

Conclusion:
- `plugin-jxa-dispatch` is not acceptable for `get_project_counts`

## Parity

All corrected A/B summaries reported:
- mismatch count: `0`

This means the functional comparison is trustworthy.

## Final Decision Rationale

`plugin-url` remains the correct default because:
- it is better on `get_task_counts`
- it is materially more reliable on `get_project_counts`
- `plugin-jxa-dispatch` does not fix `list_tasks`
- pure JXA still does not justify replacing the plugin architecture

In short:
- the transport simplification candidate (`plugin-jxa-dispatch`) did not improve the system enough to justify a switch
- the product should stay on the existing plugin query engine with URL dispatch while reliability work continues

## Follow-up Direction

The next focus should be:
- `list_tasks` reliability hardening on `plugin-url`

Reason:
- `list_tasks` is the highest-value read path
- transport switching did not solve its failure mode
- the remaining work is runtime/dispatch/query-pressure hardening, not architecture replacement

Related hardening commit after this decision:
- `9cff631` `Harden list_tasks timeout recovery`

Related smoke validation:
- `docs/benchmarks/list-tasks-smoke-post-hardening-20260313-063127/summary.md`

## Decision Rules Going Forward

Until new evidence disproves this decision:
- do not change the default transport away from `plugin-url`
- do not make architecture decisions from any benchmark run unless the transport implementation is verified first
- do not compare transports and query changes in the same experiment
- treat pure JXA as a reference/verification path, not the production architecture

## July 2026 Revalidation

The `v0.10.0-beta` release audit strengthened this decision:

- the combined candidate completed its earlier 1.5-hour realistic suite with
  750 measured calls and zero errors or timeouts;
- corrected task-search smokes completed 192 measured list/count calls with no
  error, timeout, or parity mismatch;
- the subsequent 30-minute realistic list phase completed 266 measured calls
  across all ten scenarios with no error, timeout, or mismatch;
- the paired 30-minute realistic count phase completed 278 measured calls
  across all six scenarios with no error, timeout, or mismatch, and OmniFocus
  ended 447 MB below its phase-start RSS;
- focused inbox list p50 was 0.99 seconds through the plugin versus 6.52 seconds
  through pure JXA; the corresponding smoke count p95 was 1.08 seconds versus
  7.11 seconds;
- pure JXA is not a complete alternative runtime: `getTask` and tag listing are
  not implemented there, while folder listing and all seven production
  mutations delegate back to `OmniFocusBridgeService`.

The refined architecture direction is therefore:

1. Keep plugin URL dispatch as the only production architecture.
2. Do not remove the already-validated fallback immediately before the beta.
3. After the beta, use [#80](https://github.com/deverman/FocusRelayMCP/issues/80)
   to remove JXA dispatch as a supported runtime option and move pure JXA toward
   test/benchmark-only ownership.
4. Replace live JXA parity coverage with deterministic fixtures where practical,
   then remove JXA from the shipped binary when it no longer adds unique
   verification value.

## Post-Decision Validation (2026-03-14)

Subsequent clean-branch work reinforced the decision to stay on `plugin-url`.

Relevant artifacts:
- Full clean suite after `list_tasks` hardening:
  - `docs/benchmarks/suite-post-listtasks-hardening-20260313-221745/summary.md`
- `list_tasks` post-hardening 1-hour run:
  - `docs/benchmarks/list-tasks-1h-post-hardening-20260313-145309/summary.md`
- `list_tasks` post-stream-fast-path 1-hour run:
  - `docs/benchmarks/list-tasks-1h-post-stream-fast-path-20260314-2313/summary.md`
- Progress note:
  - `docs/performance-progress-2026-03-14.md`

What changed after the decision:
- `list_tasks` timeout recovery was hardened on `plugin-url`.
- The old plugin timeout pattern in the transport A/B no longer reproduced in the clean 1-hour validation run.
- A later shared-path cleanup and no-total-count streaming path improved `list_tasks` median latency further without introducing new reliability failures.

Updated interpretation:
- `plugin-url` remains the best current production choice.
- The transport question is no longer the main optimization lever.
- Further work should continue to target query/runtime behavior on `plugin-url` rather than transport replacement.
