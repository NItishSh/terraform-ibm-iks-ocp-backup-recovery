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

IAM_TOKEN=""      # pragma: allowlist secret
TOKEN_FETCHED_AT=0  # epoch seconds when the token was last obtained

call_api() {
  local method=$1
  local path=$2
  shift 2
  local response http_code body

  # Refresh IAM token if it is older than 45 minutes (tokens last ~60 min).
  local now
  now=$(date +%s)
  if (( now - TOKEN_FETCHED_AT >= 2700 )); then
    echo "Refreshing IAM token..." >&2
    IAM_TOKEN=$(get_iam_token "${API_KEY}" "${ENDPOINT_TYPE}") # pragma: allowlist secret
    TOKEN_FETCHED_AT=$now
  fi

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

# Returns 0 (active) if any run or archival task is non-terminal.
# Populates global ACTIVE_RUN_IDS and ACTIVE_ARCHIVAL_IDS for use by callers.
ACTIVE_RUN_IDS=()
ACTIVE_ARCHIVAL_PAIRS=()  # each entry is "runId archivalTaskId" (archivalTaskId is the GET response field)

check_active_runs() {
  local run_data
  run_data=$(call_api "GET" "/v2/data-protect/protection-groups/${API_PG_ID}/runs?includeObjectDetails=false&numRuns=10" || echo '{"runs":[]}')

  ACTIVE_RUN_IDS=()
  ACTIVE_ARCHIVAL_PAIRS=()

  local total_runs
  total_runs=$(echo "$run_data" | jq '.runs | length // 0')

  echo "Total runs returned by API: ${total_runs}" >&2

  if [[ "$total_runs" -eq 0 ]]; then
    return 1  # no active runs
  fi

  local i
  for (( i = 0; i < total_runs; i++ )); do
    local run_id run_status
    run_id=$(echo "$run_data" | jq -r ".runs[${i}].id // empty")
    run_status=$(echo "$run_data" | jq -r ".runs[${i}].status // empty")

    echo "Run[${i}]: id=${run_id:-<none>}, status=${run_status:-<none>}" >&2

    if [[ -z "$run_id" ]]; then
      continue
    fi

    # Track non-terminal runs for cancel
    if ! is_terminal "$run_status"; then
      echo "  -> Non-terminal run status '${run_status}'" >&2
      ACTIVE_RUN_IDS+=("$run_id")
    fi

    # Check archival tasks regardless of main run status — an archival task
    # can remain active even after the main backup completes (Succeeded).
    local num_archival
    num_archival=$(echo "$run_data" | jq ".runs[${i}].archivalInfo.archivalTargetResults | length // 0")

    if [[ "$num_archival" -gt 0 ]]; then
      local j
      for (( j = 0; j < num_archival; j++ )); do
        local archival_status archival_task_id
        archival_status=$(echo "$run_data" | jq -r ".runs[${i}].archivalInfo.archivalTargetResults[${j}].status // empty")
        archival_task_id=$(echo "$run_data" | jq -r ".runs[${i}].archivalInfo.archivalTargetResults[${j}].archivalTaskId // empty")

        echo "  Copy task[${j}]: status=${archival_status:-<none>}, taskId=${archival_task_id:-<none>}" >&2

        if [[ -n "$archival_status" ]] && ! is_terminal "$archival_status" && [[ -n "$archival_task_id" ]]; then
          echo "  -> Active copy task '${archival_status}'" >&2
          ACTIVE_ARCHIVAL_PAIRS+=("${run_id} ${archival_task_id}")
        fi
      done
    fi
  done

  if [[ "${#ACTIVE_RUN_IDS[@]}" -gt 0 || "${#ACTIVE_ARCHIVAL_PAIRS[@]}" -gt 0 ]]; then
    return 0  # has active work
  fi
  return 1  # all terminal
}

cancel_active_runs() {
  check_active_runs || true  # populate arrays; return code used by has_active_runs, not here

  local active_found
  active_found=$(( ${#ACTIVE_RUN_IDS[@]} + ${#ACTIVE_ARCHIVAL_PAIRS[@]} ))

  # Cancel non-terminal runs
  local run_id
  for run_id in "${ACTIVE_RUN_IDS[@]}"; do
    echo "  -> Sending cancel for run ${run_id}..." >&2
    call_api "POST" "/v2/data-protect/protection-groups/${API_PG_ID}/runs/actions" \
      --data-raw "{\"action\": \"Cancel\", \"cancelParams\": [{\"runId\": \"${run_id}\"}]}" > /dev/null \
      || echo "  -> Cancel request may have failed, continuing..." >&2
  done

  # Cancel active archival tasks
  local pair
  for pair in "${ACTIVE_ARCHIVAL_PAIRS[@]}"; do
    local r_id a_id
    r_id="${pair%% *}"
    a_id="${pair##* }"
    echo "  -> Sending cancel for archival task ${a_id} (run ${r_id})..." >&2
    # archivalTaskId in cancelParams is an array per the BRS API schema.
    call_api "POST" "/v2/data-protect/protection-groups/${API_PG_ID}/runs/actions" \
      --data-raw "{\"action\": \"Cancel\", \"cancelParams\": [{\"runId\": \"${r_id}\", \"archivalTaskId\": [\"${a_id}\"]}]}" > /dev/null \
      || echo "  -> Archival cancel request may have failed, continuing..." >&2
  done

  echo "$active_found"
}

has_active_runs() {
  check_active_runs
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
  TOKEN_FETCHED_AT=$(date +%s)

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
    # Brief settle: even with no active runs, give BRS 30s to finish any
    # in-progress state commit before the provider sends DELETE.
    sleep 30
    exit 0
  fi

  # Wait for all active runs to reach a terminal state.
  # Timeout is 60 minutes — archival (CloudArchiveDirect) tasks can take
  # 30+ minutes to cancel when mid-upload to cloud storage.
  echo "Waiting for ${active_count} active run(s) to stop (timeout 60m)..."
  local timeout_at
  timeout_at=$(( $(date +%s) + 3600 ))

  while [[ "$(date +%s)" -lt "$timeout_at" ]]; do
    sleep 20
    echo "Re-checking run states..."
    if ! has_active_runs; then
      echo "All runs stopped. Waiting 30s for BRS to commit final state..."
      # Give BRS time to fully commit the terminal state before the provider
      # sends DELETE — avoids the race where the API still reports a running
      # job for a few seconds after the status transitions to terminal.
      sleep 30
      exit 0
    fi
    # Re-issue cancel each iteration: a run may have transitioned from a
    # non-cancellable phase (e.g. initialising) into a cancellable one, or
    # the previous cancel API call may have been silently dropped by BRS.
    cancel_active_runs > /dev/null
  done

  echo "ERROR: Timed out (60 min) waiting for run cancellation to complete." >&2
  echo "Active runs/tasks are still present. Protection group cannot be safely deleted." >&2
  echo "Investigate BRS job state for protection group ${API_PG_ID} and retry." >&2
  exit 1
}

main
