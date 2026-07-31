#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

VALID_INPUT="$TEMP_DIR/valid.txt"
VALID_OUTPUT="$TEMP_DIR/github-output.txt"
cat > "$VALID_INPUT" <<'EOF'
Minimum macOS: 26.0
version=0.12.0-beta
tag_name=v0.12.0-beta
archive_name=focusrelay-0.12.0-beta.tar.gz
checksum_name=focusrelay-0.12.0-beta.sha256
sha256=48eba81d7aa1c5a1688915f60bc27bfcfb3ee57ec3bdf786870edb8e9ff625c5
EOF

"$ROOT_DIR/scripts/write-github-package-outputs.sh" "$VALID_INPUT" "$VALID_OUTPUT"
if grep -Fq "Minimum macOS" "$VALID_OUTPUT"; then
  echo "Human-readable diagnostics leaked into GitHub outputs." >&2
  exit 1
fi
if [ "$(wc -l < "$VALID_OUTPUT" | tr -d ' ')" -ne 5 ]; then
  echo "Expected exactly five GitHub outputs." >&2
  exit 1
fi

DUPLICATE_INPUT="$TEMP_DIR/duplicate.txt"
cp "$VALID_INPUT" "$DUPLICATE_INPUT"
printf 'sha256=%s\n' "48eba81d7aa1c5a1688915f60bc27bfcfb3ee57ec3bdf786870edb8e9ff625c5" >> "$DUPLICATE_INPUT"
if "$ROOT_DIR/scripts/write-github-package-outputs.sh" "$DUPLICATE_INPUT" "$TEMP_DIR/duplicate-output.txt"; then
  echo "Duplicate package output unexpectedly passed." >&2
  exit 1
fi

MISSING_INPUT="$TEMP_DIR/missing.txt"
grep -v '^tag_name=' "$VALID_INPUT" > "$MISSING_INPUT"
if "$ROOT_DIR/scripts/write-github-package-outputs.sh" "$MISSING_INPUT" "$TEMP_DIR/missing-output.txt"; then
  echo "Missing package output unexpectedly passed." >&2
  exit 1
fi

echo "Release package output tests passed."
