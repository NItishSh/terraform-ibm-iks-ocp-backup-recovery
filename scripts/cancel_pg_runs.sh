#!/bin/bash
set -euo pipefail

# cancel_pg_runs.sh — pause a protection group, cancel any active runs/archival
# tasks, then wait for all work to reach a terminal state before returning.
#
# Uses the ibmcloud backup-recovery CLI (br plugin) so no bearer-token
# management or raw curl is needed.
#
# Usage: cancel_pg_runs.sh REGION TENANT PROTECTION_GROUP_ID BRS_ENDPOINT
#   REGION               — IBM Cloud region of the BRS instance (e.g. us-south)
#   TENANT               — X-IBM-Tenant-Id value (e.g. 8phgk0sod0/)
#   PROTECTION_GROUP_ID  — full Terraform ID (clusterid/::timestamp:id:id)
#   BRS_ENDPOINT         — BRS hostname without scheme or path
#                          e.g. <guid>.<region>.backup-recovery.cloud.ibm.com
#                          Used to set the ibmcloud br service-url before any
#                          backup-recovery CLI calls. Without this every br
#                          command silently fails with an auth/404 error.
#
# Required env var:
#   IBMCLOUD_API_KEY     — IBM Cloud API key used to log in
#
# Optional env var:
#   VERBOSE              — set to 1 to print every raw API response to stderr.
#                          Off (0) by default to keep Terraform output clean.
#                          Enable when diagnosing whether failures originate
#                          in server responses or in this script's logic.
#                          Example: VERBOSE=1 terraform destroy

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common_utils.sh
source "${SCRIPT_DIR}/common_utils.sh"

# ---------------------------------------------------------------------------
# Verbose logging — all raw API responses are emitted to stderr when VERBOSE=1.
# Toggle off once the script is known-good to reduce Terraform output noise.
# ---------------------------------------------------------------------------
VERBOSE="${VERBOSE:-0}"

# vlog LABEL JSON — print label + pretty-printed JSON to stderr when verbose.
vlog() {
  [[ "${VERBOSE}" == "1" ]] || return 0
  local label="$1"
  local body="$2"
  echo "[VERBOSE] ${label}:" >&2
  echo "${body}" | jq '.' 2>/dev/null >&2 || echo "${body}" >&2
}

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 REGION TENANT PROTECTION_GROUP_ID BRS_ENDPOINT" >&2
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
BRS_ENDPOINT=$4

# Extract numeric PG ID (after ::)
# Format: clusterid/::timestamp:id:id -> timestamp:id:id
API_PG_ID="${PROTECTION_GROUP_ID#*::}"

# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------
ibmcloud_login() {
  echo "Logging in to IBM Cloud (region: ${REGION})..." >&2
  local login_out
  login_out=$(ibmcloud login --apikey "${IBMCLOUD_API_KEY}" -r "${REGION}" -q 2>&1) || true
  echo "${login_out}" | grep -v "^$" >&2 || true
  vlog "ibmcloud login" "${login_out}"

  # Set the BRS service URL so all backup-recovery CLI commands reach the
  # correct instance. Without this step every 'ibmcloud backup-recovery'
  # command fails with an authentication or 404 error — the CLI has no default
  # endpoint and the config is not persisted between sessions.
  local brs_url="https://${BRS_ENDPOINT}/v2"
  echo "Setting BRS service URL: ${brs_url}" >&2
  ibmcloud backup-recovery config set service-url "${brs_url}" 2>&1 \
    | grep -v "^$" >&2 || true
}

