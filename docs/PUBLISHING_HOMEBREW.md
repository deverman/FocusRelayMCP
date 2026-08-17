# Publishing FocusRelay Through Homebrew

The authoritative formula lives in the external tap:

- Repository: `deverman/homebrew-focus-relay`
- Formula: `focusrelay.rb`
- Install name: `focusrelay`

FocusRelayMCP intentionally does not keep a second formula in this repository. Two formula copies drifted in the past and made it unclear which URL, version, and SHA256 users should trust.

## Prerequisites

Before updating the tap:

- the GitHub release exists;
- `focusrelay-VERSION.tar.gz` is uploaded;
- `focusrelay-VERSION.sha256` is uploaded;
- the release workflow completed successfully;
- the release asset contains `focusrelay`, `FocusRelayBridge.omnijs`, and `README.md`.

Always take the SHA256 from the actual release asset. Recreating a release or tag can change the archive and therefore the checksum even when the version string is unchanged.

## Update The Tap

```bash
git clone https://github.com/deverman/homebrew-focus-relay.git
cd homebrew-focus-relay
```

Update `focusrelay.rb`:

```ruby
version "VERSION"
url "https://github.com/deverman/FocusRelayMCP/releases/download/vVERSION/focusrelay-VERSION.tar.gz"
sha256 "SHA256_FROM_RELEASE_ASSET"
```

Then validate and publish the tap change:

```bash
brew audit --strict ./focusrelay.rb
brew style ./focusrelay.rb
git add focusrelay.rb
git commit -m "Update focusrelay to VERSION"
git push origin main
```

## Validate A Fresh Installation

Refresh the tap before trusting the result:

```bash
brew untap deverman/focus-relay
brew tap deverman/focus-relay
brew reinstall focusrelay
focusrelay --help
focusrelay --version
```

Run the repository validation helper to check the published formula:

```bash
./scripts/test-homebrew-formula.sh
```

After installation:

1. Preview the packaged paths with `focusrelay setup --dry-run`.
2. Install the bundled plug-in with `focusrelay setup --non-interactive`.
   When validating from this repository, `./scripts/install-plugin.sh` calls
   that same Swift implementation with the development plug-in source.
3. Quit and fully restart OmniFocus.
4. Run `focusrelay setup --non-interactive --check-readiness`.
5. Run a real read query.
6. Run a safe mutation preview.
7. Run a reversible verified mutation and restore the original state.

The tap caveats should name `focusrelay setup` as the only plug-in installation
step. Do not duplicate copy commands or plug-in path logic in the formula.

The release is not complete until the fresh Homebrew installation passes these checks.
