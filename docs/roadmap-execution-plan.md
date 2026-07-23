# FocusRelay Roadmap Execution Plan

Last updated: 2026-07-23

GitHub issues own requirements, discussion, and validation evidence. This file
records only current sequencing and cross-issue dependencies.

## Delivery Order

1. [#129 — task dropping and restoration](https://github.com/deverman/FocusRelayMCP/issues/129)
   - Keep dropping distinct from completing so cleanup does not create false
     completion history.
2. [#138 — mark projects reviewed](https://github.com/deverman/FocusRelayMCP/issues/138)
   - Prove native Mark Reviewed parity with disposable projects before allowing
     the semantic `reviewedNow` mutation in production.
3. [#94 — Discoverable MCP workflows](https://github.com/deverman/FocusRelayMCP/issues/94)
   - Research daily focus, weekly review, inbox processing, and project
     planning before fixing the public prompt set.
4. [#82 — Task/subtask creation](https://github.com/deverman/FocusRelayMCP/issues/82), then
   [#83 — project creation/conversion](https://github.com/deverman/FocusRelayMCP/issues/83)
   - Build on the consolidated edit surface, support safe project folder
     destinations, and retain duplicate/write safety.
5. [#93 — repetition support](https://github.com/deverman/FocusRelayMCP/issues/93)
   - After task creation and truthful drop behavior stabilize, establish complete
     schedule readback before adding create, edit, and lifecycle mutation slices.
6. [#70 — parent-aware tag discovery](https://github.com/deverman/FocusRelayMCP/issues/70), then
   [#130 — project tag membership and filtering](https://github.com/deverman/FocusRelayMCP/issues/130), then
   [#128 — create and assign missing tags](https://github.com/deverman/FocusRelayMCP/issues/128)
   - Resolve root and nested tags safely, query direct project membership by
     stable ID, then create missing tags during assignment.
7. [#88 — project folder membership](https://github.com/deverman/FocusRelayMCP/issues/88), then
   [#87 — project-health filters](https://github.com/deverman/FocusRelayMCP/issues/87)
   - Reduce context before expanding project-review workflows.
8. [#85 — safe Forecast contract](https://github.com/deverman/FocusRelayMCP/issues/85), then
   [#125 — Forecast-based attention](https://github.com/deverman/FocusRelayMCP/issues/125), then
   [#126 — broader ranked task search](https://github.com/deverman/FocusRelayMCP/issues/126)
   - Reuse one documented task-only Forecast classifier for attention ranking.
   - Keep search independent, broad, relevance-ranked, and lightweight.
9. Small independent query improvements: #11, #22, #18, #59, and #62.
10. Feasibility work for #10 custom perspectives and #16 planned-date writes.

## Standing Decisions

- Plugin URL dispatch through the Bridge plugin is the only architecture; #80
  removed the alternate runtime, development oracle, and dual-path benchmarks.
- Query code uses documented Omni Automation APIs and native status semantics.
- One product branch plus one process/docs branch may be active.
- Merge small vertical PRs and complete headline UAT before freezing a release
  candidate.
- Run the realistic 1.5-hour suite once per frozen production fingerprint.
- Performance work must show a user-relevant latency/reliability win after
  semantic correctness passes.
- Public tool count and serialized catalog size are directional optimization
  evidence; they must not override correctness, routing reliability, or real
  and perceived performance.
- #95 established the current development and release flow; #90 owns the
  remaining command/session latency investigation.
- Raw benchmark artifacts are not roadmap content and belong under `.build`.

## Release Reference

- Current release: [`v0.10.1-beta`](https://github.com/deverman/FocusRelayMCP/releases/tag/v0.10.1-beta)
- Release engineering: [`release-engineering-checklist.md`](release-engineering-checklist.md)
- Development validation: [`development-workflow.md`](development-workflow.md)
- User-facing changes: [`../CHANGELOG.md`](../CHANGELOG.md)
