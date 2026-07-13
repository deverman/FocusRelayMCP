# Session Notes (FocusRelayMCP)

Last updated: 2026-07-13

## Current Release Candidate

- Local integration branch: `integration/v0.10.0-beta-rc`.
- Base: `master` / `origin/master` at `74190b5`.
- Swift toolchain: Swiftly-managed Swift 6.3.3, selected by `.swift-version`.
- Combined validation: 113 Swift Testing tests pass, including live OmniFocus
  integration tests available in the current environment.
- Release packaging: a local `0.10.0-beta` release build, archive, checksum,
  packaged binary, plugin manifest, and plugin health version were verified.
- Remote state: the release-candidate branches and commits have not been pushed,
  and no tag or release has been created.

## Remaining Release Work

1. Install the plugin from the combined candidate and fully restart OmniFocus.
2. Repeat bridge health, safe mutation preview, verified write/restore, and
   bridge/JXA query-parity checks on the combined code.
3. Run the `list-tasks`, `task-counts`, and `project-counts` semantic gates.
4. Run the required realistic single-user benchmark because the candidate
   changes production query/plugin paths.
5. Publish for CI/review only after explicit approval.
6. After the GitHub release asset exists, update the authoritative tap at
   `/Users/deverman/Documents/code/homebrew-focus-relay` with its actual SHA256
   and verify a clean Homebrew reinstall.

## Important Local State

- The authoritative Homebrew tap checkout is
  `/Users/deverman/Documents/code/homebrew-focus-relay`.
- Its formula has uncommitted local syntax/style corrections; do not replace the
  published version or SHA256 until the real release asset exists.
- Install plugin updates only with `./scripts/install-plugin.sh`, then quit and
  reopen OmniFocus so its cached JavaScript is replaced.

See [`docs/roadmap-execution-plan.md`](docs/roadmap-execution-plan.md) for the
full issue map, dependency decisions, validation evidence, and delivery order.
