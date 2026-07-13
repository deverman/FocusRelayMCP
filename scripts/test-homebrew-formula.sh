#!/usr/bin/env bash

set -euo pipefail

TAP="deverman/focus-relay"
FORMULA="$TAP/focusrelay"
DEFAULT_TAP_REPO="/Users/deverman/Documents/code/homebrew-focus-relay"
TAP_REPO="${FOCUSRELAY_HOMEBREW_TAP_REPO:-$DEFAULT_TAP_REPO}"

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
ruby -c "$FORMULA_PATH"

echo "Checking the installed tap's audit and install resolution..."
brew tap "$TAP"
brew style "$FORMULA"
brew audit --strict "$FORMULA"
brew install --dry-run "$FORMULA"
brew info "$FORMULA"

echo "Authoritative formula validated: $FORMULA_PATH"
