#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_SRC="${FOCUSRELAY_PLUGIN_SRC:-$ROOT_DIR/Plugin/FocusRelayBridge.omnijs}"

cd "$ROOT_DIR"
exec swift run focusrelay setup --plugin-source "$PLUGIN_SRC" --non-interactive
