#!/bin/bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common_utils.sh
source "${SCRIPT_DIR}/common_utils.sh"

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 URL TENANT ENDPOINT_TYPE PROTECTION_GROUP_ID" >&2
  echo "Note: API_KEY must be set as an environment variable" >&2
  exit 1
fi

if [ -z "${API_KEY:-}" ]; then  # pragma: allowlist secret
  echo "ERROR: API_KEY environment variable is not set" >&2
  exit 1
fi

URL=$1
TENANT=$2
ENDPOINT_TYPE=$3
PROTECTION_GROUP_ID=$4

# Extract numeric PG ID (after ::)
# Format: clusterid/::timestamp:id:id -> timestamp:id:id
API_PG_ID="${PROTECTION_GROUP_ID#*::}"

IAM_TOKEN="" # pragma: allowlist secret

call_api() {
  local method=$1
  local path=$2
  shift 2
  local response http_code body

  response=$(curl --retry 3 -s -w "\n%{http_code}" -X "$method" "${URL}${path}" \
    -H "Authorization: Bearer ${IAM_TOKEN}" \
    -H "X-IBM-Tenant-Id: ${TENANT}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "$@")

  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "API warning: HTTP $http_code from $method $path" >&2
    echo "$body" >&2
    return 1
  fi
  echo "$body"
}

# Returns 0 (true) if a run status is a known terminal/done state.
# Anything NOT in this list is treated as active/blocking — this intentionally
# catches statuses like kScheduled, kInitializing, kPending that BRS may use
# and that would still block a DELETE even though they look "not running".
is_terminal() {
  local status=$1
  case "$status" in
    Succeeded | Failed | Canceled | Skipped | Missed | SucceededWithWarning | \
    kSucceeded | kFailed | kCanceled | kSkipped | kMissed | kSucceededWithWarning)
      return 0 ;;
    *) return 1 ;;
  esac
}

cancel_active_runs() {
  local run_data
  run_data=$(call_api "GET" "/v2/data-protect/protection-groups/${API_PG_ID}/runs?includeObjectDetails=false&numRuns=10" || echo '{"runs":[]}')

  local total_runs active_found
  total_runs=$(echo "$run_data" | jq '.runs | length')
  active_found=0

  echo "Total runs returned by API: ${total_runs}" >&2

  for i in $(seq 0 $(( total_runs - 1 ))); do
    local run_id run_status
    run_id=$(echo "$run_data" | jq -r ".runs[${i}].id // empty")
    run_status=$(echo "$run_data" | jq -r ".runs[${i}].status // empty")

    echo "Run[${i}]: id=${run_id:-<none>}, status=${run_status:-<none>}" >&2

    if [[ -z "$run_id" ]]; then
      continue
    fi

    # Cancel the entire run if it is not in a terminal state
    if ! is_terminal "$run_status"; then
      echo "  -> Non-terminal run status '${run_status}'. Sending cancel for run ${run_id}..." >&2
      active_found=$(( active_found + 1 ))
      call_api "POST" "/v2/data-protect/protection-groups/${API_PG_ID}/runs/actions" \
        --data-raw "{\"action\": \"Cancel\", \"cancelParams\": [{\"runId\": \"${run_id}\"}]}" > /dev/null \
        || echo "  -> Cancel request may have failed, continuing..." >&2
    fi

    # Even for terminal runs, copy (archival) tasks may still be active and will
    # block protection group deletion.  Cancel each non-terminal archival task.
    local num_archival
    num_archival=$(echo "$run_data" | jq ".runs[${i}].archivalInfo.archivalTargetResults | length // 0")

    for j in $(seq 0 $(( num_archival - 1 ))); do
      local archival_status archival_task_id
      archival_status=$(echo "$run_data" | jq -r ".runs[${i}].archivalInfo.archivalTargetResults[${j}].status // empty")
      archival_task_id=$(echo "$run_data" | jq -r ".runs[${i}].archivalInfo.archivalTargetResults[${j}].archivalTaskId // empty")

      echo "  Copy task[${j}]: status=${archival_status:-<none>}, taskId=${archival_task_id:-<none>}" >&2

      if [[ -n "$archival_status" ]] && ! is_terminal "$archival_status" && [[ -n "$archival_task_id" ]]; then
        echo "  -> Active copy task '${archival_status}'. Sending cancel for archival task ${archival_task_id}..." >&2
        active_found=$(( active_found + 1 ))
        call_api "POST" "/v2/data-protect/protection-groups/${API_PG_ID}/runs/actions" \
          --data-raw "{\"action\": \"Cancel\", \"cancelParams\": [{\"runId\": \"${run_id}\", \"archivalTaskId\": \"${archival_task_id}\"}]}" > /dev/null \
          || echo "  -> Archival cancel request may have failed, continuing..." >&2
      fi
    done
  done

  echo "$active_found"
}

