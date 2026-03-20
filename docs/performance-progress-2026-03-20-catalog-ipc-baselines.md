# Performance Progress: 2026-03-20 Catalog and IPC Baselines

Branch:
- `chore/catalog-ipc-baselines`

## Scope

This refresh replaces the stale catalog / IPC benchmark artifacts added earlier on this branch.

The benchmark surface remains:
- `list_projects`
- `list_tags`
- bridge IPC overhead

The goal of this document is to capture the latest smoke and realistic baselines for this PR only.
It is not transport A/B evidence.

## Validation

Commands run before benchmarking:
- `swift test`
- `./scripts/install-plugin.sh`
- `osascript -e 'tell application "OmniFocus" to quit' && sleep 2 && open -a "OmniFocus"`
- `swift run focusrelay benchmark-gate-check --tool list-projects`
- `swift run focusrelay benchmark-gate-check --tool list-tags`
- `swift run focusrelay benchmark-gate-check --tool all`

Benchmark commands run:
- `caffeinate -dimsu swift run focusrelay benchmark-list-projects --duration-hours 0.17 --warmup-calls 5 --interval-ms 2000 --cooldown-ms 3000 --output-dir docs/benchmarks/list-projects-smoke-20260320-093850`
- `caffeinate -dimsu swift run focusrelay benchmark-list-tags --duration-hours 0.17 --warmup-calls 5 --interval-ms 2000 --cooldown-ms 3000 --output-dir docs/benchmarks/list-tags-smoke-20260320-093850`
- `caffeinate -dimsu swift run focusrelay benchmark-bridge-health --duration-hours 0.17 --warmup-calls 5 --interval-ms 2000 --cooldown-ms 3000 --output-dir docs/benchmarks/bridge-health-smoke-20260320-093850`
- `caffeinate -dimsu swift run focusrelay benchmark-list-projects --duration-hours 0.5 --warmup-calls 10 --interval-ms 5000 --cooldown-ms 5000 --output-dir docs/benchmarks/list-projects-realistic-20260320-101217`
- `caffeinate -dimsu swift run focusrelay benchmark-list-tags --duration-hours 0.5 --warmup-calls 10 --interval-ms 5000 --cooldown-ms 5000 --output-dir docs/benchmarks/list-tags-realistic-20260320-101217`
- `caffeinate -dimsu swift run focusrelay benchmark-bridge-health --duration-hours 0.5 --warmup-calls 10 --interval-ms 5000 --cooldown-ms 5000 --output-dir docs/benchmarks/bridge-health-realistic-20260320-101217`

Result:
- all tests and semantic gates passed
- all six benchmark runs completed without recorded errors or timeouts

## Artifacts

Smoke:
- `docs/benchmarks/list-projects-smoke-20260320-093850/summary.md`
- `docs/benchmarks/list-tags-smoke-20260320-093850/summary.md`
- `docs/benchmarks/bridge-health-smoke-20260320-093850/summary.md`

Realistic:
- `docs/benchmarks/list-projects-realistic-20260320-101217/summary.md`
- `docs/benchmarks/list-tags-realistic-20260320-101217/summary.md`
- `docs/benchmarks/bridge-health-realistic-20260320-101217/summary.md`

## Representative Results

### `list_projects`

Smoke:
- `active_minimal` p50 `399.07ms`, p95 `441.11ms`
- `active_counts` p50 `2045.36ms`, p95 `2104.36ms`
- `active_counts_stalled` p50 `2080.62ms`, p95 `2154.02ms`

Realistic:
- `active_minimal` p50 `410.59ms`, p95 `453.04ms`
- `active_counts` p50 `2113.21ms`, p95 `2189.63ms`
- `active_counts_stalled` p50 `2153.39ms`, p95 `2221.99ms`

Interpretation:
- `active_minimal` remains much cheaper than the count-bearing scenarios
- stalled-field retrieval stays close to the cost of counts, not far above it

### `list_tags`

Smoke:
- `active_no_counts` p50 `2335.44ms`, p95 `2409.25ms`
- `active_with_counts` p50 `2331.60ms`, p95 `2408.58ms`

Realistic:
- `active_no_counts` p50 `2401.40ms`, p95 `2498.13ms`
- `active_with_counts` p50 `2383.80ms`, p95 `2532.94ms`

Interpretation:
- the two tag scenarios are still in the same latency band on the current plugin path
- this document should be treated as the latest baseline for this PR, not as evidence of a transport change

### bridge IPC overhead

Smoke:
- total calls: `302`
- latency p50 `185.32ms`, p95 `236.24ms`
- bridge timing p50 `17.00ms`, p95 `23.00ms`
- transport overhead p50 `168.44ms`, p95 `212.24ms`

Realistic:
- total calls: `357`
- latency p50 `186.59ms`, p95 `237.83ms`
- bridge timing p50 `18.00ms`, p95 `22.00ms`
- transport overhead p50 `168.85ms`, p95 `216.55ms`

Interpretation:
- bridge health remains dominated by dispatch / wait overhead rather than plugin execution time
- smoke and realistic runs stayed close enough to use these numbers as the current IPC baseline for this PR

## Current Recommendation

1. Use the smoke artifacts for quick refreshes on this branch.
2. Use the realistic artifacts as the merge-confidence baseline for this PR.
3. Do not cite these numbers as transport A/B results.
