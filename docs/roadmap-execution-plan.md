# FocusRelayMCP Roadmap Execution Plan

Last updated: 2026-07-14

This document tracks the repository cleanup, release preparation, and next product work identified by the July 2026 repository and GitHub audit. GitHub issues are the source of truth for individual deliverables; this file records sequencing, dependencies, and audit decisions across those issues.

## Current Baseline

- `master` is clean and matches `origin/master` at `74190b5`; the combined local
  release candidate is `integration/v0.10.0-beta-rc`.
- The latest `master` GitHub Actions run passed.
- The combined candidate passes 126 Swift Testing tests with Swiftly-managed
  Swift 6.3.3, including the live OmniFocus integration tests enabled in the
  current environment.
- `master` is 22 commits ahead of the latest release, `v0.9.4beta`.

## Phase 1: Reconcile Existing GitHub Work

### PR #51 and PR #52 dependency audit

- [x] Compare PR #51 with merged PR #57 at the helper, operation, response, save, preview, and verification levels.
- [x] Confirm every mutation operation remains wired through the final shared helpers.
- [x] Confirm the changed merge order did not create a code-to-documentation mismatch.
- [x] Compare PR #52 with merged PR #56 and the current mutation workflow documentation.
- [x] Run JavaScript syntax validation and `swift test` against the final `master` implementation.
- [x] Close PRs #51 and #52 only after the audit result is documented on each PR.

Audit result: PR #57 is the complete replacement for PR #51. It retains shared task, project, tag, and folder indexes; shared response envelopes; and one mutation executor used by all seven v1 task/project mutation operations. PR #56 is the maintained replacement for PR #52. Merging its public-contract documentation before the internal PR #57 refactor was safe because the refactor preserved CLI/MCP request and response semantics. PR #54 subsequently added `list_folders` and updated the workflow documentation that originally treated public folder discovery as unavailable.

### PR #25 integration audit

- [x] Confirm the shared date decoder is present on `master`.
- [x] Confirm both bridge and JXA decoding paths use the shared decoder.
- [x] Confirm the PR's regression test file is present on `master`.
- [x] Confirm standard and fractional-second ISO8601 decoder tests pass.
- [x] Document the integration path and contributor credit on PR #25, then close it as integrated elsewhere.

Audit result: the date decoder and the complete 188-line regression test file from PR #25 are byte-for-byte present on `master`. Both `BridgeClient` and `OmniAutomationService` still construct their decoders through `BridgeDateDecoding.makeJSONDecoder()`. The work landed through the history of merged PR #37 with contributor credit retained in commit `bb4da93`.

### Issue #47 reliability closeout

- [x] Confirm PR #49 added actionable pickup-state timeout diagnostics and tests.
- [x] Reproduce current behavior with the plugin built from `master` and OmniFocus fully restarted.
- [x] Run repeated safe mutation previews and record timeout/pickup-state results.
- [x] Decide whether the original issue is complete, needs a narrower follow-up, or still requires implementation.
- [x] Update and close issue #47 only when the evidence supports closure.

Closeout result: the current plugin was installed to both detected OmniFocus plugin locations and OmniFocus was fully restarted. `bridge-health-check` succeeded. Five consecutive `update_projects` previews succeeded without timeouts, followed by a verified `flagged=false -> true` write and verified restoration to `false` on project `gL3zoHCAyW_`. No response was stranded and the original state was restored. The earlier timeout was not proven deterministic; future occurrences should open a focused issue containing the `pickupState`, request/response/lock state, and `strandedRedispatched` diagnostics added by PR #49.

## Phase 2: Restore Roadmap And Release Hygiene

- [x] Close or supersede stale PRs after the Phase 1 review.
- [x] Replace stale entries in `NEXT-STEPS.md` with a current release checklist
  and issue index.
- [x] Rewrite `SESSION_NOTES.md` around the current local release candidate and
  authoritative Homebrew checkout.
- [x] Populate the `CHANGELOG.md` Unreleased section and correct the stale
  `1.0.0` placeholder to the actual `v0.9.0-beta` tag and date.
