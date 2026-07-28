#!/usr/bin/env bash

set -euo pipefail

BINARY_PATH="${1:-}"
EXPECTED_MINIMUM="${2:-26.0}"

if [ -z "$BINARY_PATH" ] || [ ! -f "$BINARY_PATH" ]; then
  echo "Usage: $0 <mach-o-binary> [expected-minimum]" >&2
  exit 2
fi

ACTUAL_MINIMUM="$(
  xcrun vtool -show-build "$BINARY_PATH" |
    awk '$1 == "minos" { print $2; exit }'
)"

if [ -z "$ACTUAL_MINIMUM" ]; then
  echo "Could not read a macOS minimum version from $BINARY_PATH" >&2
  exit 1
fi

if [ "$ACTUAL_MINIMUM" != "$EXPECTED_MINIMUM" ]; then
  echo "Minimum macOS mismatch: expected $EXPECTED_MINIMUM, got $ACTUAL_MINIMUM" >&2
  exit 1
fi

printf 'Minimum macOS: %s\n' "$ACTUAL_MINIMUM"
