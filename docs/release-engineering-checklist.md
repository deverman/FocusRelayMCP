# Release Engineering Checklist

Use this checklist for future FocusRelayMCP beta/stable releases.

## 1. Classify The Release

- `Docs / packaging only`
- `Production query / transport / reliability change`

Rule:
- If the release changes production query behavior, transport behavior, or timeout/reliability handling, use the **full validation path** below.
- If the release changes only docs, packaging, or metadata, use the **light validation path**.

## 2. Validate The Working Tree

- Ensure you are on the intended release branch
- Ensure benchmark artifacts are not accidentally staged
- Confirm plugin changes and binary changes are in sync

Commands:
```bash
git status --short
swift test
```

## 3. Run Semantic Gates

Run the gate for each affected tool:

```bash
swift run focusrelay benchmark-gate-check --tool task-counts
swift run focusrelay benchmark-gate-check --tool list-tasks
swift run focusrelay benchmark-gate-check --tool project-counts
```

Rule:
- If a gate fails, do not benchmark, tag, or release.

## 4. Benchmark Before Release

### Light Validation Path

Use for docs/packaging-only releases:

```bash
swift test
```

If you want a quick runtime check, run a smoke benchmark on the affected tool only.

### Full Validation Path

Use for production query/transport/reliability releases:

1. Smoke benchmark on the affected tool(s)
2. Realistic single-user suite before tagging

Recommended realistic suite:
```bash
caffeinate -dimsu ./scripts/benchmark-suite.sh \
  --total-hours 1.5 \
  --warmup-calls 10 \
  --interval-ms 5000 \
  --cooldown-ms 5000 \
  --memory-interval-seconds 60 \
  --suite-dir docs/benchmarks/release-$(date +%Y%m%d-%H%M%S)
```

Rule:
- Use the 3-hour stress profile only for diagnostics or when transport/reliability work changed.

## 5. Merge First

- Merge the release PR into `master`
- Update local `master`

Commands:
```bash
git switch master
git pull --ff-only origin master
```

## 6. Create The Tag

Commands:
```bash
git tag -a vX.Y.Z -m "Release vX.Y.Z: short description"
git push origin vX.Y.Z
```

Notes:
- For beta releases, use the intended beta tag consistently
- Verify the release workflow starts on GitHub

## 7. Verify GitHub Release

Check:
- release exists
- tarball asset exists
- `.sha256` asset exists
- release notes are correct
- prerelease flag is correct for beta tags

Commands:
```bash
gh release view vX.Y.Z --repo deverman/FocusRelayMCP
gh run list --repo deverman/FocusRelayMCP --workflow release.yml --limit 5
```

## 8. Update The Homebrew Tap

Repository:
- `/Users/deverman/Documents/Code/swift/homebrew-focus-relay`

Steps:
1. update the formula URL
2. update the formula SHA256 from the actual release asset
3. add/update explicit `version` if needed
4. commit and push the tap

## 9. Test Homebrew Installation

Recommended validation:
```bash
brew update
brew untap deverman/focus-relay || true
brew tap deverman/focus-relay
brew reinstall focusrelay
focusrelay --help
```

Rule:
- Do not consider the release done until the Homebrew install path is validated.

Install-flow validation:
1. Verify the README order still matches the real path: install binary -> install plugin -> configure MCP -> restart OmniFocus -> approve first query.
2. If the plugin changed, reinstall it before validating.
3. Trigger a real query after restart so the OmniFocus approval prompt can appear:

```bash
focusrelay bridge-health-check
focusrelay list-tasks --fields id,name --limit 1
```

4. If the approval prompt does not appear when expected, treat the release as not validated.
5. After approval, confirm the first query returns real task data rather than a timeout or empty transport failure.

## 10. Post-Release Sanity Check

- confirm the installed formula version matches the release
- confirm the plugin bundle exists in the Homebrew package share path
- if plugin JS changed, reinstall the plugin locally and restart OmniFocus before local validation
- confirm the first-query approval path and README setup steps still match the actual product behavior

## 11. Communication Checklist

- GitHub release notes updated from generic workflow text if needed
- release summary uses plain language, not only benchmark jargon
- if citing benchmark improvements, state what they mean in user terms:
  - “slower normal requests got faster”
  - “timeouts dropped to zero”

## 12. Do Not Repeat These Mistakes

- Do not mix transport experiments and query changes in one release benchmark
- Do not ship speculative optimizations that regressed the 1-hour validation
- Do not trust stale local Homebrew tap state; refresh it if results look wrong
- Do not tag before semantic gates and release validation are complete
