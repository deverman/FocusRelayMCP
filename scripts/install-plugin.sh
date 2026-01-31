#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_SRC="$ROOT_DIR/Plugin/FocusRelayBridge.omnijs"

# Detect OmniFocus plugin directories in priority order
# Priority: User's custom linked folders > iCloud > Sandbox > Legacy

echo "🔍 Detecting OmniFocus plugin directory..."

# Priority 1: Check if user has configured custom plugin folders via defaults
CUSTOM_PLUGINS=$(defaults read com.omnigroup.OmniFocus4 PlugInFolders 2>/dev/null || echo "")

if [ -n "$CUSTOM_PLUGINS" ]; then
    # Extract the first custom plugin folder path from plist
    FIRST_CUSTOM=$(echo "$CUSTOM_PLUGINS" | grep -o '"[^"]*"' | head -1 | tr -d '"')
    if [ -n "$FIRST_CUSTOM" ] && [ -d "$FIRST_CUSTOM" ]; then
        PLUGIN_DIR="$FIRST_CUSTOM"
        echo "✅ Found custom plugin folder: $PLUGIN_DIR"
    fi
fi

# Priority 2: Check for OmniFocus 4 sandbox directory (most common)
if [ -z "${PLUGIN_DIR:-}" ]; then
    SANDBOX_DIR="$HOME/Library/Containers/com.omnigroup.OmniFocus4/Data/Library/Application Support/Plug-Ins"
    if [ -d "$SANDBOX_DIR" ]; then
        PLUGIN_DIR="$SANDBOX_DIR"
        echo "✅ Found OmniFocus 4 sandbox plugin directory"
    fi
fi

# Priority 3: Check for iCloud sync directory
if [ -z "${PLUGIN_DIR:-}" ]; then
    ICLOUD_DIR="$HOME/Library/Mobile Documents/iCloud~com~omnigroup~OmniFocus/Documents/Plug-Ins"
    if [ -d "$ICLOUD_DIR" ]; then
        PLUGIN_DIR="$ICLOUD_DIR"
        echo "✅ Found iCloud-synced plugin directory"
    fi
fi

# Priority 4: Legacy Application Support (OmniFocus 3 and earlier)
if [ -z "${PLUGIN_DIR:-}" ]; then
    LEGACY_DIR="$HOME/Library/Application Support/OmniFocus/Plug-Ins"
    PLUGIN_DIR="$LEGACY_DIR"
    echo "⚠️  Using legacy plugin directory (OmniFocus 3 or earlier)"
fi

# Ensure the directory exists
mkdir -p "$PLUGIN_DIR"

# Install the plugin
rm -rf "$PLUGIN_DIR/FocusRelayBridge.omnijs"
cp -R "$PLUGIN_SRC" "$PLUGIN_DIR/FocusRelayBridge.omnijs"

echo ""
echo "✅ Successfully installed FocusRelayBridge.omnijs to:"
echo "   $PLUGIN_DIR"
echo ""
echo "🔄 IMPORTANT: You MUST restart OmniFocus completely for changes to take effect."
echo ""
echo "   Run this command:"
echo "   osascript -e 'tell application \"OmniFocus\" to quit' && sleep 2 && open -a \"OmniFocus\""
echo ""
echo "⚠️  NOTE: The first time you run a query, OmniFocus will ask you to approve"
echo "   the automation script. Click \"Run Script\" when prompted."
