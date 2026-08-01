# FocusRelay Roadmap Execution Plan

Last updated: 2026-08-01

GitHub issues own requirements, discussion, and validation evidence. This file
records only current sequencing and cross-issue dependencies.

## Current Focus

`v0.12.0-beta` shipped. IPC hardening (#197), the plug-in diagnostic half of
#200, and bounded task-detail lookup (#172) have merged. The next slice is
[#88 — project folder membership](https://github.com/deverman/FocusRelayMCP/issues/88),
which #171 now depends on.

## Delivery Order

1. [#88 — project folder membership](https://github.com/deverman/FocusRelayMCP/issues/88)
   - Moved ahead of #171. #171 requires path/parent information so duplicate
     names stay distinguishable, and `ProjectItem` carries no folder or path
     field today; tags already expose parent and path.
2. [#171 — multi-name project and tag resolution](https://github.com/deverman/FocusRelayMCP/issues/171)
   - Resolve a bounded set of requested names through the existing catalog cache
     instead of repeating full catalog queries. Depends on #88 for project
     paths. Open question at start: whether batch mode accepts
     `includeTaskCounts` — measured cost on a 392-project database is roughly
     +1.3 s and about double the response bytes, and project health has its own
     issue in #87.
3. [#173 — atomic heterogeneous task edit plans](https://github.com/deverman/FocusRelayMCP/issues/173)
   - Design the larger approved-workflow batch only after #172 and #171 reduce
     its read-before-write query cost.
4. [#94 — discoverable MCP workflows](https://github.com/deverman/FocusRelayMCP/issues/94)
   - Continue measured client research after the shipped `process_inbox`
     vertical; add another prompt only when UAT demonstrates a reliable benefit.
5. [#82 — task/subtask creation](https://github.com/deverman/FocusRelayMCP/issues/82), then
   [#83 — project creation/conversion](https://github.com/deverman/FocusRelayMCP/issues/83)
   - Build on the consolidated edit surface, support safe project folder
     destinations, and retain duplicate/write safety.
6. [#93 — repetition support](https://github.com/deverman/FocusRelayMCP/issues/93)
   - After task creation and truthful drop behavior stabilize, establish complete
     schedule readback before adding create, edit, and lifecycle mutation slices.
7. [#130 — project tag membership and filtering](https://github.com/deverman/FocusRelayMCP/issues/130), then
   [#128 — create and assign missing tags](https://github.com/deverman/FocusRelayMCP/issues/128)
   - Query direct project membership by stable ID before creating missing root
     or nested tags during assignment.
8. [#87 — project-health filters](https://github.com/deverman/FocusRelayMCP/issues/87)
   - Reduce context before expanding project-review workflows. #88 moved to
     the front of the order; this is the intended home for stalled/health
     questions rather than widening batch resolution.
9. [#85 — safe Forecast contract](https://github.com/deverman/FocusRelayMCP/issues/85), then
   [#125 — Forecast-based attention](https://github.com/deverman/FocusRelayMCP/issues/125), then
   [#126 — broader ranked task search](https://github.com/deverman/FocusRelayMCP/issues/126)
   - Reuse one documented task-only Forecast classifier for attention ranking.
   - Keep search independent, broad, relevance-ranked, and lightweight.
10. [#92 — guided Homebrew setup](https://github.com/deverman/FocusRelayMCP/issues/92)
    - Reduce installation friction after the next product capabilities settle.
    - Covers the plug-in directory discovery and partial-install reporting
      left open by #200.
11. [#90 — command/session latency](https://github.com/deverman/FocusRelayMCP/issues/90)
    - The remaining measured command experiment.
12. Small independent query improvements: #11, #22, #18, #59, #62, #65,
    #66, #67, and #68.
13. Feasibility work for #10 custom perspectives and #16 planned-date writes.

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

## Release Reference

- Current release: [`v0.12.0-beta`](https://github.com/deverman/FocusRelayMCP/releases/tag/v0.12.0-beta)
- Release notes: [`release-notes-v0.12.0-beta.md`](release-notes-v0.12.0-beta.md)
- Release engineering: [`release-engineering-checklist.md`](release-engineering-checklist.md)
- Development validation: [`development-workflow.md`](development-workflow.md)
- User-facing changes: [`../CHANGELOG.md`](../CHANGELOG.md)
