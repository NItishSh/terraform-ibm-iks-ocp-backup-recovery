#!/bin/bash
# wait-for-deregistration.sh
#
# Poll registrations-list until the given registration ID disappears,
# confirming BRS has fully completed the async deregistration cleanup.
# Replaces the old blind time_sleep.brs_source_deregistration_wait (20m).
#
# Deregistration typically completes in under 2 minutes after source_registration
# destroy; worst-case (active runs, large cluster) may take 5-10 minutes.
# Hard timeout default is 30 minutes to match the old upper bound.
#
# Uses ibmcloud backup-recovery CLI — same pattern as delete_auto_protect_pg.sh.
#
# Usage:
#   $0 REGION TENANT REGISTRATION_ID BRS_ENDPOINT [TIMEOUT_S] [POLL_S]
#
#   REGION           — IBM Cloud region (e.g. us-south)
#   TENANT           — X-IBM-Tenant-Id (e.g. watmhpj18k/)
#   REGISTRATION_ID  — numeric source_id from ibm_backup_recovery_source_registration
#   BRS_ENDPOINT     — BRS hostname without scheme/path
#                      e.g. <guid>.<region>.backup-recovery.cloud.ibm.com
#   TIMEOUT_S        — total polling budget in seconds (default: 1800)
#   POLL_S           — sleep between polls in seconds   (default: 20)
#
# Required env var:
#   IBMCLOUD_API_KEY — IBM Cloud API key for the destination account (BRS)

set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 REGION TENANT REGISTRATION_ID BRS_ENDPOINT [TIMEOUT_S] [POLL_S]" >&2
  exit 1
fi

# If REGISTRATION_ID is empty the source was never created (e.g. plan-time
# failure before registration); nothing to wait for.
if [ -z "${4:-}" ] || [ -z "${3:-}" ]; then
  echo "wait-for-deregistration.sh: empty args — skipping (resource may not have been created)." >&2
  exit 0
fi

if [ -z "${IBMCLOUD_API_KEY:-}" ]; then # pragma: allowlist secret
  echo "ERROR: IBMCLOUD_API_KEY environment variable is not set" >&2
  exit 1
fi

REGION=$1
TENANT=$2
REGISTRATION_ID=$3
BRS_ENDPOINT=$4
TIMEOUT_S="${5:-1800}"
POLL_S="${6:-20}"

echo "=== wait-for-deregistration.sh invoked at $(date) ===" >&2
echo "region=${REGION}  tenant=${TENANT}  registration_id=${REGISTRATION_ID}" >&2
echo "timeout=${TIMEOUT_S}s  poll=${POLL_S}s" >&2

# ---------------------------------------------------------------------------
# Login + set BRS service URL (same pattern as delete_auto_protect_pg.sh)
# ---------------------------------------------------------------------------
echo "Logging in to IBM Cloud (region: ${REGION})..." >&2
ibmcloud login --apikey "${IBMCLOUD_API_KEY}" -r "${REGION}" -q 2>&1 \
  | grep -v "^$" >&2 || true  # pragma: allowlist secret

brs_url="https://${BRS_ENDPOINT}/v2"
echo "Setting BRS service URL: ${brs_url}" >&2
ibmcloud backup-recovery config set service-url "${brs_url}" 2>&1 \
  | grep -v "^$" >&2 || true

# ---------------------------------------------------------------------------
# Polling loop — exit as soon as the registration disappears
# ---------------------------------------------------------------------------
elapsed=0
while (( elapsed < TIMEOUT_S )); do

  raw=$(ibmcloud backup-recovery protection-source registrations-list \
    --xibm-tenant-id "${TENANT}" \
    --ids "${REGISTRATION_ID}" \
    --output json -q 2>&1) || {
      echo "[${elapsed}s] registrations-list failed — retrying in ${POLL_S}s" >&2
      sleep "${POLL_S}"
      (( elapsed += POLL_S )) || true
      continue
    }

  count=$(echo "${raw}" | jq '.registrations | length' 2>/dev/null || echo "1")

  echo "[${elapsed}s] registrations remaining for id=${REGISTRATION_ID}: ${count}" >&2

  if [[ "${count}" == "0" ]]; then
    echo "=== wait-for-deregistration.sh: registration ${REGISTRATION_ID} confirmed gone (elapsed=${elapsed}s) ===" >&2
    exit 0
  fi

  sleep "${POLL_S}"
  (( elapsed += POLL_S )) || true
done

echo "WARNING: timeout after ${TIMEOUT_S}s — registration ${REGISTRATION_ID} still present." >&2
echo "The brs-backup-agent namespace may not be cleaned up automatically." >&2
# Exit 0 — non-fatal: Terraform destroy should proceed; a lingering registration
# record does not block resource deletion and will eventually be cleaned by BRS.
exit 0
