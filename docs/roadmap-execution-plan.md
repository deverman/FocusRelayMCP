# FocusRelay Roadmap Execution Plan

Last updated: 2026-08-03

GitHub issues own requirements, discussion, and validation evidence. This file
records only current sequencing and cross-issue dependencies.

## Current Focus

`v0.12.0-beta` shipped. Merged since: IPC hardening (#197), bounded
task-detail lookup (#172), project folder membership (#88), multi-name
resolution (#171), and both halves of #200. All of that is read-path work;
the mutation surface is unchanged since the release.

The next slice is [#173 — atomic heterogeneous task edit
plans](https://github.com/deverman/FocusRelayMCP/issues/173), whose
read-before-write cost #172 and #171 were sequenced to reduce. It is also the
first mutation work in the queue, and it deserves more caution than the
read-path slices behind it: a wrong query returns bad data the caller can
discard, while a wrong write changes the user's database.

## Delivery Order

1. [#173 — atomic heterogeneous task edit plans](https://github.com/deverman/FocusRelayMCP/issues/173)
   - Design the larger approved-workflow batch only after #172 and #171 reduce
     its read-before-write query cost.
   - First mutation slice since the release. Establish the failure and rollback
     story before the convenience of the batch: what a partially applied plan
     leaves behind, and how the caller learns which edits landed.
2. [#94 — discoverable MCP workflows](https://github.com/deverman/FocusRelayMCP/issues/94)
   - Continue measured client research after the shipped `process_inbox`
     vertical; add another prompt only when UAT demonstrates a reliable benefit.
3. [#82 — task/subtask creation](https://github.com/deverman/FocusRelayMCP/issues/82), then
   [#83 — project creation/conversion](https://github.com/deverman/FocusRelayMCP/issues/83)
   - Build on the consolidated edit surface, support safe project folder
     destinations, and retain duplicate/write safety.
4. [#93 — repetition support](https://github.com/deverman/FocusRelayMCP/issues/93)
   - After task creation and truthful drop behavior stabilize, establish complete
     schedule readback before adding create, edit, and lifecycle mutation slices.
5. [#130 — project tag membership and filtering](https://github.com/deverman/FocusRelayMCP/issues/130), then
   [#128 — create and assign missing tags](https://github.com/deverman/FocusRelayMCP/issues/128)
   - Query direct project membership by stable ID before creating missing root
     or nested tags during assignment.
6. [#87 — project-health filters](https://github.com/deverman/FocusRelayMCP/issues/87)
   - Reduce context before expanding project-review workflows. #88 moved to
     the front of the order; this is the intended home for stalled/health
     questions rather than widening batch resolution.
7. [#85 — safe Forecast contract](https://github.com/deverman/FocusRelayMCP/issues/85), then
   [#125 — Forecast-based attention](https://github.com/deverman/FocusRelayMCP/issues/125), then
   [#126 — broader ranked task search](https://github.com/deverman/FocusRelayMCP/issues/126)
   - Reuse one documented task-only Forecast classifier for attention ranking.
   - Keep search independent, broad, relevance-ranked, and lightweight.
8. [#92 — guided Homebrew setup](https://github.com/deverman/FocusRelayMCP/issues/92)
    - Reduce installation friction after the next product capabilities settle.
    - Covers the plug-in directory discovery and partial-install reporting
      left open by #200.
9. [#90 — command/session latency](https://github.com/deverman/FocusRelayMCP/issues/90)
    - The remaining measured command experiment.
10. [#206 — benchmark coverage for unmeasured tools](https://github.com/deverman/FocusRelayMCP/issues/206)
    - Partially shipped: `classify` now warns when a change touches a tool the
      suite cannot measure, which is the part that was costing real time. What
      remains is adding benchmarks for the six uncovered tools. Do that when a
      change to one of them actually needs measuring, not before.
11. Small independent query improvements: #11, #22, #18, #59, #62, #65,
    #66, #67, and #68.
12. Feasibility work for #10 custom perspectives and #16 planned-date writes.

## Standing Decisions

- Plugin URL dispatch through the Bridge plugin is the only architecture; #80
  removed the alternate runtime, development oracle, and dual-path benchmarks.
- FocusRelay targets terminal-based MCP clients. Desktop-app hosts are out of
  scope; #196 is parked and carries the evidence needed to resume it.
- #170 established one process-wide FIFO Bridge lane: one request executes, six
  may queue, and excess or expired work returns structured retryable errors.
- Query code uses documented Omni Automation APIs and native status semantics.
- One product branch plus one process/docs branch may be active.
- Merge small vertical PRs and complete headline UAT before freezing a release
  candidate.
- Keep #171, #172, #173, and further #94 prompt work outside v0.12.0-beta so
  the Bridge coordinator and stdio lifecycle ship on one certifiable fingerprint.
- Run the realistic 1.5-hour suite once per frozen production fingerprint.
- Performance work must show a user-relevant latency/reliability win after
  semantic correctness passes.
- Workflow UAT showed that repeated detail and catalog lookups cost more than
  coordinator handoff. Prefer bounded server-side resolution through #172 and
  #171 before proposing a broader query-engine optimization.
- Public tool count and serialized catalog size are directional optimization
  evidence; they must not override correctness, routing reliability, or real
  and perceived performance.
- #95 established the current development and release flow; #90 owns the
  remaining command/session latency investigation.
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

## Release Reference

- Current release: [`v0.12.0-beta`](https://github.com/deverman/FocusRelayMCP/releases/tag/v0.12.0-beta)
- Release notes: [`release-notes-v0.12.0-beta.md`](release-notes-v0.12.0-beta.md)
- Release engineering: [`release-engineering-checklist.md`](release-engineering-checklist.md)
- Development validation: [`development-workflow.md`](development-workflow.md)
- User-facing changes: [`../CHANGELOG.md`](../CHANGELOG.md)
