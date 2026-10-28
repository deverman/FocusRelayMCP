# Publishing FocusRelay to the MCP Registry

This document describes how to publish FocusRelay to the official MCP Registry at `registry.modelcontextprotocol.io`.

## Overview

FocusRelay is distributed as an MCPB (MCP Bundle) package via GitHub Releases. The MCP Registry hosts only metadata (in `server.json`), not the binary itself.

## Prerequisites

1. Install the `mcp-publisher` CLI tool:
   ```bash
   # macOS/Linux
   curl -L "https://github.com/modelcontextprotocol/registry/releases/latest/download/mcp-publisher_$(uname -s | tr '[:upper:]' '[:lower:]')_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" | tar xz mcp-publisher && sudo mv mcp-publisher /usr/local/bin/
   
   # Or via Homebrew
   brew install mcp-publisher
   ```

2. Verify installation:
   ```bash
   mcp-publisher --help
   ```

## Publishing Process

### Step 1: Create a GitHub Release

1. Push a version tag to trigger the release workflow:
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
   
   Or use the manual workflow dispatch in GitHub Actions.

2. The release workflow will automatically:
   - Build the binary
   - Package the tarball (for Homebrew)
   - **Package the MCPB bundle** (`.mcpb` file)
   - Upload both to the GitHub release with SHA256 checksums

### Step 2: Update server.json with the MCPB SHA256

After the release is created, download the `.mcpb.sha256` file or calculate it:

```bash
# Download the release asset
curl -LO https://github.com/deverman/FocusRelayMCP/releases/download/v1.0.0/focusrelay-1.0.0.mcpb.sha256

# Or calculate from the .mcpb file
curl -LO https://github.com/deverman/FocusRelayMCP/releases/download/v1.0.0/focusrelay-1.0.0.mcpb
openssl dgst -sha256 focusrelay-1.0.0.mcpb
```

Update the `server.json` file:
- Set `version` to match the release version (e.g., `1.0.0`)
- Set `packages[0].identifier` to the MCPB download URL
- Set `packages[0].fileSha256` to the actual SHA256 hash

Example:
```json
{
  "version": "1.0.0",
  "packages": [
    {
      "registryType": "mcpb",
      "identifier": "https://github.com/deverman/FocusRelayMCP/releases/download/v1.0.0/focusrelay-1.0.0.mcpb",
      "fileSha256": "abc123...",
      "transport": {
        "type": "stdio"
      }
    }
  ]
}
```

Commit and push the updated `server.json`:
```bash
git add server.json
git commit -m "Update server.json for v1.0.0 release"
git push origin main
```

### Step 3: Authenticate with the MCP Registry

Authenticate using GitHub-based authentication (required for `io.github.deverman/*` namespace):

```bash
mcp-publisher login github
```

This will open a browser for GitHub OAuth authentication.

### Step 4: Validate server.json

Before publishing, validate the `server.json`:

```bash
mcp-publisher validate
```

This checks:
- JSON schema compliance
- Version format
- Package URL accessibility
- Namespace format

### Step 5: Publish to the Registry

Publish the server metadata:

```bash
mcp-publisher publish
```

This will:
1. Validate `server.json` 
2. Verify namespace ownership (via your GitHub authentication)
3. Verify the package exists at the specified URL
4. Publish the metadata to the official registry

### Step 6: Verify Publication

Check that your server is published:

```bash
# Via the registry API
curl https://registry.modelcontextprotocol.io/api/v0/servers/io.github.deverman/focusrelay

# Or search for it
curl 'https://registry.modelcontextprotocol.io/api/v0/servers?q=focusrelay'
```

You can also view it at: `https://modelcontextprotocol.io/servers/io.github.deverman/focusrelay`

## Updating for New Releases

For each new release:

1. Create the GitHub release (Step 1)
2. Update `server.json` with the new version and SHA256 hash (Step 2)
3. Run `mcp-publisher publish` (skip authentication if still logged in)

## Troubleshooting

### "Package not found" error

The MCPB file must be publicly accessible at the URL in `identifier`. Verify:
```bash
curl -I https://github.com/deverman/FocusRelayMCP/releases/download/v1.0.0/focusrelay-1.0.0.mcpb
```

### "Namespace ownership verification failed"

Ensure you're authenticated with the GitHub account that owns the `deverman` username:
```bash
mcp-publisher logout
mcp-publisher login github
```

### "Invalid version format"

The `version` field must be a concrete version (e.g., `1.0.0` or `1.0.0-beta`), not a range.

## Files

- `server.json` - Registry metadata (checked into git)
- `mcpb-manifest.json` - MCPB bundle manifest template
- `scripts/package-mcpb.sh` - Script to create the MCPB bundle
- `.github/workflows/release.yml` - Automated release workflow

## References

- [MCP Registry Documentation](https://github.com/modelcontextprotocol/registry/tree/main/docs)
- [MCPB Specification](https://github.com/modelcontextprotocol/mcpb)
- [mcp-publisher CLI Reference](https://github.com/modelcontextprotocol/registry/blob/main/docs/reference/cli/commands.md)
