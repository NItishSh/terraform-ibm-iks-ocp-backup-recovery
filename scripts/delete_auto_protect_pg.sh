#!/bin/bash
set -euo pipefail

# delete_auto_protect_pg.sh — pause, drain active runs, then delete a BRS
# auto-protect protection group that was created by BRS itself (not tracked
# in Terraform state).
#
# Uses the ibmcloud backup-recovery CLI (br plugin) throughout — no raw curl
# or manual IAM token management.  Mirrors cancel_pg_runs.sh exactly for the
# pause + cancel + drain loop, then adds a final CLI delete.
#
# Usage: delete_auto_protect_pg.sh REGION TENANT PROTECTION_GROUP_ID BRS_ENDPOINT \
#                                   [REGISTRATION_ID]
#   REGION               — IBM Cloud region (e.g. us-south)
#   TENANT               — X-IBM-Tenant-Id value (e.g. mq9k8wzuwf/)
#   PROTECTION_GROUP_ID  — full Terraform PG ID (tenant/::timestamp:id:id)
#   BRS_ENDPOINT         — BRS hostname without scheme/path
#                          e.g. <guid>.<region>.backup-recovery.cloud.ibm.com
#   REGISTRATION_ID      — accepted but ignored (snapshot expiry not implemented)
#
# Required env var:
#   IBMCLOUD_API_KEY     — IBM Cloud API key
#
# Optional env var:
#   VERBOSE              — set to 1 to print every raw CLI response to stderr

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common_utils.sh
source "${SCRIPT_DIR}/common_utils.sh"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
if [ "$#" -lt 4 ]; then
  echo "Usage: $0 REGION TENANT PROTECTION_GROUP_ID BRS_ENDPOINT [REGISTRATION_ID]" >&2
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
# REGISTRATION_ID ($5) accepted but not used — snapshot expiry skipped for now.

# Extract numeric PG ID (strip leading "tenant::" prefix).
# Full Terraform ID format:  tenant/::timestamp:pgid:something
# API expects:               timestamp:pgid:something
API_PG_ID="${PROTECTION_GROUP_ID#*::}"

# ---------------------------------------------------------------------------
# Verbose logging
# ---------------------------------------------------------------------------
VERBOSE="${VERBOSE:-0}"

vlog() {
  [[ "${VERBOSE}" == "1" ]] || return 0
  local label="$1"
  local body="$2"
  echo "[VERBOSE] ${label}:" >&2
  echo "${body}" | jq '.' 2>/dev/null >&2 || echo "${body}" >&2
}

# ---------------------------------------------------------------------------
# Login + set BRS service URL (identical to cancel_pg_runs.sh)
# ---------------------------------------------------------------------------
ibmcloud_login() {
  echo "Logging in to IBM Cloud (region: ${REGION})..." >&2
  local login_out
  login_out=$(ibmcloud login --apikey "${IBMCLOUD_API_KEY}" -r "${REGION}" -q 2>&1) || true  # pragma: allowlist secret
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
# pg_pause — GET first, echo all required fields back verbatim on the PUT.
# kKubernetes PGs require kubernetesParams on every update or BRS returns
# "Parameters 'kubernetesParams' must be specified for environment type kKubernetes".
# Returns 0 on success, 1 (without exiting) when the PG is already gone.
# ---------------------------------------------------------------------------
pg_pause() {
  local pg_json
  pg_json=$(ibmcloud backup-recovery protection-group get \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --output json -q 2>&1) || {
    echo "Could not fetch protection group details; skipping pause." >&2
    vlog "protection-group get (error)" "${pg_json}"
    return 1
  }
  vlog "protection-group get" "${pg_json}"

  # 404 / "not found" responses come back as non-zero exit from the CLI.
  # Guard against an empty or error JSON body just in case.
  if echo "${pg_json}" | jq -e '.statusCode == 404 or .error != null' > /dev/null 2>&1; then
    echo "Protection group ${API_PG_ID} already gone. Skipping pause." >&2
    return 1
  fi

  local pg_name pg_policy_id pg_env
  pg_name=$(echo      "${pg_json}" | jq -r '.name        // empty')
  pg_policy_id=$(echo "${pg_json}" | jq -r '.policyId    // empty')
  pg_env=$(echo       "${pg_json}" | jq -r '.environment // empty')

  if [[ -z "${pg_name}" || -z "${pg_policy_id}" || -z "${pg_env}" ]]; then
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

  if [[ "${pg_env}" == "kKubernetes" ]]; then
    local k8s_params
    k8s_params=$(echo "${pg_json}" | jq -c '.kubernetesParams // empty')
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
# Run-state queries — two targeted server-side status filter calls.
# ---------------------------------------------------------------------------
ACTIVE_STATUSES="Accepted,Running,Canceling,OnHold,Finalizing"

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
  [[ "${out}" == *"{"* ]] || out='{"runs":[]}'
  vlog "protection-group-run list (backup)" "${out}"
  echo "${out}"
}

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
  [[ "${out}" == *"{"* ]] || out='{"runs":[]}'
  vlog "protection-group-run list (archival)" "${out}"
  echo "${out}"
}

