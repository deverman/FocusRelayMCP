# Release Engineering Checklist

Use this with [`development-workflow.md`](development-workflow.md). The release
proof applies to one frozen production fingerprint, not to a moving branch.

## 1. Plan And Freeze

- Confirm the issue/PR names the validation impact and user acceptance journey.
- Merge independently validated vertical changes before freezing the candidate.
- Run release-claim UAT through a real MCP client before the long suite.
- Keep `Sources/FocusRelayVersion/FocusRelayBuildVersion.swift` at `0.0.0-dev`;
  the release workflow embeds the tag version.

```bash
swift run focusrelay-dev release-plan --version X.Y.Z
git status --short
```

Any later production-code or plugin change invalidates the fingerprint. A
documentation-only correction does not.

## 2. Validate Once At The Required Depth

Docs or metadata only:

```bash
swift run focusrelay-dev validate --impact docs
```

Production query, performance, transport, or reliability changes:

```bash
swift run focusrelay-dev validate --impact transport-reliability
swift run focusrelay-dev benchmark --profile release
```

The release profile is the realistic 1.5-hour suite. Use `smoke` during targeted
performance work and `stress` only to answer a named diagnostic question.
Every benchmark profile fails closed when a required measured scenario reports
an error or timeout, has incomplete coverage, or produces malformed/missing
artifacts. An environment-interrupted run is failed evidence even when the
interruption is external. Diagnose it first, then permit at most one bounded
retry with the cause removed; for sleep interruption, run the retry under
`caffeinate`.

## 3. Tag The Certified Commit

```bash
git switch master
git pull --ff-only origin master
git tag -a vX.Y.Z -m "Release vX.Y.Z: short description"
git push origin vX.Y.Z
```

Verify the GitHub release, tarball, `.sha256`, prerelease flag, release notes,
and embedded version. Credit contributors by GitHub handle.

```bash
gh release view vX.Y.Z --repo deverman/FocusRelayMCP
gh run list --repo deverman/FocusRelayMCP --workflow release.yml --limit 5
swift run focusrelay-dev release-verify --version X.Y.Z
```

## 4. Update And Verify Homebrew

Update the URL and checksum in the authoritative
`deverman/homebrew-focus-relay` checkout. A rebuilt asset always needs its new
checksum, even when reusing a version.

Run one explicit update, then suppress hidden repeats:

```bash
./scripts/test-homebrew-formula.sh --update
HOMEBREW_NO_AUTO_UPDATE=1 brew reinstall focusrelay
focusrelay --version
focusrelay --help
```

If the tap appears stale, untap and retap it before trusting the result.

## 5. Verify The Installed Journey

If plugin JavaScript changed:

```bash
FOCUSRELAY_PLUGIN_SRC=/opt/homebrew/opt/focusrelay/share/focusrelay/Plugin/FocusRelayBridge.omnijs \
  ./scripts/install-plugin.sh
osascript -e 'tell application "OmniFocus" to quit'
sleep 2
open -a "OmniFocus"
```

Omit `FOCUSRELAY_PLUGIN_SRC` only for development validation that intentionally
installs the source-tree `0.0.0-dev` plugin. Release verification must install
the version-embedded plugin from the package being tested.

Then verify the README flow: install binary, install plugin, configure MCP,
restart OmniFocus, approve the first query, and receive real data.

```bash
focusrelay bridge-health-check
focusrelay list-tasks --fields id,name --limit 1
```

The release is complete only when the GitHub asset, Homebrew formula, installed
binary version, plugin, and first-query path all agree.
