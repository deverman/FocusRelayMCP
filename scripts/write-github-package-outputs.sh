#!/usr/bin/env bash

set -euo pipefail

PACKAGE_OUTPUT_FILE="${1:-}"
GITHUB_OUTPUT_FILE="${2:-}"

if [ -z "$PACKAGE_OUTPUT_FILE" ] || [ -z "$GITHUB_OUTPUT_FILE" ]; then
  echo "Usage: $0 <package-output-file> <github-output-file>" >&2
  exit 1
fi

test -f "$PACKAGE_OUTPUT_FILE"

required_keys="version tag_name archive_name checksum_name sha256"
for key in $required_keys; do
  matches="$(awk -F= -v key="$key" '$1 == key { print }' "$PACKAGE_OUTPUT_FILE")"
  match_count="$(printf '%s\n' "$matches" | awk 'NF { count += 1 } END { print count + 0 }')"
  if [ "$match_count" -ne 1 ]; then
    echo "Expected exactly one package output for $key, found $match_count." >&2
    exit 1
  fi
done

version="$(awk -F= '$1 == "version" { sub(/^[^=]*=/, ""); print }' "$PACKAGE_OUTPUT_FILE")"
tag_name="$(awk -F= '$1 == "tag_name" { sub(/^[^=]*=/, ""); print }' "$PACKAGE_OUTPUT_FILE")"
archive_name="$(awk -F= '$1 == "archive_name" { sub(/^[^=]*=/, ""); print }' "$PACKAGE_OUTPUT_FILE")"
checksum_name="$(awk -F= '$1 == "checksum_name" { sub(/^[^=]*=/, ""); print }' "$PACKAGE_OUTPUT_FILE")"
sha256="$(awk -F= '$1 == "sha256" { sub(/^[^=]*=/, ""); print }' "$PACKAGE_OUTPUT_FILE")"

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?(\+[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$ ]]; then
  echo "Invalid package version output: $version" >&2
  exit 1
fi
if [ "$tag_name" != "v$version" ]; then
  echo "Package tag does not match version: $tag_name" >&2
  exit 1
fi
if [ "$archive_name" != "focusrelay-$version.tar.gz" ]; then
  echo "Package archive does not match version: $archive_name" >&2
  exit 1
fi
if [ "$checksum_name" != "focusrelay-$version.sha256" ]; then
  echo "Package checksum does not match version: $checksum_name" >&2
  exit 1
fi
if ! [[ "$sha256" =~ ^[0-9a-f]{64}$ ]]; then
  echo "Invalid package SHA-256 output." >&2
  exit 1
fi

for key in $required_keys; do
  awk -F= -v key="$key" '$1 == key { print }' "$PACKAGE_OUTPUT_FILE" >> "$GITHUB_OUTPUT_FILE"
done