- [x] Add a version-reporting issue covering `focusrelay --version`, release injection, and the MCP server's hard-coded `0.1.0` version: [#58](https://github.com/deverman/FocusRelayMCP/issues/58).
- [x] Create a release tracker for the 22 commits currently ahead of `v0.9.4beta`: [#63](https://github.com/deverman/FocusRelayMCP/issues/63).
- [x] Run the required semantic gates and realistic single-user validation before tagging.
- [x] Record sparse MCP field updates, including flag changes, as the explicitly
  accepted beta known issue [#89](https://github.com/deverman/FocusRelayMCP/issues/89).
- [ ] Update the external Homebrew tap with the release asset's actual SHA256 and verify a clean reinstall.

### Confirmed release blockers

- [ ] **P1** [#71](https://github.com/deverman/FocusRelayMCP/issues/71): make mutation save and per-target failures impossible to report as success. The fix has unit, JavaScriptCore, live write/restore, combined-candidate, and green GitHub CI evidence in PR #84; merge it before closure.
- [ ] **P2** [#61](https://github.com/deverman/FocusRelayMCP/issues/61): align project available-task counts with shared task availability semantics. The fix has documented bridge/JXA semantics, root-task exclusion, unit/live tests, semantic gates, smoke/realistic validation, and green PR #84 CI; merge it before closure.
- [ ] **P2** [#64](https://github.com/deverman/FocusRelayMCP/issues/64): fix CI artifact upload, manual release version selection, and prerelease metadata. A `0.10.0-beta` archive/checksum was validated end to end and PR #84 uploaded its release binary successfully; merge before final release-workflow validation and closure.
- [ ] **P2** [#72](https://github.com/deverman/FocusRelayMCP/issues/72): remove the stale checked-in formula and validate the authoritative tap at `/Users/deverman/Documents/code/homebrew-focus-relay`. Ownership changes are integrated locally; tap draft PR #1 corrects formula style, the packaged plugin path, the copy-paste install command, and the read/write description, and passes real tap-context style, strict audit, and install resolution. Merge both repositories, then validate the actual release SHA256.
- [ ] **Release prerequisite** [#58](https://github.com/deverman/FocusRelayMCP/issues/58): unify CLI, MCP, plugin, and release version metadata. PR #84 synchronizes full SemVer across binary/MCP/plugin health, preserves the numeric OmniFocus manifest core, and passes release injection, packaging, and CI; merge before closure.
- [ ] **Release UX** [#76](https://github.com/deverman/FocusRelayMCP/issues/76): keep internal bridge health and inbox probes out of the model-facing tool catalog. PR #84 exposes 14 product tools, retains three CLI diagnostics, passes a direct MCP handshake and the 126-test suite, and has green CI; merge before closure.
- [ ] **P2** [#77](https://github.com/deverman/FocusRelayMCP/issues/77): publish one complete shared task-filter schema for `list_tasks` and `get_task_counts`. PR #84 covers all 20 `TaskFilter` fields and passes direct `tools/list`, the 126-test suite, and CI; merge before closure.
- [ ] **P2** [#78](https://github.com/deverman/FocusRelayMCP/issues/78): correct mutation safety annotations and make preview/write defaults explicit. PR #84 marks all seven mutation tools destructive and non-idempotent, locks the contract with tests, and has green CI; merge before closure.
- [ ] **P2** [#79](https://github.com/deverman/FocusRelayMCP/issues/79): make advertised task search filter names and notes in both list and count paths. PR #84 has deterministic plugin/JXA tests, positive live-search evidence, semantic gates, smoke/realistic validation, and green CI; merge before closure.
- [ ] **P2** [#81](https://github.com/deverman/FocusRelayMCP/issues/81): prevent list-task benchmarks from silently skipping half their declared scenarios. PR #84 rotates per transport pair, fails incomplete measured coverage, passes deterministic tests and corrected smoke coverage, and has green CI; merge before closure.
- [ ] **P2** [#86](https://github.com/deverman/FocusRelayMCP/issues/86): match OmniFocus's effective flagged-item semantics. The release candidate now uses documented `task.effectiveFlagged`, preserves the local writable `flagged` field, excludes invisible project roots from action counts, and adds an independent native OmniFocus gate. Unit/live tests, all semantic gates, two 10-minute smokes, and a 1.5-hour realistic suite pass; merge PR #84 before closure.

### Swift toolchain alignment

- Tracking issue: [#74](https://github.com/deverman/FocusRelayMCP/issues/74).
- [x] Confirm Swiftly 1.1.3 has Swift 6.3.3 installed and `swift-latest.xctoolchain` points to it.
- [x] Implement a checked-in `.swift-version` with `6.3.3` on local branch `chore/swift-6.3.3`.
- [x] Raise `swift-tools-version` to 6.3 on that branch.
- [x] Configure both CI and release workflows to install the `.swift-version`
  toolchain through Swiftly 1.1.3 and verify Swift 6.3.3 before building.
- [x] Verify the Swiftly shim selects Swift 6.3.3 from the project directory.
- [x] Verify workflow YAML and run the 98-test suite with the Swiftly shim.
- [x] Integrate the isolated toolchain branch into the local release candidate.
- [x] Publish the toolchain change in draft release candidate
  [#84](https://github.com/deverman/FocusRelayMCP/pull/84) and pass its clean
  GitHub CI build, test, release-build, and artifact-upload job.
- [ ] Merge the release candidate before tagging.

All live semantic gates pass, including the native effective-flag contract added
after UAT exposed #86. The native gate is intentionally independent of the
plugin and JXA implementations, preventing transport parity from agreeing on
the same incorrect product semantics.

## Phase 3: Create Missing Roadmap Issues

Create focused issues without combining unrelated variables or duplicating existing issues.

- [x] Task status filters using native `task.taskStatus` semantics: [#59](https://github.com/deverman/FocusRelayMCP/issues/59).
- [x] Configurable task/project sorting: [#62](https://github.com/deverman/FocusRelayMCP/issues/62).
- [x] Task/project `hasNote` filtering: [#65](https://github.com/deverman/FocusRelayMCP/issues/65).
- [x] Exact-day `dueOn` and `deferOn` filters: [#66](https://github.com/deverman/FocusRelayMCP/issues/66).
- [x] Parent/child task hierarchy fields: [#67](https://github.com/deverman/FocusRelayMCP/issues/67).
- [x] Inbox scope/view contract cleanup: [#60](https://github.com/deverman/FocusRelayMCP/issues/60).
- [x] Project available-count parity with task availability semantics: [#61](https://github.com/deverman/FocusRelayMCP/issues/61).
- [x] Count freshness guidance and diagnostics: [#68](https://github.com/deverman/FocusRelayMCP/issues/68).
- [x] CLI/MCP version reporting and release metadata: [#58](https://github.com/deverman/FocusRelayMCP/issues/58).
- [x] Project search: [#69](https://github.com/deverman/FocusRelayMCP/issues/69).
- [x] Tag search: [#70](https://github.com/deverman/FocusRelayMCP/issues/70).
- [x] CI/release packaging correction: [#64](https://github.com/deverman/FocusRelayMCP/issues/64).
- [x] Homebrew formula ownership/correctness: [#72](https://github.com/deverman/FocusRelayMCP/issues/72).
- [x] Shared task-filter schema parity: [#77](https://github.com/deverman/FocusRelayMCP/issues/77).
- [x] Truthful mutation safety annotations: [#78](https://github.com/deverman/FocusRelayMCP/issues/78).
- [x] Advertised task-search behavior: [#79](https://github.com/deverman/FocusRelayMCP/issues/79).
- [x] Production transport consolidation follow-up: [#80](https://github.com/deverman/FocusRelayMCP/issues/80).
- [x] Complete benchmark scenario rotation: [#81](https://github.com/deverman/FocusRelayMCP/issues/81).
- [x] Safe task creation: [#82](https://github.com/deverman/FocusRelayMCP/issues/82).
- [x] Safe project creation: [#83](https://github.com/deverman/FocusRelayMCP/issues/83).
- [x] Forecast-query contract and limitation handling: [#85](https://github.com/deverman/FocusRelayMCP/issues/85).
- [x] Effective flagged-item semantics: [#86](https://github.com/deverman/FocusRelayMCP/issues/86).
- [x] Server-side project-health filters: [#87](https://github.com/deverman/FocusRelayMCP/issues/87).
- [x] Project folder membership and root filtering: [#88](https://github.com/deverman/FocusRelayMCP/issues/88).
- [x] Sparse MCP task/project mutation decoding: [#89](https://github.com/deverman/FocusRelayMCP/issues/89).

Issues #82 and #83 are post-beta roadmap enhancements and do not block
`v0.10.0-beta`. Each still requires API, duplicate-safety, test, and benchmark
acceptance work before its own release.

Issue #89 is the first post-beta correctness fix. The user explicitly accepted
it as a documented `v0.10.0-beta` limitation after UAT showed that normal sparse
MCP field patches fail during Swift decoding before reaching OmniFocus.

## Performance Decision

The prior optimization program concluded that production query paths are at diminishing returns and that remaining tail latency is dominated by OmniFocus runtime pressure and documented collection access. Keep plugin URL dispatch as the only production architecture: it has the best combined latency/reliability evidence, while JXA dispatch adds another failure surface and duplicated query logic without a compensating production win. Do not change transport, add task caching, or introduce speculative JavaScript memoization before this release.

After the release, [#80](https://github.com/deverman/FocusRelayMCP/issues/80) will remove the supported JXA-dispatch runtime option and move pure JXA toward test/benchmark-only ownership. Until then, JXA remains an internal parity oracle rather than a user-facing recommendation.

One isolated candidate has current evidence:

- [#73](https://github.com/deverman/FocusRelayMCP/issues/73): clean successful IPC files immediately. After the live semantic gates, 40 completed calls left 40 request, 40 response, and 40 lock files while every new call rescanned all three directories. This is an experiment, not a release blocker. Keep it only if semantic gates pass and smoke plus 1-hour realistic validation show a defensible production-path win without new timeouts.

User-visible performance already available in the current release candidate should be emphasized and preserved:

- bulk mutations replace many bridge round trips with one homogeneous request;
- compact `returnFields` provide verified post-write data without a follow-up read;
- `list_tasks` without `includeTotalCount` uses early-stop paging;
- projects and tags use the existing actor cache for repeated MCP-session reads.

Existing feature issues remain:

- [#11](https://github.com/deverman/FocusRelayMCP/issues/11): OmniFocus deep links.
- [#18](https://github.com/deverman/FocusRelayMCP/issues/18): project planned-date reads and filters.
- [#22](https://github.com/deverman/FocusRelayMCP/issues/22): task added/modified timestamps and filters.
- [#10](https://github.com/deverman/FocusRelayMCP/issues/10): custom perspectives.
- [#16](https://github.com/deverman/FocusRelayMCP/issues/16): planned-date writes.
- [#75](https://github.com/deverman/FocusRelayMCP/issues/75): migrate deprecated MCP text response construction without changing wire behavior.

## Proposed Delivery Order

1. Re-run final combined tests, semantic gates, plugin/runtime checks, and release packaging.
2. Publish the release candidate for GitHub CI/review after approval.
3. Merge only after green CI and review, then tag `v0.10.0-beta` after explicit approval.
4. Update and verify the external Homebrew tap with the actual release-asset SHA256.
5. Implement post-beta task creation in #82, then project creation in #83.
6. Implement #11, then #22, then #18 as separate branches.
7. Add native task-status filters and general sorting as separate branches.
8. Run a documented feasibility phase before implementing #10 custom perspectives.
9. Re-scope #16 after verifying the current official planned-date setter contract.

## Validation Record

- 2026-07-13: `swift test` passed with 98 Swift Testing tests using `/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test`.
- 2026-07-13: Latest GitHub Actions CI run for `74190b5` was successful.
- 2026-07-13: Default tests did not enable `FOCUS_RELAY_LIVE_TESTS` or `FOCUS_RELAY_BRIDGE_TESTS`; live bridge behavior remains a separate validation step.
- 2026-07-13: `node --check Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js` and `git diff --check` passed.
- 2026-07-13: Current plugin installation, full OmniFocus restart, bridge health check, five mutation previews, and one verified write/restore cycle passed for issue #47.
- 2026-07-13: Live `list-tasks`, `task-counts`, and `project-counts` semantic gates all passed with bridge/JXA parity and list/count consistency.
- 2026-07-13: P1 mutation-truthfulness branch passed 104 Swift 6.3.3 tests, JavaScript syntax validation, plugin install/restart, bridge health, preview, verified write, and verified restore. Six failure-injection tests exercise the actual JavaScript executor through JavaScriptCore.
- 2026-07-13: Swift 6.3.3 toolchain branch was selected automatically through `.swift-version`; workflow YAML passed parsing and the 98-test suite passed.
- 2026-07-13: Release-packaging branch passed workflow YAML parsing, shell syntax, the 98-test suite, a Swift 6.3.3 release build, archive/checksum creation, archive-content inspection, packaged-binary help, and invalid-version rejection.
- 2026-07-13: The authoritative Homebrew tap checkout was confirmed at `/Users/deverman/Documents/code/homebrew-focus-relay`. Its formula passes Ruby syntax after local fixes for component order and an invalid escaped space; published-tap style/audit validation remains pending publication of those fixes.
- 2026-07-13: The tap's follow-up commit `c576a44` fixed a quoted-tilde caveat that would not expand in users' shells and updated the formula description for read/write behavior. `ruby -c`, `brew style`, and `git diff --check` pass; the published version and SHA256 remain intentionally unchanged.
- 2026-07-13: Version-reporting branch passed 100 Swift 6.3.3 tests. The local binary reports `0.0.0-dev`; a release build injected from `v0.10.0-beta` reported `0.10.0-beta`; malformed versions were rejected; workflow YAML, shell syntax, and diff checks passed.
- 2026-07-13: Project-count parity branch passed 104 Swift 6.3.3 tests, live per-project task-query consistency, live bridge/JXA count parity, and the `project-counts` semantic gate. Its 10-minute smoke completed 55/55 plugin and 55/55 JXA calls with zero errors, timeouts, or parity mismatches. RSS increased during sustained automation, which was carried forward into the completed post-integration realistic run below.
- 2026-07-13: Before the tool-surface follow-up, the combined `integration/v0.10.0-beta-rc` candidate passed 113 Swift 6.3.3 tests. A release-injected `0.10.0-beta` binary, matching plugin health version, numeric `0.10.0` OmniFocus manifest, archive contents, and SHA256 all validated; packaging correctly rejected a mismatched binary and malformed legacy version.
- 2026-07-13: The combined realistic suite ran for 1.5 hours with 750 measured calls, zero errors, zero timeouts, and all three fresh semantic gates passing. Project counts completed 256/256 calls with zero parity mismatches. Task listing completed 260/260 with zero mismatches. Task counts completed 234/234; its one paired mismatch coincided with the live inbox count changing between the plugin and JXA calls. OmniFocus RSS exceeded 1 GB under sustained alternating automation but reclaimed during the final phase, which ended 70 MB below its phase start.
- 2026-07-13: The public-tool-surface follow-up raised the combined suite to 114 tests. A direct MCP initialize and `tools/list` handshake returned exactly 14 product tools; bridge health and both inbox probes remained operational through the CLI.
- 2026-07-13: Shared task-filter schema and mutation-annotation fixes passed direct MCP `tools/list` inspection. The candidate publishes all 20 task-filter fields consistently and marks all seven write tools destructive, non-read-only, non-idempotent, and closed-world with explicit write/verification defaults.
- 2026-07-13: Task name/note search passed deterministic plugin and JXA tests, a positive live read, and both task semantic gates. The list gate explicitly returned zero for an impossible search and retained list/count parity.
- 2026-07-13: The benchmark-rotation regression fix raised the suite to 120 Swift 6.3.3 tests. Its corrected 10-minute list smoke covered all ten declared scenarios with 94 measured calls, zero errors/timeouts, zero parity mismatches, and zero timeout diagnostics.
- 2026-07-13: The 10-minute task-count search smoke covered all six scenarios with 98 measured calls, zero errors/timeouts, zero parity mismatches, and zero timeout diagnostics. Plugin p95 for the inbox scenario was 1.08 seconds versus 7.11 seconds for JXA.
- 2026-07-13: The post-search realistic validation ran sequential 30-minute list and count phases. All 544 measured calls succeeded with complete scenario coverage, zero errors/timeouts, zero parity mismatches, and zero timeout diagnostics. Plugin inbox list p50 was 0.99 seconds versus 6.52 seconds for JXA, while inbox-count p95 was 1.34 seconds versus 8.01 seconds. OmniFocus ended the count phase 447 MB below its start.
- 2026-07-14: Swiftly 1.1.3 installed and selected Swift 6.3.3 on a clean `macos-15` GitHub runner. Draft PR #84 passed build, all tests, release build, and artifact upload in 6m39s. The same candidate passed 122 Swift Testing tests and a production build locally with the Swiftly-managed toolchain.
- 2026-07-14: Effective-flag semantics passed 126 Swift 6.3.3 tests, deterministic plugin/JXA coverage, a live native ID-set comparison, and all three semantic gates. The new standard task-count gate independently compared documented OmniFocus `task.effectiveFlagged` results with bridge list/count results: all reported 46 available flagged actions and excluded the invisible flagged project root.
- 2026-07-14: The effective-flag 10-minute task-count and list smokes completed 208 measured calls with complete coverage and zero errors, timeouts, or mismatches. The required 1.5-hour realistic suite completed 864 measured calls across task counts, task lists, and project counts with zero errors, timeouts, or parity mismatches. Production plugin latency improved in every phase versus the prior candidate, although the correctness fix is not claimed as the cause because OmniFocus runtime state was not controlled.