# ---------------------------------------------------------------------------
# check_and_cancel — single pass across all active runs.
# Merges backup-phase localTaskId and archival-phase archivalTaskId[] into
# one cancel action per run.  Skips tasks already in Canceling state.
# Prints active run count to stdout; all diagnostic output goes to stderr.
# ---------------------------------------------------------------------------
check_and_cancel() {
  local active_found=0

  local backup_data archival_data
  backup_data=$(pg_active_backup_runs)
  archival_data=$(pg_active_archival_runs)

  local all_run_ids
  all_run_ids=$(
    { echo "$backup_data"; echo "$archival_data"; } \
      | jq -rs '[.[].runs[].id // empty] | unique | .[]'
  )

  [[ -z "$all_run_ids" ]] && { echo "0"; return 0; }

  while IFS= read -r run_id; do
    [[ -z "$run_id" ]] && continue

    local local_task_id run_status
    local_task_id=$(echo "$backup_data" | jq -r --arg id "$run_id" \
      '.runs[] | select(.id == $id) | .localBackupInfo.localTaskId // empty')
    run_status=$(echo "$backup_data" | jq -r --arg id "$run_id" \
      '.runs[] | select(.id == $id) | .status // empty')

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

    if [[ -z "$local_task_id" && -z "$archival_task_ids" ]]; then
      echo "  Run ${run_id}: all tasks already Canceling or terminal — waiting..." >&2
      active_found=$(( active_found + 1 ))
      continue
    fi

    local cancel_obj
    cancel_obj=$(jq -n --arg rid "$run_id" '{"runId": $rid}')

    if [[ -n "$local_task_id" ]]; then
      cancel_obj=$(echo "$cancel_obj" | jq --arg ltid "$local_task_id" \
        '. + {"localTaskId": $ltid}')
    fi

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

# Returns 0 when active work exists, 1 when all runs are terminal.
has_active_work() {
  local backup_data archival_data backup_count archival_count
  backup_data=$(pg_active_backup_runs)
  archival_data=$(pg_active_archival_runs)

  backup_count=$(echo "$backup_data" | jq '
    [ (.runs // [])[] | select(.status != null and .status != "") ] | length' \
    2>/dev/null) || backup_count=0
  [[ "${backup_count}" =~ ^[0-9]+$ ]] || backup_count=0

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
# pg_delete — delete the PG via CLI, treating "not found" as success.
# ---------------------------------------------------------------------------
pg_delete() {
  echo "Deleting protection group ${API_PG_ID}..." >&2
  local delete_out
  delete_out=$(ibmcloud backup-recovery protection-group delete \
    --id "${API_PG_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --delete-snapshots=true \
    --force \
    -q 2>&1) || {
    # CLI exits non-zero for 404 — treat as already gone.
    if echo "${delete_out}" | grep -qi "not found\|404\|does not exist"; then
      echo "Protection group already gone." >&2
      return 0
    fi
    echo "Delete failed: ${delete_out}" >&2
    return 1
  }
  vlog "protection-group delete" "${delete_out}"
  echo "Protection group ${API_PG_ID} deleted." >&2
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  ibmcloud_login

  echo "Pausing protection group ${API_PG_ID} to block new runs..." >&2
  pg_pause || {
    echo "PG not found — nothing to delete." >&2
    exit 0
  }

  # Wait briefly so any run BRS had already internally queued (but not yet
  # visible via /runs) has time to surface before we check.
  echo "Waiting 30s for in-flight run state to surface..." >&2
  sleep 30

  local active_count
  active_count=$(check_and_cancel)

  if [[ "$active_count" -eq 0 ]]; then
    # Settle guard: BRS may queue a run between pause and our first check.
    echo "No active runs found — waiting 2m for any late-arriving runs..." >&2
    sleep 120
    if has_active_work; then
      echo "Newly-arrived run(s) detected after settle wait — entering cancel loop." >&2
    else
      echo "Still no active runs after settle. Protection group is ready for deletion." >&2
      pg_delete
      echo "Cleanup complete." >&2
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
    echo "Re-checking run states..." >&2
    if ! has_active_work; then
      echo "All runs stopped. Sleeping 60s for BRS backend state propagation..." >&2
      sleep 60
      echo "Protection group is ready for deletion." >&2
      break
    fi
    # Re-issue cancel each iteration: a run may have transitioned from a
    # non-cancellable phase (e.g. initialising) into a cancellable one, or
    # the previous cancel may have been silently dropped by BRS.
    check_and_cancel > /dev/null
  done

  if has_active_work; then
    echo "WARNING: Timed out (20 min) waiting for run cancellation. Proceeding anyway." >&2
  fi

  pg_delete
  echo "Cleanup complete." >&2
}

main