has_active_runs() {
  local run_data
  run_data=$(call_api "GET" "/v2/data-protect/protection-groups/${API_PG_ID}/runs?includeObjectDetails=false&numRuns=10" || echo '{"runs":[]}')

  local total_runs
  total_runs=$(echo "$run_data" | jq '.runs | length')

  for i in $(seq 0 $(( total_runs - 1 ))); do
    local run_status
    run_status=$(echo "$run_data" | jq -r ".runs[${i}].status // empty")
    if [[ -n "$run_status" ]] && ! is_terminal "$run_status"; then
      echo "Still active: run[${i}] status=${run_status}" >&2
      return 0  # has active run
    fi

    # Also check whether any copy (archival) tasks are still running
    local num_archival
    num_archival=$(echo "$run_data" | jq ".runs[${i}].archivalInfo.archivalTargetResults | length // 0")
    for j in $(seq 0 $(( num_archival - 1 ))); do
      local archival_status
      archival_status=$(echo "$run_data" | jq -r ".runs[${i}].archivalInfo.archivalTargetResults[${j}].status // empty")
      if [[ -n "$archival_status" ]] && ! is_terminal "$archival_status"; then
        echo "Still active: run[${i}] copy task[${j}] status=${archival_status}" >&2
        return 0  # has active copy task
      fi
    done
  done
  return 1  # no active runs or copy tasks
}

pause_protection_group() {
  local pg_body
  pg_body=$(call_api "GET" "/v2/data-protect/protection-groups/${API_PG_ID}") || {
    echo "Could not fetch protection group details; skipping pause..." >&2
    return 0
  }

  local paused_body
  paused_body=$(echo "$pg_body" | jq '.isPaused = true')

  call_api "PUT" "/v2/data-protect/protection-groups/${API_PG_ID}" \
    --data-raw "$paused_body" > /dev/null \
    || echo "Pause request failed; continuing anyway..." >&2
}

main() {
  echo "Getting IAM token..."
  IAM_TOKEN=$(get_iam_token "${API_KEY}" "${ENDPOINT_TYPE}") # pragma: allowlist secret

  echo "Pausing protection group ${API_PG_ID} to block new runs..."
  pause_protection_group

  # Wait briefly so any run BRS had already internally queued (but not yet
  # visible via /runs) has time to surface before we check.
  echo "Waiting 30s for in-flight run state to surface in API..."
  sleep 30

  # Cancel all non-terminal runs
  echo "Checking for active runs on protection group: ${API_PG_ID}"
  local active_count
  active_count=$(cancel_active_runs)

  if [[ "$active_count" -eq 0 ]]; then
    echo "No active runs found. Protection group is ready for deletion."
    exit 0
  fi

  # Wait for all active runs to reach a terminal state
  echo "Waiting for ${active_count} active run(s) to stop..."
  local timeout_at
  timeout_at=$(( $(date +%s) + 600 ))

  while [[ "$(date +%s)" -lt "$timeout_at" ]]; do
    sleep 15
    echo "Re-checking run states..."
    if ! has_active_runs; then
      echo "All runs stopped. Protection group is ready for deletion."
      exit 0
    fi
    # Re-issue cancel in case a run transitioned to a cancellable state
    cancel_active_runs > /dev/null
  done

  echo "WARNING: Timed out (10 min) waiting for run cancellation. Proceeding anyway." >&2
  exit 0
}

main