# ---------------------------------------------------------------------------
# Pause the protection group to block new runs.
#
# 'protection-group update' requires --name, --policy-id, and --environment
# even when only changing --is-paused. For kKubernetes PGs it also requires
# --kubernetes-params (confirmed on live instance: omitting it returns
# "Parameters 'kubernetesParams' must be specified for environment type
# 'kKubernetes'"). We GET the group first, extract all required fields,
# then pass them verbatim back in the update.
# ---------------------------------------------------------------------------
pg_pause() {
  local pg_json
  pg_json=$(ibmcloud backup-recovery protection-group get \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --output json -q 2>&1) || {
    echo "Could not fetch protection group details; skipping pause." >&2
    vlog "protection-group get (error)" "${pg_json}"
    return 0
  }
  vlog "protection-group get" "${pg_json}"

  local pg_name pg_policy_id pg_env
  pg_name=$(echo       "$pg_json" | jq -r '.name        // empty')
  pg_policy_id=$(echo  "$pg_json" | jq -r '.policyId    // empty')
  pg_env=$(echo        "$pg_json" | jq -r '.environment // empty')

  if [[ -z "$pg_name" || -z "$pg_policy_id" || -z "$pg_env" ]]; then
    echo "Could not extract required PG fields (name/policyId/environment); skipping pause." >&2
    return 0
  fi

  # Build the update command as an array so we can conditionally append
  # --kubernetes-params without messy quoting or eval.
  local -a update_cmd=(
    ibmcloud backup-recovery protection-group update
    --id             "${API_PG_ID}"
    --xibm-tenant-id "${TENANT}"
    --name           "${pg_name}"
    --policy-id      "${pg_policy_id}"
    --environment    "${pg_env}"
    --is-paused=true
    -q
  )

  # kKubernetes PGs require the full kubernetesParams body on every update.
  if [[ "${pg_env}" == "kKubernetes" ]]; then
    local k8s_params
    k8s_params=$(echo "$pg_json" | jq -c '.kubernetesParams // empty')
    if [[ -n "${k8s_params}" ]]; then
      update_cmd+=(--kubernetes-params "${k8s_params}")
    else
      echo "Warning: kKubernetes PG has no kubernetesParams in GET response; pause may fail." >&2
    fi
  fi

  local update_out
  update_out=$("${update_cmd[@]}" 2>&1) \
    || { echo "Pause request failed; continuing anyway..." >&2
         vlog "protection-group update (error)" "${update_out}"
         return 0; }
  vlog "protection-group update" "${update_out}"
  echo "Protection group ${API_PG_ID} paused successfully." >&2
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

# Non-terminal status values (same set applies to both phases).
ACTIVE_STATUSES="Accepted,Running,Canceling,OnHold,Finalizing"

# pg_active_backup_runs — finds runs where the LOCAL backup phase is non-terminal.
# NOTE: CloudArchiveDirect (CAD) PGs have no local backup phase.
#   .localBackupInfo is null and top-level .status is null for CAD runs.
#   --local-backup-run-status returns an empty list for CAD PGs.
#   These runs are only detectable via pg_active_archival_runs.
pg_active_backup_runs() {
  local out
  out=$(ibmcloud backup-recovery protection-group-run list \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --local-backup-run-status "${ACTIVE_STATUSES}" \
    --num-runs 10 \
    --include-object-details=false \
    --output json -q 2>&1) \
    || out='{"runs":[]}'
  # Guard: CLI may return empty string (not JSON) on a valid 200 with no runs.
  [[ "${out}" == *"{"* ]] || out='{"runs":[]}'
  vlog "protection-group-run list (backup)" "${out}"
  echo "${out}"
}

# pg_active_archival_runs — finds runs where an ARCHIVAL task is non-terminal.
# This is the ONLY reliable way to detect active CAD PG runs.
pg_active_archival_runs() {
  local out
  out=$(ibmcloud backup-recovery protection-group-run list \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --archival-run-status "${ACTIVE_STATUSES}" \
    --num-runs 10 \
    --include-object-details=false \
    --output json -q 2>&1) \
    || out='{"runs":[]}'
  # Guard: CLI may return empty string (not JSON) on a valid 200 with no runs.
  [[ "${out}" == *"{"* ]] || out='{"runs":[]}'
  vlog "protection-group-run list (archival)" "${out}"
  echo "${out}"
}

# ---------------------------------------------------------------------------
# check_and_cancel: single pass — detect active work and issue cancels.
#
# Both list calls are still needed (backup and archival use different
# server-side status filters), but per-run we merge localTaskId (backup)
# and archivalTaskId[] (archival) into ONE perform-action cancel call
# instead of issuing a separate call per phase.
#
# cancelParams schema (BRS API):
#   runId          String     required
#   localTaskId    String     optional — backup-phase task ID
#   archivalTaskId String[]   optional — archival task IDs to cancel
#
# Once a task reaches "Canceling" status, BRS rejects further cancel
# requests with "Copy Task: ... not found or not running".  We skip
# re-issuing cancel for tasks already in Canceling — they just need time.
#
# Returns the total count of active run IDs found (via stdout).
# All diagnostic output goes to stderr.
# ---------------------------------------------------------------------------
check_and_cancel() {
  local active_found=0

  local backup_data archival_data
  backup_data=$(pg_active_backup_runs)
  archival_data=$(pg_active_archival_runs)

  # Collect the union of all active run IDs across both responses.
  local all_run_ids
  all_run_ids=$(
    { echo "$backup_data"; echo "$archival_data"; } \
      | jq -rs '[.[].runs[].id // empty] | unique | .[]'
  )

  [[ -z "$all_run_ids" ]] && { echo "0"; return 0; }

  while IFS= read -r run_id; do
    [[ -z "$run_id" ]] && continue

    # --- extract backup-phase info for this run (absent for CAD PGs) ---
    # For CloudArchiveDirect PGs: .localBackupInfo is null and .status is null.
    # local_task_id will be empty — that's correct, we just won't set it in cancelParams.
    local local_task_id run_status
    local_task_id=$(echo "$backup_data" | jq -r --arg id "$run_id" \
      '.runs[] | select(.id == $id) | .localBackupInfo.localTaskId // empty')
    run_status=$(echo "$backup_data" | jq -r --arg id "$run_id" \
      '.runs[] | select(.id == $id) | .status // empty')

    # --- extract archival tasks that are NOT yet Canceling ---
    # Once a task is Canceling, BRS rejects further cancel requests.
    # Only send cancel for tasks still in a pre-cancel active state.
    local archival_task_ids
    archival_task_ids=$(echo "$archival_data" | jq -r --arg id "$run_id" '
      [ .runs[] | select(.id == $id) |
        (.archivalInfo.archivalTargetResults // [])[] |
        select(
          .archivalTaskId != null and .archivalTaskId != "" and
          .status != null and (.status | test("Canceling") | not)
        ) |
        .archivalTaskId
      ] | unique | .[]
    ')

    local a_statuses
    a_statuses=$(echo "$archival_data" | jq -r --arg id "$run_id" '
      [ .runs[] | select(.id == $id) |
        (.archivalInfo.archivalTargetResults // [])[] |
        select(.archivalTaskId != null and .archivalTaskId != "") |
        "\(.archivalTaskId)=\(.status // "unknown")"
      ] | .[]
    ')

    echo "  Run ${run_id}: backup_status=${run_status:-none} archival=[${a_statuses//$'\n'/, }]" >&2

    # Skip this run entirely if nothing needs a cancel request
    # (backup not active, all archival tasks already Canceling or terminal)
    if [[ -z "$local_task_id" && -z "$archival_task_ids" ]]; then
      echo "  Run ${run_id}: all tasks already Canceling or terminal — waiting..." >&2
      active_found=$(( active_found + 1 ))
      continue
    fi

    # --- build cancelParams JSON for this run ---
    local cancel_obj
    cancel_obj=$(jq -n --arg rid "$run_id" '{"runId": $rid}')

    # Attach localTaskId if the backup phase is still active.
    if [[ -n "$local_task_id" ]]; then
      cancel_obj=$(echo "$cancel_obj" | jq --arg ltid "$local_task_id" \
        '. + {"localTaskId": $ltid}')
    fi

    # Attach archivalTaskId array for tasks that still need a cancel signal.
    if [[ -n "$archival_task_ids" ]]; then
      local arch_array
      arch_array=$(echo "$archival_task_ids" | jq -Rs '[split("\n")[] | select(. != "")]')
      cancel_obj=$(echo "$cancel_obj" | jq --argjson arr "$arch_array" \
        '. + {"archivalTaskId": $arr}')
    fi

    local cancel_params="[${cancel_obj}]"
    echo "  Issuing cancel for run ${run_id}..." >&2
    local cancel_out
    cancel_out=$(ibmcloud backup-recovery protection-group-run perform-action \
      --id "${API_PG_ID}" \
      --xibm-tenant-id "${TENANT}" \
      --action Cancel \
      --cancel-params "${cancel_params}" \
      -q 2>&1) \
      || echo "  Cancel request may have failed, continuing..." >&2
    vlog "perform-action Cancel run=${run_id} params=${cancel_params}" "${cancel_out}"

    active_found=$(( active_found + 1 ))
  done <<< "$all_run_ids"

  echo "$active_found"
}

# Returns 0 (active work exists) or 1 (all terminal).
#
# Counts active items across BOTH phases:
#   backup_count  — runs with a non-terminal local backup phase (0 for CAD PGs)
#   archival_count — archival tasks with a non-terminal status (the only signal for CAD PGs)
#
# IMPORTANT: do NOT use '.runs | length' for backup_count — that counts all returned
# runs, not just ones with an active backup phase. Use the archivalTargetResults
# status check for archival, and the run-level .status for non-CAD backup runs.
has_active_work() {
  local backup_data archival_data backup_count archival_count
  backup_data=$(pg_active_backup_runs)
  archival_data=$(pg_active_archival_runs)

  # Non-CAD PGs: count runs where the backup-phase .status is non-null (active).
  # Use (.runs // []) to guard against null .runs (e.g. non-JSON CLI response).
  backup_count=$(echo "$backup_data" | jq '
    [ (.runs // [])[] | select(.status != null and .status != "") ] | length' \
    2>/dev/null) || backup_count=0
  [[ "${backup_count}" =~ ^[0-9]+$ ]] || backup_count=0

  # Both CAD and non-CAD: count archival tasks with a non-terminal status.
  # (.runs // []) guards null root; (.archivalInfo.archivalTargetResults // [])
  # guards null .archivalInfo on terminal runs (confirmed in live testing).
  archival_count=$(echo "$archival_data" | jq '
    [ (.runs // [])[] |
      (.archivalInfo.archivalTargetResults // [])[] |
      select(.archivalTaskId != null and .archivalTaskId != "")
    ] | length' \
    2>/dev/null) || archival_count=0
  [[ "${archival_count}" =~ ^[0-9]+$ ]] || archival_count=0

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
    # Even when no runs are visible, BRS may have just queued one internally
    # (e.g. immediately after receiving the pause request). Wait 2 minutes and
    # re-check before declaring the PG clear. This prevents a race where the
    # scheduler commits a run between our last check and the TF provider delete.
    echo "No active runs found — waiting 2m for any late-arriving runs..." >&2
    sleep 120
    if has_active_work; then
      echo "Newly-arrived run(s) detected after settle wait — entering cancel loop." >&2
      # Fall through to the main cancel/wait loop below.
    else
      echo "Still no active runs after settle. Protection group is ready for deletion." >&2
      exit 0
    fi
    active_count=$(check_and_cancel)
  fi

  # Wait for all active runs to reach a terminal state.
  # Timeout is 20 minutes — archival (CloudArchiveDirect) tasks can take
  # several minutes to cancel when mid-upload to cloud storage.
  echo "Waiting for ${active_count} active run(s) to stop (timeout 20m)..." >&2
  local timeout_at
  timeout_at=$(( $(date +%s) + 1200 ))

  while [[ "$(date +%s)" -lt "$timeout_at" ]]; do
    sleep 15
    echo "Re-checking run states..."
    if ! has_active_work; then
      echo "All runs stopped. Sleeping 60s for BRS backend state propagation..."
      sleep 60
      echo "Protection group is ready for deletion."
      exit 0
    fi
    # Re-issue cancel each iteration: a run may have transitioned from a
    # non-cancellable phase (e.g. initialising) into a cancellable one, or
    # the previous cancel may have been silently dropped by BRS.
    check_and_cancel > /dev/null
  done

  echo "WARNING: Timed out (20 min) waiting for run cancellation. Proceeding anyway." >&2
  exit 0
}

main
