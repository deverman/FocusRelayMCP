# Session Notes (FocusRelayMCP)

Last updated: 2026-07-14

## Current Release Candidate

- Local integration branch: `integration/v0.10.0-beta-rc`.
- Base: `master` / `origin/master` at `74190b5`.
- Swift toolchain: Swiftly-managed Swift 6.3.3, selected by `.swift-version`.
- Combined validation: 126 Swift Testing tests pass, including live OmniFocus
  integration tests available in the current environment.
- Release packaging: a local `0.10.0-beta` release build, archive, checksum,
  packaged binary, plugin manifest, and plugin health version were verified.
- Remote state: draft PR #84 is pushed, mergeable, and green in GitHub CI. No
  tag or release has been created.
- Realistic validation: 750 measured calls over 1.5 hours completed with zero
  errors/timeouts. All three semantic gates passed; project-count parity had no
  mismatch. OmniFocus RSS showed runtime-pressure fluctuations but reclaimed
  during the final phase rather than increasing monotonically.
- Post-search validation: corrected 10-minute list/count smokes completed 192
  measured calls, followed by sequential 30-minute list/count phases with 544
  measured calls. Every call succeeded with complete scenario coverage and no
  parity mismatch; OmniFocus ended the final phase 447 MB below its start.
- Effective-flag validation: two corrected 10-minute smokes completed 208 calls,
  followed by a 1.5-hour suite with 864 measured calls. Every call succeeded
  without a timeout or mismatch, and the native OmniFocus gate, task list, and
  task count all agreed on the visible Flagged action set.
- MCP surface: 14 product tools are advertised. Bridge health and inbox probes
  remain CLI-only diagnostics.
- Public contract follow-ups: list/count now share all 20 task-filter schema
  fields; all seven mutations advertise truthful destructive/write defaults;
  task search filters names and notes in plugin and JXA list/count paths.
- Transport decision: plugin URL remains the only recommended production path.
  JXA is retained temporarily as an internal parity/benchmark oracle; #80
  tracks removing JXA dispatch after this release.

## Remaining Release Work

1. Complete user acceptance testing of the installed `0.10.0-beta` candidate.
2. Merge approved draft PR #84.
3. Tag only after the release tracker is green and explicit approval is given.
4. After the GitHub release asset exists, update the authoritative tap at
   `/Users/deverman/Documents/code/homebrew-focus-relay` with its actual SHA256
   and verify a clean Homebrew reinstall.

## Important Local State

- The authoritative Homebrew tap checkout is
  `/Users/deverman/Documents/code/homebrew-focus-relay`.
- Its `fix/formula-style` branch is pushed at `18894b6` in draft PR #1 and
  passes real tap-context style, strict audit, and install resolution. Do not
  replace the published version or SHA256 until the real release asset exists.
- Install plugin updates only with `./scripts/install-plugin.sh`, then quit and
  reopen OmniFocus so its cached JavaScript is replaced.

See [`docs/roadmap-execution-plan.md`](docs/roadmap-execution-plan.md) for the
full issue map, dependency decisions, validation evidence, and delivery order.
