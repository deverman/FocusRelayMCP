#!/usr/bin/env bash

set -euo pipefail

forbidden_tokens=(
  "OSA""Kit"
  "OmniAutomation""Service"
  "Script""Runner"
  "FOCUS_RELAY_PARITY_""TESTS"
  "FOCUS_RELAY_LIVE_""TESTS"
  "include-""jxa-parity"
  "debug-inbox-""probe"
)

source_roots=(Sources Tests scripts Package.swift)
for token in "${forbidden_tokens[@]}"; do
  if grep -REn --exclude='check-bridge-only-architecture.sh' "$token" "${source_roots[@]}"; then
    echo "Bridge-only architecture violation: found $token" >&2
    exit 1
  fi
done

for binary in "$@"; do
  if [[ ! -x "$binary" ]]; then
    echo "Binary is missing or not executable: $binary" >&2
    exit 1
  fi

  framework_name="${forbidden_tokens[0]}"
  if otool -L "$binary" | grep -Fq "/${framework_name}.framework/"; then
    echo "Binary links the retired direct-automation framework: $binary" >&2
    exit 1
  fi

  for token in "${forbidden_tokens[@]}"; do
    if strings "$binary" | grep -Fq "$token"; then
      echo "Binary contains retired direct-automation code: $binary ($token)" >&2
      exit 1
    fi
  done
done

echo "Bridge-only architecture check passed."
