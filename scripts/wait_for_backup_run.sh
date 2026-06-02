#!/bin/bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common_utils.sh
source "${SCRIPT_DIR}/common_utils.sh"

# Log script invocation
echo "=== wait_for_backup_run.sh invoked at $(date) ===" >&2
echo "Arguments: $#" >&2

if [ "$#" -lt 5 ]; then
  echo "ERROR: Insufficient arguments (got $#, need at least 5)" >&2
  echo "Usage: $0 URL TENANT ENDPOINT_TYPE INSTANCE_ID PROTECTION_GROUP_ID [TIMEOUT_MINUTES] [POLL_INTERVAL_SECONDS] [BINARIES_PATH]" >&2
  echo "Note: IBMCLOUD_API_KEY must be set as an environment variable" >&2
  exit 1
fi

if [ -z "${IBMCLOUD_API_KEY:-}" ]; then  # pragma: allowlist secret
  echo "ERROR: IBMCLOUD_API_KEY environment variable is not set" >&2
  exit 1
fi

URL=$1
TENANT=$2
ENDPOINT_TYPE=$3
# shellcheck disable=SC2034  # Used in API URL construction
INSTANCE_ID=$4
PROTECTION_GROUP_ID=$5
API_KEY="${IBMCLOUD_API_KEY}"
TIMEOUT_MINUTES=${6:-45}
POLL_INTERVAL_SECONDS=${7:-30}
BINARIES_PATH=${8:-/tmp}

export PATH="${PATH}:${BINARIES_PATH}"

call_api() {
  local method=$1
  local path=$2
  shift 2

  local response
  response=$(curl --retry 3 -s -w "\n%{http_code}" -X "$method" "${URL}${path}" \
    -H "Authorization: Bearer ${IAM_TOKEN}" \
    -H "X-IBM-Tenant-Id: ${TENANT}" \
    -H "Accept: application/json" \
    -H "Content-Type: application/json" \
    "$@")

  local http_code
  http_code=$(echo "$response" | tail -n1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -eq 404 ]]; then
    echo "__HTTP_404__"
    return 0
  fi

  if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
    echo "API Error: Received HTTP $http_code from $path" >&2
    echo "Response Body: $body" >&2
    exit 1
  fi

  echo "$body"
}

latest_snapshot_id() {
  local body=$1
  # Find the first successful (Succeeded status) snapshot ID
  # Only return snapshots from completed backups, not running ones
  echo "$body" | jq -r '
    [
      .runs[]? |
      (
        # Object-level archival snapshots (most common for Kubernetes) - only if Succeeded
        (.objects[]?.archivalInfo?.archivalTargetResults[]? | select(.status == "Succeeded") | .snapshotId),

        # Object-level local snapshots - only if Succeeded
        (.objects[]?.localSnapshotInfo? | select(.snapshotInfo?.status == "Succeeded") | .snapshotInfo?.snapshotId),

        # Object-level replication snapshots - only if Succeeded
        (.objects[]?.replicationInfo?.replicationTargetResults[]? | select(.status == "Succeeded") | .snapshotId),

        # Run-level archival info - only if Succeeded
        (.archivalInfo?.archivalTargetResults[]? | select(.status == "Succeeded") | .snapshotId),

        # Run-level replication info - only if Succeeded
        (.replicationInfo?.replicationTargetResults[]? | select(.status == "Succeeded") | .snapshotId),

        # Direct snapshot locations (for local backups)
        .localBackupInfo?.snapshotInfo?.snapshotId,

        # Nested in run instances
        (.localBackupInfo?.runInstances[]? | (
          .snapshotInfo?.snapshotId,
          (.archivalInfo?.archivalTargetResults[]? | select(.status == "Succeeded") | .snapshotId),
          (.replicationInfo?.replicationTargetResults[]? | select(.status == "Succeeded") | .snapshotId)
        ))
      )
    ] | map(select(. != null and . != "")) | .[0] // empty
  '
}

latest_run_id() {
  local body=$1
  echo "$body" | jq -r '.runs[0].id // empty'
}

