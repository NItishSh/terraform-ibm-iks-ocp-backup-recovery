#!/bin/bash
set -euo pipefail

# cancel_pg_runs.sh — pause a protection group, cancel any active runs/archival
# tasks, then wait for all work to reach a terminal state before returning.
#
# Uses the ibmcloud backup-recovery CLI (br plugin) so no bearer-token
# management or raw curl is needed.
#
# Usage: cancel_pg_runs.sh REGION TENANT PROTECTION_GROUP_ID
#   REGION               — IBM Cloud region of the BRS instance (e.g. us-south)
#   TENANT               — X-IBM-Tenant-Id value (e.g. 8phgk0sod0)
#   PROTECTION_GROUP_ID  — full Terraform ID (clusterid/::timestamp:id:id)
#
# Required env var:
#   IBMCLOUD_API_KEY     — IBM Cloud API key used to log in

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common_utils.sh
source "${SCRIPT_DIR}/common_utils.sh"

if [ "$#" -lt 3 ]; then
  echo "Usage: $0 REGION TENANT PROTECTION_GROUP_ID" >&2
  echo "Note: IBMCLOUD_API_KEY must be set as an environment variable" >&2
  exit 1
fi

if [ -z "${IBMCLOUD_API_KEY:-}" ]; then  # pragma: allowlist secret
  echo "ERROR: IBMCLOUD_API_KEY environment variable is not set" >&2
  exit 1
fi

REGION=$1
TENANT=$2
PROTECTION_GROUP_ID=$3

# Extract numeric PG ID (after ::)
# Format: clusterid/::timestamp:id:id -> timestamp:id:id
API_PG_ID="${PROTECTION_GROUP_ID#*::}"

# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------
ibmcloud_login() {
  echo "Logging in to IBM Cloud (region: ${REGION})..." >&2
  ibmcloud login --apikey "${IBMCLOUD_API_KEY}" -r "${REGION}" -q 2>&1 | grep -v "^$" >&2 || true
}

# ---------------------------------------------------------------------------
# Helpers — thin wrappers around the CLI, output is raw JSON (--output json)
# ---------------------------------------------------------------------------

pg_run_list() {
  ibmcloud backup-recovery protection-group-run list \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --num-runs 10 \
    --include-object-details=false \
    --output json \
    -q 2>/dev/null \
    || echo '{"runs":[]}'
}

pg_run_cancel() {
  local cancel_params_json=$1
  ibmcloud backup-recovery protection-group-run perform-action \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --action Cancel \
    --cancel-params "${cancel_params_json}" \
    -q 2>/dev/null
}

pg_update_pause() {
  ibmcloud backup-recovery protection-group update \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --is-paused=true \
    -q 2>/dev/null \
    || echo "Pause request failed; continuing anyway..." >&2
}

# ---------------------------------------------------------------------------
# is_terminal: returns 0 if status is a known done/stopped state
# ---------------------------------------------------------------------------
is_terminal() {
  local status=$1
  case "$status" in
    Succeeded | Failed | Canceled | Skipped | Missed | SucceededWithWarning | \
    kSucceeded | kFailed | kCanceled | kSkipped | kMissed | kSucceededWithWarning)
      return 0 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# check_active_runs: populate ACTIVE_RUN_IDS and ACTIVE_ARCHIVAL_PAIRS
# Returns 0 if any active work exists, 1 if everything is terminal.
# ---------------------------------------------------------------------------
ACTIVE_RUN_IDS=()
ACTIVE_ARCHIVAL_PAIRS=()  # each entry: "runId archivalTaskId"

