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
PACKAGE_DIR="$OUTPUT_DIR/$PACKAGE_NAME"
ARCHIVE_NAME="$PACKAGE_NAME.tar.gz"
CHECKSUM_NAME="$PACKAGE_NAME.sha256"
ARCHIVE_PATH="$OUTPUT_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$OUTPUT_DIR/$CHECKSUM_NAME"

test -x "$BINARY_PATH"
test -f "$ROOT_DIR/Plugin/FocusRelayBridge.omnijs/manifest.json"
test -f "$ROOT_DIR/Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js"
test -f "$ROOT_DIR/README.md"

REPORTED_VERSION="$($BINARY_PATH --version)"
if [ "$REPORTED_VERSION" != "$VERSION" ]; then
  echo "Binary version mismatch: expected $VERSION, got $REPORTED_VERSION" >&2
  exit 1
fi

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

if [ -e "$PACKAGE_DIR" ] || [ -e "$ARCHIVE_PATH" ] || [ -e "$CHECKSUM_PATH" ]; then
  echo "Release output already exists for $PACKAGE_NAME in $OUTPUT_DIR" >&2
  exit 1
fi

mkdir -p "$PACKAGE_DIR"
cp "$BINARY_PATH" "$PACKAGE_DIR/"
cp -R "$ROOT_DIR/Plugin/FocusRelayBridge.omnijs" "$PACKAGE_DIR/"
cp "$ROOT_DIR/README.md" "$PACKAGE_DIR/"
tar -C "$OUTPUT_DIR" -czf "$ARCHIVE_PATH" "$PACKAGE_NAME"

SHA256="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$SHA256" "$ARCHIVE_NAME" > "$CHECKSUM_PATH"

printf 'version=%s\n' "$VERSION"
printf 'tag_name=v%s\n' "$VERSION"
printf 'archive_name=%s\n' "$ARCHIVE_NAME"
printf 'checksum_name=%s\n' "$CHECKSUM_NAME"
printf 'sha256=%s\n' "$SHA256"
