#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 VERSION" >&2
    exit 64
fi

VERSION="${1#v}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?(\+[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
    echo "Invalid release version: $1" >&2
    exit 64
fi

VERSION_FILE="Sources/FocusRelayVersion/FocusRelayBuildVersion.swift"
PLUGIN_MANIFEST="Plugin/FocusRelayBridge.omnijs/manifest.json"
PLUGIN_LIBRARY="Plugin/FocusRelayBridge.omnijs/Resources/BridgeLibrary.js"
if [[ ! -f "$VERSION_FILE" ]]; then
    echo "Version source not found: $VERSION_FILE" >&2
    exit 66
fi
if [[ ! -f "$PLUGIN_MANIFEST" || ! -f "$PLUGIN_LIBRARY" ]]; then
    echo "FocusRelay plugin sources were not found" >&2
    exit 66
fi

PLUGIN_VERSION="${VERSION%%[-+]*}"

printf '%s\n' \
    'public enum FocusRelayBuildVersion {' \
    '    /// Embedded at build time. Tagged releases set this value with `scripts/set-version.sh`.' \
    "    public static let current = \"$VERSION\"" \
    '}' > "$VERSION_FILE"

FOCUSRELAY_PLUGIN_VERSION="$PLUGIN_VERSION" perl -0pi -e \
    's/"version": "[^"]+"/"version": "$ENV{FOCUSRELAY_PLUGIN_VERSION}"/' \
    "$PLUGIN_MANIFEST"
FOCUSRELAY_VERSION="$VERSION" perl -0pi -e \
    's/const FOCUSRELAY_VERSION = "[^"]+";/const FOCUSRELAY_VERSION = "$ENV{FOCUSRELAY_VERSION}";/' \
    "$PLUGIN_LIBRARY"

grep -Fq "const FOCUSRELAY_VERSION = \"$VERSION\";" "$PLUGIN_LIBRARY"
grep -Fq "\"version\": \"$PLUGIN_VERSION\"" "$PLUGIN_MANIFEST"

echo "Embedded FocusRelay version: $VERSION (OmniFocus manifest: $PLUGIN_VERSION)"
