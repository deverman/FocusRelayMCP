# FocusRelay Roadmap Execution Plan

Last updated: 2026-07-15

GitHub issues own requirements, discussion, and validation evidence. This file
records only current sequencing and cross-issue dependencies.

## Delivery Order

1. [#95 — Kaizen development and release flow](https://github.com/deverman/FocusRelayMCP/issues/95)
   - Establish impact-based validation, truthful live-test reporting,
     developer workflow tooling, lean CI, and one frozen-RC reliability run.
   - Keep #90 as the focused command/session latency investigation.
2. [#75 — Swift MCP SDK maintenance](https://github.com/deverman/FocusRelayMCP/issues/75)
   - Upgrade to `0.12.1` and remove deprecated response construction before
     adding prompt responses.
3. [#91 — Smaller edit interface](https://github.com/deverman/FocusRelayMCP/issues/91)
   - Preserve or improve Kimi and comparison-model tool selection.
4. [#94 — Discoverable MCP workflows](https://github.com/deverman/FocusRelayMCP/issues/94)
   - Research daily focus, weekly review, inbox processing, and project
     planning before fixing the public prompt set.
5. [#82 — Task/subtask creation](https://github.com/deverman/FocusRelayMCP/issues/82), then
   [#83 — project creation/conversion](https://github.com/deverman/FocusRelayMCP/issues/83)
   - Build on the consolidated edit surface and retain duplicate/write safety.
6. [#88 — project folder membership](https://github.com/deverman/FocusRelayMCP/issues/88), then
   [#87 — project-health filters](https://github.com/deverman/FocusRelayMCP/issues/87)
   - Reduce context before expanding project-review workflows.
7. [#85 — safe Forecast contract](https://github.com/deverman/FocusRelayMCP/issues/85)
8. Small independent query improvements: #11, #22, #18, #59, and #62.
9. [#93 — repetition support](https://github.com/deverman/FocusRelayMCP/issues/93)
   after creation and editing stabilize.
10. Feasibility work for #10 custom perspectives and #16 planned-date writes.

## Standing Decisions

- Plugin URL dispatch is the supported production transport. #80 tracks
  removing supported JXA dispatch; JXA is not a second production path.
- Query code uses documented Omni Automation APIs and native status semantics.
- One product branch plus one process/docs branch may be active.
- Merge small vertical PRs and complete headline UAT before freezing a release
  candidate.
- Run the realistic 1.5-hour suite once per frozen production fingerprint.
- Performance work must show a user-relevant latency/reliability win after
  semantic correctness passes.
- Raw benchmark artifacts are not roadmap content and belong under `.build`.

## Release Reference

- Current release: [`v0.10.0-beta`](https://github.com/deverman/FocusRelayMCP/releases/tag/v0.10.0-beta)
- Release engineering: [`release-engineering-checklist.md`](release-engineering-checklist.md)
- Development validation: [`development-workflow.md`](development-workflow.md)
- User-facing changes: [`../CHANGELOG.md`](../CHANGELOG.md)
