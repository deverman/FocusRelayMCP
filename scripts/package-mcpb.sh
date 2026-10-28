#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:-}"
OUTPUT_DIR="${2:-$PWD}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY_PATH="${FOCUSRELAY_BINARY_PATH:-$ROOT_DIR/.build/release/focusrelay}"

VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?(\+[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  echo "Invalid release version: $VERSION" >&2
  exit 1
fi

PACKAGE_NAME="focusrelay-${VERSION}"
MCPB_NAME="${PACKAGE_NAME}.mcpb"
MCPB_PATH="$OUTPUT_DIR/$MCPB_NAME"
MCPB_CHECKSUM_NAME="${PACKAGE_NAME}.mcpb.sha256"
MCPB_CHECKSUM_PATH="$OUTPUT_DIR/$MCPB_CHECKSUM_NAME"
TEMP_DIR="$(mktemp -d)"

# Verify required files exist
test -x "$BINARY_PATH"
test -f "$ROOT_DIR/Plugin/FocusRelayBridge.omnijs/manifest.json"
test -f "$ROOT_DIR/Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js"
test -f "$ROOT_DIR/README.md"
test -f "$ROOT_DIR/mcpb-manifest.json"
"$ROOT_DIR/scripts/check-minimum-macos.sh" "$BINARY_PATH"

# Verify binary version matches
REPORTED_VERSION="$($BINARY_PATH --version)"
if [ "$REPORTED_VERSION" != "$VERSION" ]; then
  echo "Binary version mismatch: expected $VERSION, got $REPORTED_VERSION" >&2
  exit 1
fi

# Verify plugin version matches
PLUGIN_VERSION="${VERSION%%[-+]*}"
MANIFEST_VERSION="$(awk -F'"' '/"version"/ { print $4; exit }' "$ROOT_DIR/Plugin/FocusRelayBridge.omnijs/manifest.json")"
if [ "$MANIFEST_VERSION" != "$PLUGIN_VERSION" ]; then
  echo "Plugin manifest version mismatch: expected $PLUGIN_VERSION, got $MANIFEST_VERSION" >&2
  exit 1
fi
if ! grep -Fq "const FOCUSRELAY_VERSION = \"$VERSION\";" "$ROOT_DIR/Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js"; then
  echo "Plugin health version does not match release version $VERSION" >&2
  exit 1
fi

# Check that output doesn't already exist
if [ -e "$MCPB_PATH" ] || [ -e "$MCPB_CHECKSUM_PATH" ]; then
  echo "MCPB output already exists for $PACKAGE_NAME in $OUTPUT_DIR" >&2
  exit 1
fi

# Create MCPB bundle structure in temp directory
mkdir -p "$TEMP_DIR"
cp "$BINARY_PATH" "$TEMP_DIR/"
cp -R "$ROOT_DIR/Plugin/FocusRelayBridge.omnijs" "$TEMP_DIR/"
cp "$ROOT_DIR/README.md" "$TEMP_DIR/"

# Create manifest.json with the correct version
sed "s/\"version\": \".*\"/\"version\": \"$VERSION\"/" "$ROOT_DIR/mcpb-manifest.json" > "$TEMP_DIR/manifest.json"

# Create the MCPB file (ZIP archive)
cd "$TEMP_DIR"
zip -r -q "$MCPB_PATH" .

# Calculate SHA256 hash
SHA256="$(shasum -a 256 "$MCPB_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$MCPB_NAME" > "$MCPB_CHECKSUM_PATH"

# Clean up temp directory
rm -rf "$TEMP_DIR"

# Output information for GitHub Actions
printf 'mcpb_name=%s\n' "$MCPB_NAME"
printf 'mcpb_checksum_name=%s\n' "$MCPB_CHECKSUM_NAME"
printf 'mcpb_sha256=%s\n' "$SHA256"
