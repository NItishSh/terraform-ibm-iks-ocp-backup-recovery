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
# Pause the protection group to block new runs.
#
# 'protection-group update' requires --name, --policy-id, and --environment
# even when only changing --is-paused. We GET the group first to extract
# those required fields, then issue the update.
# ---------------------------------------------------------------------------
pg_pause() {
  local pg_json
  pg_json=$(ibmcloud backup-recovery protection-group get \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --output json -q 2>/dev/null) || {
    echo "Could not fetch protection group details; skipping pause." >&2
    return 0
  }

  local pg_name pg_policy_id pg_env
  pg_name=$(echo    "$pg_json" | jq -r '.name        // empty')
  pg_policy_id=$(echo "$pg_json" | jq -r '.policyId  // empty')
  pg_env=$(echo     "$pg_json" | jq -r '.environment // empty')

  if [[ -z "$pg_name" || -z "$pg_policy_id" || -z "$pg_env" ]]; then
    echo "Could not extract required PG fields (name/policyId/environment); skipping pause." >&2
    return 0
  fi

  ibmcloud backup-recovery protection-group update \
    --id          "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --name        "${pg_name}" \
    --policy-id   "${pg_policy_id}" \
    --environment "${pg_env}" \
    --is-paused=true \
    -q 2>/dev/null \
    || echo "Pause request failed; continuing anyway..." >&2
}

# ---------------------------------------------------------------------------
# Run-state queries — two targeted calls using server-side status filters:
#
#   pg_active_backup_runs  — local backup phase is non-terminal
#   pg_active_archival_runs — archival phase is non-terminal
#
# Using separate targeted list calls per phase (--local-backup-run-status /
# --archival-run-status) is more accurate than fetching all runs and
# filtering client-side: BRS only returns runs that match, so we never
# confuse a Succeeded backup run for an active one just because it still
# has an active archival task.
# ---------------------------------------------------------------------------

# Non-terminal local-backup statuses
ACTIVE_STATUSES="Accepted,Running,Canceling,OnHold,Finalizing"

pg_active_backup_runs() {
  ibmcloud backup-recovery protection-group-run list \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --local-backup-run-status "${ACTIVE_STATUSES}" \
    --num-runs 10 \
    --include-object-details=false \
    --output json -q 2>/dev/null \
    || echo '{"runs":[]}'
}

pg_active_archival_runs() {
  ibmcloud backup-recovery protection-group-run list \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --archival-run-status "${ACTIVE_STATUSES}" \
    --num-runs 10 \
    --include-object-details=false \
    --output json -q 2>/dev/null \
    || echo '{"runs":[]}'
}

# ---------------------------------------------------------------------------
# check_and_cancel: single pass — detect active work and issue cancels.
#
# Uses a single jq expression per response to extract all relevant IDs at
# once (avoids one jq fork per run/task in a loop).
#
# Returns the total count of active items found (via stdout).
# All diagnostic output goes to stderr.
# ---------------------------------------------------------------------------
check_and_cancel() {
  local active_found=0

  # --- Phase 1: non-terminal backup runs ---
  local backup_data run_ids
  backup_data=$(pg_active_backup_runs)
  # Extract all run IDs in one jq call
  run_ids=$(echo "$backup_data" | jq -r '[.runs[].id // empty] | .[]')

  if [[ -n "$run_ids" ]]; then
    while IFS= read -r run_id; do
      [[ -z "$run_id" ]] && continue
      local run_status
      run_status=$(echo "$backup_data" | jq -r --arg id "$run_id" \
        '.runs[] | select(.id == $id) | .status // "<unknown>"')
      echo "  Backup run ${run_id}: status=${run_status} → cancelling..." >&2
      ibmcloud backup-recovery protection-group-run perform-action \
        --id "${API_PG_ID}" \
        --xibm-tenant-id "${TENANT}" \
        --action Cancel \
        --cancel-params "[{\"runId\": \"${run_id}\"}]" \
        -q 2>/dev/null \
        || echo "  Cancel request may have failed, continuing..." >&2
      active_found=$(( active_found + 1 ))
    done <<< "$run_ids"
  fi

  # --- Phase 2: non-terminal archival tasks ---
  # A run's archival task may be active even when the backup phase is terminal.
  # We fetch separately using --archival-run-status so we don't miss them.
  local archival_data pairs
  archival_data=$(pg_active_archival_runs)
  # Single jq call: emit "runId archivalTaskId" lines for all active tasks
  pairs=$(echo "$archival_data" | jq -r '
    .runs[] |
    .id as $rid |
    .archivalInfo.archivalTargetResults[]? |
    select(.archivalTaskId != null and .archivalTaskId != "") |
    "\($rid) \(.archivalTaskId)"
  ')

  if [[ -n "$pairs" ]]; then
    while IFS=" " read -r r_id a_id; do
      [[ -z "$r_id" || -z "$a_id" ]] && continue
      local a_status
      a_status=$(echo "$archival_data" | jq -r --arg rid "$r_id" --arg aid "$a_id" '
        .runs[] | select(.id == $rid) |
        .archivalInfo.archivalTargetResults[] |
        select(.archivalTaskId == $aid) | .status // "<unknown>"')
      echo "  Archival task ${a_id} (run ${r_id}): status=${a_status} → cancelling..." >&2
      # archivalTaskId must be passed as a JSON array per the BRS API schema
      ibmcloud backup-recovery protection-group-run perform-action \
        --id "${API_PG_ID}" \
        --xibm-tenant-id "${TENANT}" \
        --action Cancel \
        --cancel-params "[{\"runId\": \"${r_id}\", \"archivalTaskId\": [\"${a_id}\"]}]" \
        -q 2>/dev/null \
        || echo "  Archival cancel request may have failed, continuing..." >&2
      active_found=$(( active_found + 1 ))
    done <<< "$pairs"
  fi

  echo "$active_found"
}

# Returns 0 (active work exists) or 1 (all terminal).
has_active_work() {
  local backup_count archival_count
  backup_count=$(pg_active_backup_runs  | jq '.runs | length // 0')
  archival_count=$(pg_active_archival_runs | jq '
    [ .runs[].archivalInfo.archivalTargetResults[]? |
      select(.archivalTaskId != null and .archivalTaskId != "") ] | length')
  [[ "$backup_count" -gt 0 || "$archival_count" -gt 0 ]]
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  ibmcloud_login

  echo "Pausing protection group ${API_PG_ID} to block new runs..." >&2
  pg_pause

  # Wait briefly so any run BRS had already internally queued (but not yet
  # visible via /runs) has time to surface before we check.
  echo "Waiting 30s for in-flight run state to surface..." >&2
  sleep 30

  echo "Checking for active runs on protection group: ${API_PG_ID}" >&2
  local active_count
  active_count=$(check_and_cancel)

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
    if ! has_active_work; then
      echo "All runs stopped. Waiting 30s for BRS to commit final state..." >&2
      sleep 30
      exit 0
    fi
    # Re-issue cancel each iteration: a run may have transitioned from a
    # non-cancellable phase (e.g. initialising) into a cancellable one, or
    # the previous cancel may have been silently dropped by BRS.
    check_and_cancel > /dev/null
  done

  echo "ERROR: Timed out (60 min) waiting for run cancellation to complete." >&2
  echo "Active runs/tasks are still present. Protection group cannot be safely deleted." >&2
  echo "Investigate BRS job state for protection group ${API_PG_ID} and retry." >&2
  exit 1
}

main
