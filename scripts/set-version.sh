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
if [[ ! -f "$VERSION_FILE" ]]; then
    echo "Version source not found: $VERSION_FILE" >&2
    exit 66
fi

printf '%s\n' \
    'public enum FocusRelayBuildVersion {' \
    '    /// Embedded at build time. Tagged releases set this value with `scripts/set-version.sh`.' \
    "    public static let current = \"$VERSION\"" \
    '}' > "$VERSION_FILE"

echo "Embedded FocusRelay version: $VERSION"
