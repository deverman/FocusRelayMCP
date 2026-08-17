# FocusRelay Roadmap Execution Plan

Last updated: 2026-08-16

GitHub issues own requirements, discussion, and validation evidence. This file
records only current sequencing and cross-issue dependencies.

## Current Focus

The next milestone is **Trustworthy daily use**. It favors visible user
outcomes over speculative infrastructure and delivers one issue at a time,
with user-facing UAT before the next issue starts.

The active slice is [#92 — guided Homebrew
setup](https://github.com/deverman/FocusRelayMCP/issues/92). It replaces
duplicated manual plug-in copy instructions with one Swift setup implementation
used by the installed CLI and the thin development script. It adds no MCP tool.

## Delivery Order

1. [#92 — guided Homebrew setup](https://github.com/deverman/FocusRelayMCP/issues/92)
   - Provide one guided setup command and one Swift installer implementation.
   - Keep `scripts/install-plugin.sh` as the required thin development entry
     point so installation behavior cannot drift.
2. [#85 — truthful Forecast contract](https://github.com/deverman/FocusRelayMCP/issues/85)
   - Prefer the narrowest truthful task-only result with explicit exclusions
     when documented APIs cannot reproduce native Forecast exactly.
3. [#11 — OmniFocus URLs](https://github.com/deverman/FocusRelayMCP/issues/11)
   - Add an optional native `url` field to existing task and project outputs;
     do not add a tool.
4. [#82 — safe task/subtask creation](https://github.com/deverman/FocusRelayMCP/issues/82)
   - Use one shared creation implementation with equivalent CLI/MCP adapters,
     previews, verification, and duplicate safety.

After #82 UAT, decide whether observed use justifies [#83 — project creation
and conversion](https://github.com/deverman/FocusRelayMCP/issues/83). All other
feature issues remain unmilestoned until user evidence promotes them.

## Evidence-Gated Work

- The bounded #94 `process_inbox` refinement shipped through #219 and the
  umbrella issue is closed. Open a new bounded prompt issue only after
  independent-user evidence supports another workflow.
- #173 is not in the delivery order. Current grouped, sequential, verified
  mutations meet the observed workflow need; an atomic heterogeneous plan has
  no demonstrated user benefit.
- #90, #196, #206's remaining benchmark coverage, and #216 resume only from a
  supported user journey or repeatable failure. Do not build diagnostics ahead
  of a caller.
- #68 resumes only with a current count-freshness reproduction.
- Do not resurrect a broad query-engine refactor. Extract shared predicates
  only when a scheduled feature needs them.

## Standing Decisions

- Plugin URL dispatch through the Bridge plugin is the only architecture; #80
  removed the alternate runtime, development oracle, and dual-path benchmarks.
- FocusRelay targets terminal-based MCP clients. Desktop-app hosts are out of
  scope; #196 is parked and carries the evidence needed to resume it.
- #170 established one process-wide FIFO Bridge lane: one request executes, six
  may queue, and excess or expired work returns structured retryable errors.
- Query code uses documented Omni Automation APIs and native status semantics.
- CLI and MCP are equivalent product interfaces. They share typed services,
  workflow definitions, validation, and output shaping; protocol adapters stay
  thin and receive paired contract tests.
- One product branch plus one process/docs branch may be active.
- Merge small vertical PRs and complete headline UAT before freezing a release
  candidate.
- Run the realistic 1.5-hour suite once per frozen production fingerprint.
- Performance work must show a user-relevant latency/reliability win after
  semantic correctness passes.
- Workflow UAT showed that repeated detail and catalog lookups cost more than
  coordinator handoff. Prefer bounded server-side resolution through #172 and
  #171 before proposing a broader query-engine optimization.
- Public tool count and serialized catalog size are directional optimization
  evidence; they must not override correctness, routing reliability, or real
  and perceived performance.
- #95 established the current development and release flow.
- Raw benchmark artifacts are not roadmap content and belong under `.build`.
- Benchmark a change on the path it changed. A suite that does not exercise the
  changed tool cannot clear it, and a single stalled call on a noisy host is one
  observation rather than a verdict. `focusrelay-dev classify` reports the gap.
- Fix defects that have a reproduction. A latent risk with no reachable failure
  is not worth a refactor: #207 was closed after its fix turned out to change
  233 lines while fixing nothing reachable. Prefer a regression test at the
  point of the near-miss, which is what #88 already did.
- Do not build tooling ahead of a caller. #206's verdict engine was written,
  merged, and deleted unused; only the part wired into `classify` earned its
  place.
- Remove nearby dead scaffolding only when a scheduled change already touches
  that path and tests prove it unreachable; do not create broad cleanup work.

## Release Reference

- Current release: [`v0.12.0-beta`](https://github.com/deverman/FocusRelayMCP/releases/tag/v0.12.0-beta)
- Release notes: [`release-notes-v0.12.0-beta.md`](release-notes-v0.12.0-beta.md)
- Release engineering: [`release-engineering-checklist.md`](release-engineering-checklist.md)
- Development validation: [`development-workflow.md`](development-workflow.md)
- User-facing changes: [`../CHANGELOG.md`](../CHANGELOG.md)
