# FocusRelayMCP Next Steps

Last updated: 2026-07-13

The detailed release sequence and validation record live in
[`docs/roadmap-execution-plan.md`](docs/roadmap-execution-plan.md). GitHub issues
are the source of truth for individual deliverables.

## Before `v0.10.0-beta`

- [x] Integrate the Swift 6.3.3 toolchain, truthful mutation persistence,
  project-count parity, unified version reporting, release packaging, and
  Homebrew ownership changes into local branch `integration/v0.10.0-beta-rc`.
- [x] Pass the combined 120-test Swift Testing suite with Swiftly-managed Swift
  6.3.3.
- [x] Build and validate a versioned `0.10.0-beta` archive and checksum locally.
- [x] Install the combined plugin, fully restart OmniFocus, and repeat the live
  health, mutation write/restore, and query-parity checks.
- [x] Run all three semantic gates on the combined candidate.
- [x] Run the required 1.5-hour realistic single-user benchmark: 750 measured
  calls completed with zero errors/timeouts and project-count parity stayed
  exact. One task-count pair crossed a live inbox update.
- [x] Correct the public task-filter schema, mutation safety annotations,
  advertised task search, and list-benchmark scenario rotation on isolated
  branches, then integrate them into the local candidate.
- [x] Complete corrected 10-minute list and count smokes with full scenario
  coverage and no errors, timeouts, or parity mismatches.
- [x] Complete the required one-hour post-change realistic validation: 544
  measured calls passed with complete coverage and no errors, timeouts, or
  parity mismatches.
- [x] Prepare user-facing `v0.10.0-beta` release notes with safety limits,
  upgrade steps, measured performance, and contributor credit.
- [ ] Publish the isolated branches or release candidate for GitHub CI/review.
- [ ] Tag and publish only after approval and green release validation.
- [ ] Update `/Users/deverman/Documents/code/homebrew-focus-relay` with the
  actual release asset URL/version/SHA256, then verify a clean reinstall.

## Release Blockers and Trackers

- [#71](https://github.com/deverman/FocusRelayMCP/issues/71) — P1 mutation
  save/per-target truthfulness.
- [#61](https://github.com/deverman/FocusRelayMCP/issues/61) — P2 project task
  count parity and realistic validation.
- [#64](https://github.com/deverman/FocusRelayMCP/issues/64) — P2 release
  packaging and metadata.
- [#72](https://github.com/deverman/FocusRelayMCP/issues/72) — P2 authoritative
  Homebrew formula ownership/correctness.
- [#58](https://github.com/deverman/FocusRelayMCP/issues/58) — CLI, MCP, plugin,
  and release version consistency.
- [#74](https://github.com/deverman/FocusRelayMCP/issues/74) — Swift 6.3.3
  toolchain alignment.
- [#76](https://github.com/deverman/FocusRelayMCP/issues/76) — keep internal
  diagnostics out of the public MCP tool surface.
- [#77](https://github.com/deverman/FocusRelayMCP/issues/77) — publish the full
  shared task-filter schema on list and count tools.
- [#78](https://github.com/deverman/FocusRelayMCP/issues/78) — truthful mutation
  safety annotations and preview/write defaults.
- [#79](https://github.com/deverman/FocusRelayMCP/issues/79) — make task search
  filter names and notes as advertised.
- [#81](https://github.com/deverman/FocusRelayMCP/issues/81) — guarantee measured
  coverage of every list-benchmark scenario.
- [#63](https://github.com/deverman/FocusRelayMCP/issues/63) — release tracker.

## After Release

Prioritize user-visible, low-risk improvements as isolated branches:

1. [#82](https://github.com/deverman/FocusRelayMCP/issues/82) — safely create
   tasks in the inbox, a project, or beneath a parent task.
2. [#83](https://github.com/deverman/FocusRelayMCP/issues/83) — safely create
   projects at the root or in an existing folder.
3. [#11](https://github.com/deverman/FocusRelayMCP/issues/11) — OmniFocus deep
   links in existing query output.
4. [#22](https://github.com/deverman/FocusRelayMCP/issues/22) — task added and
   modified timestamps and filters.
5. [#18](https://github.com/deverman/FocusRelayMCP/issues/18) — project planned
   dates and filters.
6. [#59](https://github.com/deverman/FocusRelayMCP/issues/59) — native task
   status filters.
7. [#62](https://github.com/deverman/FocusRelayMCP/issues/62) — configurable
   sorting.
8. [#75](https://github.com/deverman/FocusRelayMCP/issues/75) — migrate server
   text responses off deprecated MCP SDK overloads.
9. [#80](https://github.com/deverman/FocusRelayMCP/issues/80) — remove JXA
   dispatch from the supported runtime and retain pure JXA only as an internal
   parity oracle until fixtures replace it.

Task and project creation are planned post-beta enhancements and do not block
`v0.10.0-beta`.

Treat [#73](https://github.com/deverman/FocusRelayMCP/issues/73), immediate IPC
cleanup, as an experiment rather than a release blocker. Keep it only if the
semantic, smoke, and realistic benchmarks show a defensible latency win without
new timeouts or reliability regressions.
