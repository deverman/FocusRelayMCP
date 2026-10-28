# MCP Registry Setup - Next Steps

This PR prepares FocusRelay for publication to the official MCP Registry. The changes include:

## What's Changed

1. **Added MCPB bundle support** (`mcpb-manifest.json`)
   - Created a manifest template for the MCP Bundle format
   - FocusRelay will be distributed as a `.mcpb` file (ZIP archive containing the binary and plugin)

2. **Created packaging script** (`scripts/package-mcpb.sh`)
   - Packages FocusRelay as an MCPB bundle with manifest.json
   - Calculates SHA256 hash for integrity verification
   - Executed automatically during releases

3. **Updated release workflow** (`.github/workflows/release.yml`)
   - Now creates and uploads `.mcpb` files alongside tarballs
   - Uploads SHA256 checksums for both formats

4. **Added registry metadata** (`server.json`)
   - Ready for publication to `registry.modelcontextprotocol.io`
   - Uses GitHub releases as the distribution mechanism
   - **Note: The `fileSha256` is currently a placeholder** (all zeros)

5. **Added documentation** (`docs/PUBLISHING_MCP_REGISTRY.md`)
   - Complete publishing guide with step-by-step instructions

## What You Need to Do

### Before Publishing to the Registry

1. **Create a new release** (or wait for the next scheduled release):
   ```bash
   # This will trigger the workflow and create the .mcpb file
   git tag v0.13.0-beta
   git push origin v0.13.0-beta
   ```

2. **Update `server.json` with the actual SHA256 hash**:
   - After the release completes, download the `.mcpb.sha256` file:
     ```bash
     curl -LO https://github.com/deverman/FocusRelayMCP/releases/download/v0.13.0-beta/focusrelay-0.13.0-beta.mcpb.sha256
     cat focusrelay-0.13.0-beta.mcpb.sha256
     ```
   - Update `server.json`:
     - Change `version` to match the release version (e.g., `"0.13.0-beta"`)
     - Change `packages[0].identifier` URL to match the release version
     - Replace the `fileSha256` with the actual hash from the `.sha256` file
   - Commit and push the updated `server.json`

3. **Install `mcp-publisher` CLI**:
   ```bash
   # macOS/Linux
   curl -L "https://github.com/modelcontextprotocol/registry/releases/latest/download/mcp-publisher_$(uname -s | tr '[:upper:]' '[:lower:]')_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" | tar xz mcp-publisher && sudo mv mcp-publisher /usr/local/bin/

   # Or via Homebrew
   brew install mcp-publisher
   ```

4. **Authenticate with GitHub**:
   ```bash
   mcp-publisher login github
   ```
   This will open a browser for OAuth authentication with your GitHub account (`deverman`).

5. **Validate the server.json**:
   ```bash
   mcp-publisher validate
   ```

6. **Publish to the registry**:
   ```bash
   mcp-publisher publish
   ```

### For Future Releases

After each new release:
1. Wait for the GitHub release to complete (`.mcpb` file uploaded)
2. Update `server.json` with the new version and SHA256 hash
3. Run `mcp-publisher publish` (no need to re-authenticate unless logged out)

## Important Notes

- **DO NOT** run `mcp-publisher publish` until you've updated the `fileSha256` with the actual hash from a real release
- The placeholder hash (all zeros) will fail validation if you try to publish it
- The namespace `io.github.deverman/focusrelay` requires GitHub authentication as `deverman`
- MCPB files must be publicly accessible on GitHub Releases
- Users will be able to install FocusRelay directly from the MCP Registry after publication

## Testing the MCPB Package

After merging this PR, you can test the MCPB packaging on the next release:

1. Create a release (manually or via tag push)
2. Download the `.mcpb` file from the release
3. Extract and inspect it:
   ```bash
   unzip -l focusrelay-X.Y.Z.mcpb
   ```
4. Verify it contains:
   - `manifest.json` (with correct version)
   - `focusrelay` (binary)
   - `FocusRelayBridge.omnijs/` (plugin)
   - `README.md`

## References

- Full documentation: `docs/PUBLISHING_MCP_REGISTRY.md`
- MCP Registry: https://github.com/modelcontextprotocol/registry
- MCPB Spec: https://github.com/modelcontextprotocol/mcpb
