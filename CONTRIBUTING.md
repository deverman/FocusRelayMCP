# Contributing to FocusRelay

Thanks for helping make OmniFocus work better with AI assistants.

## Before You Start

- Check the [open issues](https://github.com/deverman/FocusRelayMCP/issues) for
  existing work and known constraints.
- Keep each pull request focused on one behavior or concern.
- Open an issue before a large interface or architecture change so the direction
  can be agreed before implementation.

## Local Setup

Requirements:

- macOS with OmniFocus 4 for live integration tests;
- Swift 6.3.3 selected through Swiftly and the checked-in `.swift-version`;
- the Swift Testing framework included with the Swift toolchain.

```bash
git clone https://github.com/deverman/FocusRelayMCP.git
cd FocusRelayMCP
swift build
swift test
```

Do not add `swift-testing` as a package dependency.

## Making Changes

- Add or update Swift tests when behavior changes.
- Use only documented Omni Automation APIs in production query paths.
- Follow `docs/omni-automation-contract.md` for query changes and
  `docs/omni-automation-write-contract.md` for write changes.
- Preserve compact field selection, truthful error reporting, and CLI/MCP
  behavior parity.
- Keep query optimization, transport, caching, approval UX, and benchmark
  tooling in separate branches.

If you change the OmniFocus plugin, install it with:

```bash
./scripts/install-plugin.sh
osascript -e 'tell application "OmniFocus" to quit'
sleep 2
open -a "OmniFocus"
```

OmniFocus caches plugin JavaScript, so a complete restart is required.

## Validation

Always run:

```bash
swift test
```

Query, transport, reliability, and release changes have additional semantic and
benchmark requirements in `AGENTS.md`. Include the commands you ran and their
results in the pull request.

## Pull Requests

- Explain the user-visible outcome first.
- Link the issue being addressed.
- Describe compatibility or migration effects.
- Include tests for new behavior and regressions.
- Avoid committing raw benchmark artifacts unless the evidence needs to remain
  in the repository.

Bug reports, tested use cases, documentation fixes, and focused pull requests
are all welcome.
