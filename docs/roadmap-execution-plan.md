# FocusRelay Roadmap Execution Plan

Last updated: 2026-07-24

GitHub issues own requirements, discussion, and validation evidence. This file
records only current sequencing and cross-issue dependencies.

## Delivery Order

1. [#129 — task dropping and restoration](https://github.com/deverman/FocusRelayMCP/issues/129)
   - Keep dropping distinct from completing so cleanup does not create false
     completion history.
2. [#138 — mark projects reviewed](https://github.com/deverman/FocusRelayMCP/issues/138)
   - Prove native Mark Reviewed parity with disposable projects before allowing
     the semantic `reviewedNow` mutation in production.
3. [#144 — all-or-nothing bulk mutation preflight](https://github.com/deverman/FocusRelayMCP/issues/144)
   - Block release until every target resolves and is eligible before any
     task or project mutation applies or saves.
4. [#143 — reject unknown MCP arguments](https://github.com/deverman/FocusRelayMCP/issues/143)
   - Fail closed at the public MCP boundary so invalid filters cannot silently
     become plausible unfiltered queries.
5. [#145 — Review perspective status filtering](https://github.com/deverman/FocusRelayMCP/issues/145), then
   [#146 — query-bound pagination cursors](https://github.com/deverman/FocusRelayMCP/issues/146), then
   [#69 — project name search](https://github.com/deverman/FocusRelayMCP/issues/69)
   - Make project discovery semantically scoped and pagination-safe before
     expanding the read-before-write lookup contract.
6. [#161 — reject unsupported output fields](https://github.com/deverman/FocusRelayMCP/issues/161), then
   [#94 — Discoverable MCP workflows](https://github.com/deverman/FocusRelayMCP/issues/94)
   - Fail closed when clients request unsupported fields before encoding daily
     focus, weekly review, inbox processing, and project planning workflows.
7. [#82 — Task/subtask creation](https://github.com/deverman/FocusRelayMCP/issues/82), then
   [#83 — project creation/conversion](https://github.com/deverman/FocusRelayMCP/issues/83)
   - Build on the consolidated edit surface, support safe project folder
     destinations, and retain duplicate/write safety.
8. [#93 — repetition support](https://github.com/deverman/FocusRelayMCP/issues/93)
   - After task creation and truthful drop behavior stabilize, establish complete
     schedule readback before adding create, edit, and lifecycle mutation slices.
9. [#70 — parent-aware tag discovery](https://github.com/deverman/FocusRelayMCP/issues/70), then
   [#130 — project tag membership and filtering](https://github.com/deverman/FocusRelayMCP/issues/130), then
   [#128 — create and assign missing tags](https://github.com/deverman/FocusRelayMCP/issues/128)
   - Resolve root and nested tags safely, query direct project membership by
     stable ID, then create missing tags during assignment.
10. [#88 — project folder membership](https://github.com/deverman/FocusRelayMCP/issues/88), then
   [#87 — project-health filters](https://github.com/deverman/FocusRelayMCP/issues/87)
   - Reduce context before expanding project-review workflows.
11. [#85 — safe Forecast contract](https://github.com/deverman/FocusRelayMCP/issues/85), then
   [#125 — Forecast-based attention](https://github.com/deverman/FocusRelayMCP/issues/125), then
   [#126 — broader ranked task search](https://github.com/deverman/FocusRelayMCP/issues/126)
   - Reuse one documented task-only Forecast classifier for attention ranking.
   - Keep search independent, broad, relevance-ranked, and lightweight.
12. Small independent query improvements: #11, #22, #18, #59, and #62.
13. Feasibility work for #10 custom perspectives and #16 planned-date writes.

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
- Review-bankruptcy UAT measured project queries at 0.38–0.89 seconds; its
  multi-minute delay came from inconsistent pagination, large ID/result
  payloads, manual target reconstruction, and retry work. Reduce returned
  context through scoped queries and existing #69/#87 work before proposing a
  raw query-engine optimization.
- Public tool count and serialized catalog size are directional optimization
  evidence; they must not override correctness, routing reliability, or real
  and perceived performance.
- #95 established the current development and release flow; #90 owns the
  remaining command/session latency investigation.
- Raw benchmark artifacts are not roadmap content and belong under `.build`.

## Release Reference

- Current release: [`v0.11.0-beta`](https://github.com/deverman/FocusRelayMCP/releases/tag/v0.11.0-beta)
- Release engineering: [`release-engineering-checklist.md`](release-engineering-checklist.md)
- Development validation: [`development-workflow.md`](development-workflow.md)
- User-facing changes: [`../CHANGELOG.md`](../CHANGELOG.md)
