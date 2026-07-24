#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_SRC="${FOCUSRELAY_PLUGIN_SRC:-$ROOT_DIR/Plugin/FocusRelayBridge.omnijs}"

if [[ ! -d "$PLUGIN_SRC" ]]; then
    echo "❌ Plugin source not found: $PLUGIN_SRC" >&2
    exit 1
fi

echo "🔍 Detecting OmniFocus plugin directories..."

export ROOT_DIR
export PLUGIN_SRC

python3 - <<'PY'
import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys

root_dir = os.environ["ROOT_DIR"]
plugin_src = os.environ["PLUGIN_SRC"]
plugin_name = "FocusRelayBridge.omnijs"
timeout_seconds = 5

sandbox_dir = os.path.expanduser(
    "~/Library/Containers/com.omnigroup.OmniFocus4/Data/Library/Application Support/Plug-Ins"
)
icloud_dir = os.path.expanduser(
    "~/Library/Mobile Documents/iCloud~com~omnigroup~OmniFocus/Documents/Plug-Ins"
)
legacy_dir = os.path.expanduser("~/Library/Application Support/OmniFocus/Plug-Ins")


def handle_timeout(signum, frame):
    raise TimeoutError("Timed out while accessing plugin directory")


def read_custom_plugin_dirs():
    try:
        result = subprocess.run(
            ["defaults", "read", "com.omnigroup.OmniFocus4", "PlugInFolders"],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        return []

    if result.returncode != 0:
        return []

    try:
        parsed = json.loads(result.stdout)
        if isinstance(parsed, list):
            return [os.path.expanduser(p) for p in parsed if isinstance(p, str) and p]
    except json.JSONDecodeError:
        pass

    # Fallback for plist-style output from `defaults read`.
    dirs = []
    for line in result.stdout.splitlines():
        candidate = line.strip().strip('",();')
        if candidate.startswith("/"):
            dirs.append(os.path.expanduser(candidate))
    return dirs


def add_target(targets, seen, path, reason, create_if_missing=False):
    if not path or path in seen:
        return
    if create_if_missing or os.path.isdir(path):
        targets.append((path, reason))
        seen.add(path)


def install_plugin(plugin_dir):
    signal.signal(signal.SIGALRM, handle_timeout)
    signal.alarm(timeout_seconds)
    try:
        os.makedirs(plugin_dir, exist_ok=True)
        dest = os.path.join(plugin_dir, plugin_name)
        if os.path.exists(dest):
            shutil.rmtree(dest)
        shutil.copytree(plugin_src, dest)
        signal.alarm(0)
        return dest
    finally:
        signal.alarm(0)


def sha256_file(path):
    hasher = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


targets = []
seen = set()

for custom_dir in read_custom_plugin_dirs():
    add_target(targets, seen, custom_dir, "custom", create_if_missing=False)

add_target(targets, seen, icloud_dir, "icloud", create_if_missing=False)
add_target(targets, seen, sandbox_dir, "sandbox", create_if_missing=True)
add_target(targets, seen, legacy_dir, "legacy", create_if_missing=False)

if not targets:
    print("❌ Failed to detect any OmniFocus plugin directory.", file=sys.stderr)
    sys.exit(1)

print("Detected plugin directories:")
for path, reason in targets:
    print(f"  - {path} ({reason})")

installed = []
errors = []
for path, reason in targets:
    try:
        dest = install_plugin(path)
        bridge_js = os.path.join(dest, "Resources", "BridgeLibrary.js")
        installed.append((path, reason, bridge_js, sha256_file(bridge_js)))
    except TimeoutError:
        errors.append(f"Timed out accessing {path}")
    except Exception as exc:
        errors.append(f"{path}: {exc}")

if not installed:
    print("❌ Failed to install plugin in any known OmniFocus directory.", file=sys.stderr)
    for message in errors:
        print(f"   {message}", file=sys.stderr)
    sys.exit(1)

print("")
print("✅ Installed FocusRelayBridge.omnijs to:")
for path, reason, _, digest in installed:
    print(f"   {path} ({reason})")
    print(f"      BridgeLibrary.js sha256: {digest}")

if errors:
    print("")
    print("⚠️  Some plugin locations could not be updated:")
    for message in errors:
        print(f"   {message}")

if len(installed) > 1:
    print("")
    print("ℹ️  Multiple OmniFocus plugin directories were updated to keep duplicate bundles in sync.")

print("")
print("🔄 IMPORTANT: You MUST restart OmniFocus completely for changes to take effect.")
print("")
print("   Run this command:")
print("   osascript -e 'tell application \"OmniFocus\" to quit' && sleep 2 && open -a \"OmniFocus\"")
print("")
print("⚠️  NOTE: The first time you run a query, OmniFocus may ask you to approve")
print("   the automation script. Click \"Run Script\" when prompted.")
PY
