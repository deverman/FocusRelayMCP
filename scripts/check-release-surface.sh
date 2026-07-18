#!/usr/bin/env bash

set -euo pipefail

binary="${1:-.build/release/focusrelay}"

if [[ ! -x "$binary" ]]; then
  echo "Release binary is missing or not executable: $binary" >&2
  exit 1
fi

help_output="$($binary --help)"
retired_commands='benchmark-(task-counts|list-tasks|project-counts|gate-check)|debug-inbox-probe'
retired_symbols='OmniAutomationService|OSAKit|Application\("OmniFocus"\)'

if grep -Eq "$retired_commands" <<<"$help_output"; then
  echo "Release help exposes developer-only JXA commands." >&2
  exit 1
fi

if otool -L "$binary" | grep -Fq '/OSAKit.framework/'; then
  echo "Release binary links OSAKit." >&2
  exit 1
fi

if strings "$binary" | grep -Eq "$retired_commands|$retired_symbols"; then
  echo "Release binary contains developer-only JXA code or command names." >&2
  exit 1
fi

echo "Release surface is JXA-free: $binary"
