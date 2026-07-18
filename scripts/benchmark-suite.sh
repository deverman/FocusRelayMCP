#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROFILE=""
TOTAL_HOURS=""
WARMUP_CALLS=""
INTERVAL_MS=""
COOLDOWN_MS=""
MEMORY_INTERVAL_SECONDS=""
COMPLETED_AFTER="2020-01-01T00:00:00Z"
SUITE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
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
    --suite-dir)
      SUITE_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  echo "--profile is required: smoke, release, or stress" >&2
  exit 1
fi

case "$PROFILE" in
  smoke)
    : "${TOTAL_HOURS:=0.5}"
    : "${WARMUP_CALLS:=10}"
    : "${INTERVAL_MS:=2000}"
    : "${COOLDOWN_MS:=3000}"
    : "${MEMORY_INTERVAL_SECONDS:=60}"
    ;;
  release)
    : "${TOTAL_HOURS:=1.5}"
    : "${WARMUP_CALLS:=10}"
    : "${INTERVAL_MS:=5000}"
    : "${COOLDOWN_MS:=5000}"
    : "${MEMORY_INTERVAL_SECONDS:=60}"
    ;;
  stress)
    : "${TOTAL_HOURS:=3}"
    : "${WARMUP_CALLS:=20}"
    : "${INTERVAL_MS:=1500}"
    : "${COOLDOWN_MS:=3000}"
    : "${MEMORY_INTERVAL_SECONDS:=30}"
    ;;
  *)
    echo "Unknown profile: $PROFILE (expected smoke, release, or stress)" >&2
    exit 1
    ;;
esac

if [[ -z "$SUITE_DIR" ]]; then
  TS="$(date +%Y%m%d-%H%M%S)"
  SUITE_DIR=".build/benchmarks/${PROFILE}-${TS}"
fi

mkdir -p "$SUITE_DIR"
SUITE_LOG="${SUITE_DIR}/suite.log"

BIN="./.build/debug/focusrelay"
if [[ ! -x "$BIN" ]]; then
  swift build -c debug
fi

PER_TOOL_HOURS="$(awk "BEGIN { printf \"%.6f\", ($TOTAL_HOURS / 3.0) }")"
TASK_COUNTS_DIR="${SUITE_DIR}/get_task_counts"
LIST_TASKS_DIR="${SUITE_DIR}/list_tasks"
PROJECT_COUNTS_DIR="${SUITE_DIR}/get_project_counts"
mkdir -p "$TASK_COUNTS_DIR" "$LIST_TASKS_DIR" "$PROJECT_COUNTS_DIR"

log() {
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" | tee -a "$SUITE_LOG"
}

write_metadata() {
  cat > "${SUITE_DIR}/metadata.md" <<META
# Benchmark Suite Metadata

- Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- Profile: ${PROFILE}
- Branch: $(git rev-parse --abbrev-ref HEAD)
- Commit: $(git rev-parse HEAD)
- Dispatch transport: url
- Total configured hours: ${TOTAL_HOURS}
- Per tool configured hours: ${PER_TOOL_HOURS}
- Warmup calls: ${WARMUP_CALLS}
- Interval ms: ${INTERVAL_MS}
- Cooldown ms: ${COOLDOWN_MS}
- Memory interval seconds: ${MEMORY_INTERVAL_SECONDS}
- Completed-after anchor: ${COMPLETED_AFTER}
META
}

run_restart_step() {
  log "Restart step: quitting OmniFocus"
  osascript -e 'tell application "OmniFocus" to quit' >/dev/null 2>&1 || true
  sleep 2
  log "Restart step: opening OmniFocus"
  open -a "OmniFocus"
  sleep 4
}

