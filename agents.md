# FocusRelay Agent Guide

## Before Changing Code

1. Work from a GitHub issue with one bounded outcome.
2. Declare the validation impact: `docs`, `package`, `server-wire`, `mutation`,
   `query`, `performance`, or `transport-reliability`.
3. Write one user-facing acceptance journey before implementation.
4. Keep work in progress to one product branch plus one process/docs branch.

Use `docs/development-workflow.md` for the validation and release procedure.
When available, run:

```bash
swift run focusrelay-dev validate --impact <impact> --base origin/master
```

Do not substitute a larger validation tier merely because it feels safer. Use
the smallest tier that covers the changed production behavior; ambiguous
changes use the safer tier.

## Swift And Tests

- Use Swift Testing (`Testing`, `@Test`, `#expect`, `#require`).
- Do not add `swift-testing` as a package dependency.
- Add or update tests when functionality changes.
- Disabled live tests must use Swift Testing traits so they are reported as
  skipped. Never return early and let an unexecuted live test appear to pass.
- Test the real boundary that users exercise. MCP schema or decoding changes
  require direct MCP argument/wire coverage, not only model round trips.
- Mutation work requires a reversible live write/verify/restore for each
  affected behavior before release UAT.

## Omni Automation Contract

- Production query paths use documented Omni Automation APIs only.
- If a property or collection is absent from the official OmniFocus
  documentation, do not use it in core query logic.
- Follow `docs/omni-automation-contract.md` and prefer:
  - `flattenedTasks` and `task.taskStatus`
  - `flattenedProjects` and `project.status`
- Task availability must respect the task, its parent tasks, and its project.
- Use the shared status helpers in `BridgeLibrary.js`; do not recreate status
  from `blocked`, defer dates, or convenience booleans.
- Implementation parity is not an independent oracle. For status semantics,
  compare with native OmniFocus behavior before benchmarking.

## Plugin Changes

Install the bridge only with:

```bash
./scripts/install-plugin.sh
```

After installation, fully restart OmniFocus because it caches plugin
JavaScript:

```bash
osascript -e 'tell application "OmniFocus" to quit' && sleep 2 && open -a "OmniFocus"
```

Restart once at the beginning of a live validation session, then run health,
semantic, and UAT checks against that same ready session.

## Performance And Reliability

- Change one variable per branch. Do not mix query optimization, transport,
  approval UX, caching, and benchmark tooling.
- Keep a performance change only when semantic gates pass and measurements show
  a defensible user-relevant win without reliability regression.
- Require an explicit benchmark profile. Never default to an hours-long run.
- Use `canary` for complete scenario coverage, `smoke` for a 10-minute targeted
  run, `release` once on the frozen release candidate, and `stress` only for a
  documented diagnostic question.
- Production-path releases keep the 1.5-hour realistic suite, but unchanged
  evidence is reused by production fingerprint. Documentation-only commits do
  not invalidate it.
- Raw benchmark artifacts belong under `.build/benchmarks`; commit only an
  intentionally selected summary.

## Release And Workspace Hygiene

- GitHub issues are the source of truth for deliverables and validation
  evidence. Keep `docs/roadmap-execution-plan.md` concise.
- Merge small vertical PRs, complete user-facing UAT, then freeze one release
  candidate before the long suite.
- Do not update multiple current-status documents with the same evidence.
- After merge, report merged branches/worktrees and remove them only with an
  explicit apply action.
- For Homebrew, update once, then set `HOMEBREW_NO_AUTO_UPDATE=1` for subsequent
  checks. Untap/retap only when stale tap state is proven.
- External commands must stream output or emit a heartbeat at least every 30
  seconds. Record subprocess time separately from approval and tool-wrapper
  time. Retry only diagnosed transient failures with a bounded attempt count.

## Current Runtime Facts

- Swift is selected from `.swift-version` through Swiftly.
- The MCP server detects `TimeZone.current.identifier` and sends it as
  `userTimeZone` in bridge requests.
- Projects and tags use the actor-based `CatalogCache` with a five-minute TTL;
  tasks are intentionally uncached.
- Plugin URL dispatch is the only production transport; the JXA dispatch
  option was removed in #80. The pure-JXA query engine remains only as
  internal parity/benchmark infrastructure, not a production path. Production
  semantic gates use plugin and native contracts; pass `--include-jxa-parity`
  only for developer diagnostics.
