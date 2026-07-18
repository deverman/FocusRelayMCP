# Reset Plan From `master` For The Fastest FocusRelayMCP

Status: Completed on clean branch `exp/master-documented-query-baseline`
Date: 2026-03-16
Associated issue: `#19`

Historical note: #80 later removed the pure-JXA reference implementation and
retired transport comparisons. Current validation uses deterministic Bridge
fixtures and live list/count contracts.

## Final Status Update

This plan was executed on the clean branch and is now complete enough to close the optimization phase.

Completed:
- documented Omni Automation contract was added and enforced
- benchmark gates and repeatable benchmark tooling were added
- `get_task_counts` was optimized and validated
- `list_tasks` was hardened and optimized on `plugin-url`
- `get_project_counts` was corrected, optimized, and validated
- corrected transport A/B was completed
- architecture decision was made to keep `plugin-url`

Rejected during execution:
- replacing the plugin with pure JXA
- switching default transport to `plugin-jxa-dispatch`
- request-scoped availability memoization in `list_tasks`

Deferred to future phases:
- cache strategy work
- runtime-pressure recovery beyond the current hardening
- any additional transport experiments

Primary closeout document:
- `docs/final-optimization-summary-2026-03-16.md`

## Summary
- Start over from `master` and treat the previous experimental branch as a learning artifact, not an implementation base.
- Choose **bridge plugin as the primary architecture** for performance work. Keep **pure JXA** only as a reference implementation for parity and benchmarking, not as the target fastest architecture.
- Keep **URL + bridge** as the initial baseline from `master`. Do **not** change dispatch transport until query semantics and benchmarks are stable. Re-evaluate **JXA + bridge dispatch** only as a later isolated A/B experiment.
- Enforce a **documented Omni Automation contract** before any optimization work. No undocumented `project.availableTasks`, `project.remainingTasks`, database `availableTasks`, or database `remainingTasks` in core query paths.

## What I Would Tell My Past Self
- We mixed too many variables at once: query optimization, dispatch transport, approval-UX fixes, benchmark harness changes, and semantic fixes. That made the results impossible to trust.
- We benchmarked before we locked semantic invariants. That let us optimize incorrect behavior.
- We relied on undocumented Omni Automation collections and assumed they behaved consistently across plugin and `evaluateJavascript`. That was the core technical mistake.
- We used live tests with env gates, which made “green” runs less meaningful than they looked.
- We over-invested in transport changes before proving the query engine was the dominant bottleneck.

## Architecture Choice
- **Primary read architecture**: bridge plugin query engine, starting from `master`’s URL dispatch.
- **Reference architecture**: pure JXA `evaluateJavascript`, used only for parity probes and controlled benchmarks.
- **Deferred experiment**: JXA dispatch into bridge plugin, but only after query semantics are frozen and benchmark gates are passing.

### Final Result
- The benchmark evidence on the clean branch supports **keeping `plugin-url`**.
- Pure JXA is not the production architecture.
- `plugin-jxa-dispatch` is not the replacement transport.

Supporting document:
- `docs/transport-decision-2026-03-13.md`

## The Architecture I Would Rebuild
1. **Bridge query engine only uses documented Omni Automation surface**
- Enumerate tasks from documented `flattenedTasks` / `project.flattenedTasks`.
- Enumerate projects from documented `flattenedProjects`.
- Use `task.taskStatus` and `project.status` as the status source of truth.
- Derive remaining/available/completed from documented status values, not from convenience pools unless the docs explicitly define them.

2. **Pure JXA is a verifier, not the product path**
- Implement the same documented query model in JXA.
- Use it to cross-check counts and ordering on a fixed scenario matrix.
- Do not use pure JXA latency to drive query-engine design for the main architecture.

3. **Dispatch is isolated from query work**
- Phase 1: keep `master` transport as-is.
- Phase 2: once semantics are frozen, run a matched A/B of:
  - plugin-url
  - plugin-jxa-dispatch
- Decide dispatch only from those matched runs.

## Benchmark Strategy I Would Use Instead
### Benchmark gates before any soak run
- Reject any run if parity mismatches are nonzero on the scoped scenarios.
- Reject any run if bridge `get_task_counts` disagrees with bridge `list_tasks.totalCount` where they should match.
- Reject any run if bridge `get_project_counts(projectView=active)` disagrees with bridge `list_tasks(projectView=active, completed=false, availableOnly=false).totalCount`.
- Reject any run if OmniFocus approval prompts appear.
- Reject any run if restart/preflight is not explicit and logged.

### Run sequence
1. **Baseline on `master`, no code changes**
- Capture:
  - plugin-url baseline
  - pure-JXA baseline
- Tools:
  - `get_task_counts`
  - `list_tasks`
  - `get_project_counts`
- Durations:
  - 10-minute smoke
  - 1-hour short
- No overnight yet.

2. **One-tool optimization cycle**
- Pick one tool only.
- Lock its semantic contract.
- Add or update parity tests.
- Run:
  - 10-minute smoke
  - 1-hour short
  - 3-hour soak
- Only after 3-hour clean: include it in overnight.

3. **Dispatch experiment only after query work**
- Same commit, same database, same scenario set.
- Compare:
  - plugin-url
  - plugin-jxa-dispatch
