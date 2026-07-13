# FocusRelayMCP Next Steps

Last updated: 2026-07-13

The detailed release sequence and validation record live in
[`docs/roadmap-execution-plan.md`](docs/roadmap-execution-plan.md). GitHub issues
are the source of truth for individual deliverables.

## Before `v0.10.0-beta`

- [x] Integrate the Swift 6.3.3 toolchain, truthful mutation persistence,
  project-count parity, unified version reporting, release packaging, and
  Homebrew ownership changes into local branch `integration/v0.10.0-beta-rc`.
- [x] Pass the combined 114-test Swift Testing suite with Swiftly-managed Swift
  6.3.3.
- [x] Build and validate a versioned `0.10.0-beta` archive and checksum locally.
- [x] Install the combined plugin, fully restart OmniFocus, and repeat the live
  health, mutation write/restore, and query-parity checks.
- [x] Run all three semantic gates on the combined candidate.
- [x] Run the required 1.5-hour realistic single-user benchmark: 750 measured
  calls completed with zero errors/timeouts and project-count parity stayed
  exact. One task-count pair crossed a live inbox update.
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
- [#63](https://github.com/deverman/FocusRelayMCP/issues/63) — release tracker.

## After Release

Prioritize user-visible, low-risk improvements as isolated branches:

1. [#11](https://github.com/deverman/FocusRelayMCP/issues/11) — OmniFocus deep
   links in existing query output.
2. [#22](https://github.com/deverman/FocusRelayMCP/issues/22) — task added and
   modified timestamps and filters.
3. [#18](https://github.com/deverman/FocusRelayMCP/issues/18) — project planned
   dates and filters.
4. [#59](https://github.com/deverman/FocusRelayMCP/issues/59) — native task
   status filters.
5. [#62](https://github.com/deverman/FocusRelayMCP/issues/62) — configurable
   sorting.
6. [#75](https://github.com/deverman/FocusRelayMCP/issues/75) — migrate server
   text responses off deprecated MCP SDK overloads.

Treat [#73](https://github.com/deverman/FocusRelayMCP/issues/73), immediate IPC
cleanup, as an experiment rather than a release blocker. Keep it only if the
semantic, smoke, and realistic benchmarks show a defensible latency win without
new timeouts or reliability regressions.
