#!/usr/bin/env bash

set -euo pipefail

export HOMEBREW_NO_AUTO_UPDATE=1

UPDATE_FIRST=false
if [[ "${1:-}" == "--update" ]]; then
    UPDATE_FIRST=true
    shift
fi
if [[ $# -gt 0 ]]; then
    echo "Usage: $0 [--update]" >&2
    exit 1
fi

TAP="deverman/focus-relay"
FORMULA="$TAP/focusrelay"
DEFAULT_TAP_REPO="/Users/deverman/Documents/code/homebrew-focus-relay"
TAP_REPO="${FOCUSRELAY_HOMEBREW_TAP_REPO:-$DEFAULT_TAP_REPO}"

timed() {
    local label="$1"
    shift
    local started=$SECONDS
    echo "[start] $label"
    "$@"
    echo "[end] $label elapsed=$((SECONDS - started))s"
}

if [[ "$UPDATE_FIRST" == true ]]; then
    unset HOMEBREW_NO_AUTO_UPDATE
    timed "brew update" brew update
    export HOMEBREW_NO_AUTO_UPDATE=1
fi

if [[ -f "$TAP_REPO/focusrelay.rb" ]]; then
    FORMULA_PATH="$TAP_REPO/focusrelay.rb"
    echo "Validating the authoritative local tap checkout: $TAP_REPO"
else
    echo "Local tap checkout not found; using the installed Homebrew tap..."
    brew tap "$TAP"

    TAP_DIR="$(brew --repository "$TAP")"
    FORMULA_PATH="$TAP_DIR/focusrelay.rb"
    test -f "$FORMULA_PATH"
fi

echo "Checking formula syntax and style..."
timed "formula syntax" ruby -c "$FORMULA_PATH"

echo "Checking the installed tap's audit and install resolution..."
timed "tap resolution" brew tap "$TAP"
timed "formula style" brew style "$FORMULA"
timed "strict audit" brew audit --strict "$FORMULA"
timed "install dry run" brew install --dry-run "$FORMULA"
timed "formula info" brew info "$FORMULA"

echo "Authoritative formula validated: $FORMULA_PATH"
