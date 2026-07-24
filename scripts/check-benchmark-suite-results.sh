#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 SUITE_DIR" >&2
  exit 2
fi

SUITE_DIR="$1"
FAILURES=()

check_tool() {
  local tool="$1"
  shift
  local raw="${SUITE_DIR}/${tool}/raw.jsonl"
  local summary="${SUITE_DIR}/${tool}/summary.md"

  if [[ ! -s "$raw" ]]; then
    FAILURES+=("${tool}: missing or empty raw.jsonl")
    return
  fi
  if [[ ! -s "$summary" ]]; then
    FAILURES+=("${tool}: missing or empty summary.md")
  fi
  if ! jq -e -c . "$raw" >/dev/null 2>&1; then
    FAILURES+=("${tool}: malformed JSON in raw.jsonl")
    return
  fi

  local measured=0
  local line_number=0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    if [[ "$line" == *'"phase":"measured"'* ]]; then
      measured=$((measured + 1))
      if [[ "$line" != *'"ok":true'* ]]; then
        FAILURES+=("${tool}: measured call ${line_number} is not successful")
      fi
      if [[ "$line" == *'"timeout":true'* ]]; then
        FAILURES+=("${tool}: measured call ${line_number} timed out")
      fi
      if [[ "$line" == *'"error":'* ]]; then
        FAILURES+=("${tool}: measured call ${line_number} reported an error")
      fi
    fi
  done < "$raw"

  if (( measured == 0 )); then
    FAILURES+=("${tool}: no measured calls")
  fi

  local scenario
  for scenario in "$@"; do
    if ! jq -e --arg scenario "$scenario" \
      'select(.phase == "measured" and .scenario == $scenario)' \
      "$raw" >/dev/null
    then
      FAILURES+=("${tool}: missing measured scenario ${scenario}")
    fi
  done
}

check_tool get_task_counts \
  default inbox_only available_only completed_after_anchor flagged_only search_no_match
check_tool list_tasks \
  default default_no_total inbox_only inbox_only_no_total available_only \
  available_only_no_total completed_after_anchor flagged_only flagged_only_no_total \
  search_no_match
check_tool get_project_counts \
  project_view_remaining project_view_active project_view_available \
  project_view_everything completed_after_anchor

if (( ${#FAILURES[@]} > 0 )); then
  echo "Benchmark suite failed closed: ${SUITE_DIR}" >&2
  printf '  - %s\n' "${FAILURES[@]}" >&2
  echo "Artifacts retained under ${SUITE_DIR}" >&2
  exit 1
fi

echo "Benchmark suite evidence passed: ${SUITE_DIR}"
