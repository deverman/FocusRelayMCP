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

1. Install the bundled plugin with `./scripts/install-plugin.sh` when validating from this repository, or copy the plugin installed by Homebrew.
2. Quit and fully restart OmniFocus.
3. Run a real read query.
4. Run a safe mutation preview.
5. Run a reversible verified mutation and restore the original state.

The release is not complete until the fresh Homebrew installation passes these checks.
