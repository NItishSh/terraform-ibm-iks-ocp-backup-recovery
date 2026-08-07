#!/bin/bash
# wait-for-source-discovery.sh
#
# Poll the BRS registration-get API until the initial source refresh has
# completed — i.e., until lastRefreshedTimeMsecs is substantially greater
# than registrationTimeMsecs (indicating Velero has completed at least one
# full namespace discovery pass and sent the results to BRS).
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
#   POLL_S           — sleep between polls in seconds   (default: 30)
#
# Required env var:
#   IBMCLOUD_API_KEY — IBM Cloud API key for the destination account (BRS)

set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $0 REGION TENANT REGISTRATION_ID BRS_ENDPOINT [TIMEOUT_S] [POLL_S]" >&2
  exit 1
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
POLL_S="${6:-30}"

# Minimum refresh lag (ms) to consider initial discovery complete.
# The registration sets lastRefreshedTimeMsecs only a few seconds after
# registrationTimeMsecs on first contact.  A full Velero discovery pass
# typically takes 1–5 minutes; we require at least 60 s of lag to avoid
# treating that initial superficial refresh as "done".
MIN_REFRESH_LAG_MS=60000

echo "=== wait-for-source-discovery.sh invoked at $(date) ===" >&2
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
# Polling loop
# ---------------------------------------------------------------------------
elapsed=0
while (( elapsed < TIMEOUT_S )); do

  raw=$(ibmcloud backup-recovery protection-source registration-get \
    --id "${REGISTRATION_ID}" \
    --xibm-tenant-id "${TENANT}" \
    --output json -q 2>&1) || {
      echo "[${elapsed}s] registration-get failed — retrying in ${POLL_S}s" >&2
      sleep "${POLL_S}"
      (( elapsed += POLL_S )) || true
      continue
    }

  # The CLI returns timestamps as floating-point (e.g. 1.786125694124e+12).
  # Use jq to convert both to integers before comparing so bash arithmetic
  # doesn't choke on scientific notation.
  auth=$(echo "${raw}" | jq -r '.authenticationStatus // ""')
  lag=$(echo "${raw}" | jq '
    (.lastRefreshedTimeMsecs // 0 | floor) -
    (.registrationTimeMsecs  // 0 | floor)
  ')

  echo "[${elapsed}s] authStatus=${auth}  lag=${lag}ms" >&2

  if [[ "${auth}" == "Finished" ]] && (( lag >= MIN_REFRESH_LAG_MS )); then
    echo "=== wait-for-source-discovery.sh: initial source refresh complete (lag=${lag}ms, elapsed=${elapsed}s) ===" >&2
    exit 0
  fi

  if (( lag < MIN_REFRESH_LAG_MS )); then
    echo "[${elapsed}s] refresh lag ${lag}ms < ${MIN_REFRESH_LAG_MS}ms — waiting for initial Velero discovery pass…" >&2
  else
    echo "[${elapsed}s] authStatus not Finished yet (${auth}) — waiting…" >&2
  fi

  sleep "${POLL_S}"
  (( elapsed += POLL_S )) || true
done

echo "ERROR: timeout after ${TIMEOUT_S}s — source ${REGISTRATION_ID} initial refresh did not complete." >&2
echo "Check that the Data Source Connector pod is Running in the ibm-brs-data-source-connector namespace." >&2
exit 1