main() {
  local debug_file="/tmp/backup_poll_debug_${PROTECTION_GROUP_ID##*:}.log"

  # Create debug file immediately and make it writable (owner only for security)
  touch "$debug_file" 2>/dev/null || debug_file="/tmp/backup_poll_debug_$$.log"
  chmod 600 "$debug_file" 2>/dev/null || true

  echo "=== Script started at $(date) ===" | tee -a "$debug_file" >&2
  echo "Protection Group ID (full): ${PROTECTION_GROUP_ID}" | tee -a "$debug_file" >&2

  # Extract the numeric ID part after ::
  # Format: clusterid/::8009179080677672:1753125047518:126734
  # API expects: 8009179080677672:1753125047518:126734 (pattern: ^\d+:\d+:\d+$)
  local api_pg_id="${PROTECTION_GROUP_ID#*::}"
  echo "Protection Group ID (for API): ${api_pg_id}" | tee -a "$debug_file" >&2

  echo "Timeout: ${TIMEOUT_MINUTES} minutes" | tee -a "$debug_file" >&2
  echo "Debug log: ${debug_file}" | tee -a "$debug_file" >&2

  echo "Getting IAM token..." | tee -a "$debug_file" >&2
  IAM_TOKEN=$(get_iam_token "${API_KEY}" "${ENDPOINT_TYPE}")
  export IAM_TOKEN
  local token_obtained_at
  token_obtained_at=$(date +%s)
  local token_refresh_threshold=3300  # Refresh before 60-minute expiry
  echo "IAM token obtained" | tee -a "$debug_file" >&2

  local deadline
  deadline=$(( $(date +%s) + TIMEOUT_MINUTES * 60 ))
  echo "Deadline: $(date -r $deadline)" | tee -a "$debug_file" >&2
  echo "Entering polling loop..." | tee -a "$debug_file" >&2

  while [ "$(date +%s)" -lt "$deadline" ]; do
    local now
    now=$(date +%s)
    if (( now - token_obtained_at >= token_refresh_threshold )); then
      echo "Refreshing IAM token..." | tee -a "$debug_file" >&2
      unset IAM_TOKEN  # force API key exchange in get_iam_token, not cached env var
      IAM_TOKEN=$(get_iam_token "${API_KEY}" "${ENDPOINT_TYPE}")
      export IAM_TOKEN
      token_obtained_at=$(date +%s)
      echo "IAM token refreshed" | tee -a "$debug_file" >&2
    fi
    echo "=== Polling at $(date) ===" | tee -a "$debug_file" >&2
    echo "Calling API: GET /v2/data-protect/protection-groups/${api_pg_id}/runs?includeObjectDetails=true" | tee -a "$debug_file" >&2

    local run_response
    run_response=$(call_api "GET" "/v2/data-protect/protection-groups/${api_pg_id}/runs?includeObjectDetails=true")

    echo "API call completed, response length: ${#run_response} chars" | tee -a "$debug_file" >&2

    if [[ "$run_response" != "__HTTP_404__" ]]; then
      # Debug: Write full response to file
      echo "=== Poll at $(date) ===" | tee -a "$debug_file" >&2
      echo "$run_response" | jq '.' >> "$debug_file" 2>&1

      local snapshot_id
      snapshot_id=$(latest_snapshot_id "$run_response")

      echo "Found snapshot_id: ${snapshot_id:-<empty>}" | tee -a "$debug_file" >&2
      echo "Snapshot ID found: ${snapshot_id:-<none>}" | tee -a "$debug_file" >&2

      if [[ -n "$snapshot_id" ]]; then
        echo "✓ Backup snapshot ready: ${snapshot_id}" | tee -a "$debug_file" >&2
        local run_id
        run_id=$(latest_run_id "$run_response")
        jq -n \
          --arg snapshot_id "$snapshot_id" \
          --arg run_id "$run_id" \
          --arg protection_group_id "$PROTECTION_GROUP_ID" \
          '{snapshot_id: $snapshot_id, run_id: $run_id, protection_group_id: $protection_group_id}'
        exit 0
      else
        echo "No snapshot found yet, waiting ${POLL_INTERVAL_SECONDS}s..." | tee -a "$debug_file" >&2
      fi
    else
      echo "Protection group not found (404), waiting ${POLL_INTERVAL_SECONDS}s..." | tee -a "$debug_file" >&2
    fi

    sleep "$POLL_INTERVAL_SECONDS"
  done

  echo "Timed out waiting for a restorable backup run for protection group ${PROTECTION_GROUP_ID} after ${TIMEOUT_MINUTES} minutes." >&2
  exit 1
}

main