check_active_runs() {
  local run_data
  run_data=$(pg_run_list)

  ACTIVE_RUN_IDS=()
  ACTIVE_ARCHIVAL_PAIRS=()

  local total_runs
  total_runs=$(echo "$run_data" | jq '.runs | length // 0')
  echo "Total runs returned: ${total_runs}" >&2

  if [[ "$total_runs" -eq 0 ]]; then
    return 1
  fi

  local i
  for (( i = 0; i < total_runs; i++ )); do
    local run_id run_status
    run_id=$(echo "$run_data" | jq -r ".runs[${i}].id // empty")
    run_status=$(echo "$run_data" | jq -r ".runs[${i}].status // empty")

    echo "Run[${i}]: id=${run_id:-<none>}, status=${run_status:-<none>}" >&2
    [[ -z "$run_id" ]] && continue

    if ! is_terminal "$run_status"; then
      echo "  -> Non-terminal run status '${run_status}'" >&2
      ACTIVE_RUN_IDS+=("$run_id")
    fi

    # Check archival tasks regardless of main run status — an archival task
    # can remain active even after the main backup phase completes (Succeeded).
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
    return 0
  fi
  return 1
}

cancel_active_runs() {
  check_active_runs || true

  local active_found
  active_found=$(( ${#ACTIVE_RUN_IDS[@]} + ${#ACTIVE_ARCHIVAL_PAIRS[@]} ))

  # Cancel non-terminal runs
  local run_id
  for run_id in "${ACTIVE_RUN_IDS[@]}"; do
    echo "  -> Cancelling run ${run_id}..." >&2
    pg_run_cancel "[{\"runId\": \"${run_id}\"}]" > /dev/null \
      || echo "  -> Cancel request may have failed, continuing..." >&2
  done

  # Cancel active archival tasks — archivalTaskId is an array per the API schema
  local pair
  for pair in "${ACTIVE_ARCHIVAL_PAIRS[@]}"; do
    local r_id a_id
    r_id="${pair%% *}"
    a_id="${pair##* }"
    echo "  -> Cancelling archival task ${a_id} (run ${r_id})..." >&2
    pg_run_cancel "[{\"runId\": \"${r_id}\", \"archivalTaskId\": [\"${a_id}\"]}]" > /dev/null \
      || echo "  -> Archival cancel request may have failed, continuing..." >&2
  done

  echo "$active_found"
}

has_active_runs() {
  check_active_runs
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  ibmcloud_login

  echo "Pausing protection group ${API_PG_ID} to block new runs..." >&2
  pg_update_pause

  # Wait briefly so any run BRS had already internally queued (but not yet
  # visible via /runs) has time to surface before we check.
  echo "Waiting 30s for in-flight run state to surface..." >&2
  sleep 30

  echo "Checking for active runs on protection group: ${API_PG_ID}" >&2
  local active_count
  active_count=$(cancel_active_runs)

  if [[ "$active_count" -eq 0 ]]; then
    echo "No active runs found. Protection group is ready for deletion." >&2
    # Brief settle: give BRS time to finish any in-progress state commit.
    sleep 30
    exit 0
  fi

  # Wait for all active runs to reach a terminal state.
  # Timeout is 60 minutes — archival (CloudArchiveDirect) tasks can take
  # 30+ minutes to cancel when mid-upload to cloud storage.
  echo "Waiting for ${active_count} active run(s) to stop (timeout 60m)..." >&2
  local timeout_at
  timeout_at=$(( $(date +%s) + 3600 ))

  while [[ "$(date +%s)" -lt "$timeout_at" ]]; do
    sleep 20
    echo "Re-checking run states..." >&2
    if ! has_active_runs; then
      echo "All runs stopped. Waiting 30s for BRS to commit final state..." >&2
      sleep 30
      exit 0
    fi
    # Re-issue cancel each iteration: a run may have transitioned from a
    # non-cancellable phase (e.g. initialising) into a cancellable one, or
    # the previous cancel may have been silently dropped by BRS.
    cancel_active_runs > /dev/null
  done

  echo "ERROR: Timed out (60 min) waiting for run cancellation to complete." >&2
  echo "Active runs/tasks are still present. Protection group cannot be safely deleted." >&2
  echo "Investigate BRS job state for protection group ${API_PG_ID} and retry." >&2
  exit 1
}

main