- Keep pure JXA as reference in the same suite.
- No query changes allowed during this phase.

### Metrics that actually matter
- Primary:
  - p95 latency
  - timeout rate
  - parity mismatch count
- Secondary:
  - p50/p99
  - RSS slope for OmniFocus and `focusrelay`
- Tertiary:
  - cold-start behavior after restart
  - approval-prompt incidence

### Final interpretation update
- The stress profile was useful to expose runtime-pressure failure modes.
- For future product validation, use the realistic benchmark profile in:
  - `docs/realistic-benchmark-profile-2026-03-16.md`

### Tool-by-tool acceptance criteria
- `get_task_counts`
  - zero parity mismatches
  - error rate < 1% in 3h
  - p95 better than master baseline
  - Status: complete enough for this phase
- `list_tasks`
  - zero parity mismatches on IDs, ordering, `totalCount`, and cursor continuity
  - plugin remains materially faster than pure JXA
  - Status: complete enough for this phase
- `get_project_counts`
  - zero parity mismatches
  - active-view counts must match the corresponding `list_tasks` contract exactly before benchmarking performance claims
  - Status: complete enough for this phase

## How I Would Stay On Track Better
1. **Write a local Omni Automation contract before coding**
- Add `docs/omni-automation-contract.md`.
- It should be a short synthesized document, not a copy of the official site.
- It should list:
  - allowed documented collections/properties
  - banned undocumented collections/properties
  - links to the official docs

2. **Update `AGENTS.md` with a hard rule, not the whole docs**
- Add a compact section:
  - “Only use documented Omni Automation APIs in query engines.”
  - “If an API is not documented on the official site, do not use it in production query paths.”
  - “When in doubt, prefer `flattenedTasks` + status filtering.”
- Link `AGENTS.md` to `docs/omni-automation-contract.md` and the official docs.
- Do not dump the full docs into `AGENTS.md`; synthesize them into enforceable repo rules.

3. **Make semantic checks first-class**
- Add bridge-vs-JXA parity tests that are on by default only in a clearly named live-test mode.
- Add a small dev command or test helper that prints per-status counts for a filter.
- Never benchmark a tool whose parity gate is failing.

4. **Separate orchestration from measurement**
- No giant chained shell commands.
- Use explicit steps:
  - restart
  - bridge health check
  - JXA probe
  - smoke benchmark
- Store each step’s result separately.

5. **Keep a branch rule**
- One branch per experiment:
  - query optimization
  - dispatch transport
  - approval UX
- Never combine them.

## The Step-By-Step Restart Plan
1. Branch from `master`.
- Name it something like `exp/master-documented-query-baseline`.

2. Add the contract doc first.
- `docs/omni-automation-contract.md`
- No behavior changes yet.

3. Freeze the baseline.
- Run matched plugin-url and pure-JXA baselines from `master`.
- Save:
  - 10-minute smoke
  - 1-hour short
- Record benchmark SHA and environment notes.

4. Rebuild `get_task_counts` first.
- Use only documented APIs.
- Keep bridge as target path.
- Use pure JXA as verifier.
- Benchmark only this tool.
- Status: completed in this phase.

5. Rebuild `list_tasks` second.
- Same documented-only model.
- This is likely the most important performance path.
- Benchmark only this tool.
- Status: completed in this phase.

6. Rebuild `get_project_counts` last.
- Define its contract from `list_tasks` first.
- Do not invent a separate inclusion model.
- Benchmark only after parity is exact.
- Status: completed in this phase.

7. Only then run the dispatch experiment.
- A/B:
  - plugin-url
  - plugin-jxa-dispatch
- Same commit, same database, same tool set, no query changes.
- Status: completed in this phase.

## The Prompt I Would Give My Past Self
“Start from `master`. Do not change dispatch transport, approval UX, and query semantics in the same branch. First create a short local contract from the official Omni Automation docs that lists only documented APIs allowed in query paths. Then freeze baseline benchmarks for plugin-url and pure-JXA on `get_task_counts`, `list_tasks`, and `get_project_counts`. Treat pure JXA as a parity/reference implementation, not the target fastest architecture. Optimize one tool at a time in the bridge plugin using only documented `flattenedTasks`, `flattenedProjects`, `task.taskStatus`, and `project.status`. Before any performance benchmark, require exact parity between bridge and JXA and exact consistency between count tools and their corresponding `list_tasks` totals. Run 10-minute smoke, then 1-hour short, then 3-hour soak. Only after all three tools are semantically stable should you evaluate plugin-jxa-dispatch versus plugin-url as a separate isolated transport experiment.”

## Important Interface / Process Changes
- Add `docs/omni-automation-contract.md`.
- Add an `AGENTS.md` rule that production query paths must use documented Omni Automation APIs only.
- Add explicit parity gates to the benchmark process.
- No public MCP schema changes are required for the restart.

## Assumptions And Defaults
- “Fastest” means best p95 latency with acceptable reliability, not just best p50.
- Maintainability matters: documented-only APIs are the default rule.
- Bridge plugin remains the primary architecture unless a later isolated A/B proves otherwise.
- Pure JXA remains a verifier and benchmark reference, not the main product path.
