#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TOTAL_HOURS="3"
WARMUP_CALLS="20"
INTERVAL_MS="1500"
COOLDOWN_MS="3000"
MEMORY_INTERVAL_SECONDS="30"
COMPLETED_AFTER="2020-01-01T00:00:00Z"
RUN_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --total-hours)
      TOTAL_HOURS="$2"
      shift 2
      ;;
    --warmup-calls)
      WARMUP_CALLS="$2"
      shift 2
      ;;
    --interval-ms)
      INTERVAL_MS="$2"
      shift 2
      ;;
    --cooldown-ms)
      COOLDOWN_MS="$2"
      shift 2
      ;;
    --memory-interval-seconds)
      MEMORY_INTERVAL_SECONDS="$2"
      shift 2
      ;;
    --completed-after)
      COMPLETED_AFTER="$2"
      shift 2
      ;;
    --run-root)
      RUN_ROOT="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$RUN_ROOT" ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  RUN_ROOT="docs/benchmarks/transport-ab-${TS}"
fi

mkdir -p "$RUN_ROOT"
DRIVER_LOG="${RUN_ROOT}/driver.log"

log() {
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" | tee -a "$DRIVER_LOG"
}

run_suite() {
  local label="$1"
  local transport="$2"
  local suite_dir="${RUN_ROOT}/${label}"

  mkdir -p "$suite_dir"
  log "START suite ${label} transport=${transport}"

  FOCUS_RELAY_BRIDGE_DISPATCH_TRANSPORT="$transport" \
    ./scripts/benchmark-suite.sh \
      --total-hours "$TOTAL_HOURS" \
      --warmup-calls "$WARMUP_CALLS" \
      --interval-ms "$INTERVAL_MS" \
      --cooldown-ms "$COOLDOWN_MS" \
      --memory-interval-seconds "$MEMORY_INTERVAL_SECONDS" \
      --completed-after "$COMPLETED_AFTER" \
      --suite-dir "$suite_dir" \
      2>&1 | tee "${suite_dir}/launch.log"

  log "END suite ${label} transport=${transport}"
}

log "RUN ROOT ${RUN_ROOT}"
run_suite "plugin-url" "url"

log "Inter-suite restart: quitting OmniFocus"
osascript -e 'tell application "OmniFocus" to quit' >/dev/null 2>&1 || true
sleep 2
pkill -x OmniFocus >/dev/null 2>&1 || true
sleep 2
log "Inter-suite restart: opening OmniFocus"
open -a "OmniFocus"
sleep 6

run_suite "plugin-jxa-dispatch" "jxa"
log "ALL DONE"