run_readiness_gate() {
  local label="$1"
  local outdir="$2"
  local log_file="${outdir}/readiness.log"
  : > "$log_file"
  log "Readiness gate start: ${label}"
  local attempts=0
  local max_attempts=10
  while (( attempts < max_attempts )); do
    attempts=$((attempts + 1))
    {
      echo "attempt=${attempts}"
      "$BIN" bridge-health-check
    } >> "$log_file" 2>&1 && {
      log "Readiness gate passed: ${label} attempt=${attempts}"
      return 0
    }
    sleep 2
  done
  log "Readiness gate failed: ${label}"
  return 1
}

run_semantic_gate() {
  local scope="$1"
  local outdir="$2"
  log "Semantic gate start: scope=${scope}"
  "$BIN" benchmark-gate-check --tool "$scope" > "${outdir}/gate.json"
  log "Semantic gate passed: scope=${scope}"
}

run_bench() {
  local name="$1"
  local outdir="$2"
  shift 2
  log "Benchmark start: ${name}"
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "${outdir}/started_at.txt"
  "$BIN" "$@" --output-dir "$outdir" 2>&1 | tee "${outdir}/run.log"
  echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "${outdir}/ended_at.txt"
  log "Benchmark end: ${name}"
}

write_metadata
run_restart_step

run_readiness_gate "before get_task_counts" "$TASK_COUNTS_DIR"
run_semantic_gate "task-counts" "$TASK_COUNTS_DIR"
run_bench \
  "get_task_counts" \
  "$TASK_COUNTS_DIR" \
  benchmark-task-counts \
  --duration-hours "$PER_TOOL_HOURS" \
  --warmup-calls "$WARMUP_CALLS" \
  --interval-ms "$INTERVAL_MS" \
  --cooldown-ms "$COOLDOWN_MS" \
  --memory-interval-seconds "$MEMORY_INTERVAL_SECONDS" \
  --completed-after "$COMPLETED_AFTER"

run_readiness_gate "before list_tasks" "$LIST_TASKS_DIR"
run_semantic_gate "list-tasks" "$LIST_TASKS_DIR"
run_bench \
  "list_tasks" \
  "$LIST_TASKS_DIR" \
  benchmark-list-tasks \
  --duration-hours "$PER_TOOL_HOURS" \
  --warmup-calls "$WARMUP_CALLS" \
  --interval-ms "$INTERVAL_MS" \
  --cooldown-ms "$COOLDOWN_MS" \
  --completed-after "$COMPLETED_AFTER"

run_readiness_gate "before get_project_counts" "$PROJECT_COUNTS_DIR"
run_semantic_gate "project-counts" "$PROJECT_COUNTS_DIR"
run_bench \
  "get_project_counts" \
  "$PROJECT_COUNTS_DIR" \
  benchmark-project-counts \
  --duration-hours "$PER_TOOL_HOURS" \
  --warmup-calls "$WARMUP_CALLS" \
  --interval-ms "$INTERVAL_MS" \
  --cooldown-ms "$COOLDOWN_MS" \
  --memory-interval-seconds "$MEMORY_INTERVAL_SECONDS" \
  --completed-after "$COMPLETED_AFTER"

cat > "${SUITE_DIR}/summary.md" <<EOF_SUMMARY
# Benchmark Suite

- Started: $(head -n1 "${TASK_COUNTS_DIR}/started_at.txt" 2>/dev/null || echo "unknown")
- Ended: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
- Branch: $(git rev-parse --abbrev-ref HEAD)
- Commit: $(git rev-parse HEAD)
- Dispatch transport: url
- Total configured hours: ${TOTAL_HOURS}
- Per tool configured hours: ${PER_TOOL_HOURS}

## Artifacts

- Metadata: ${SUITE_DIR}/metadata.md
- Suite log: ${SUITE_DIR}/suite.log
- get_task_counts: ${TASK_COUNTS_DIR}/summary.md
- list_tasks: ${LIST_TASKS_DIR}/summary.md
- get_project_counts: ${PROJECT_COUNTS_DIR}/summary.md
EOF_SUMMARY

log "Suite complete: ${SUITE_DIR}"
