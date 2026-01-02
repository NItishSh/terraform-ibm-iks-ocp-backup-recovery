#!/bin/bash
set -euo pipefail

if [ "$#" -lt 3 ]; then
    echo "Usage: $0 URL TENANT ENDPOINT_TYPE [PROTECTION_GROUP_ID] [REGISTRATION_ID]"
    exit 1
fi

URL=$1
TENANT=$2
ENDPOINT_TYPE=$3
PROTECTION_GROUP_ID=${4:-}
REGISTRATION_ID=${5:-}

# --- IAM Token Logic ---
iam_cloud_endpoint="${IBMCLOUD_IAM_API_ENDPOINT:-"iam.cloud.ibm.com"}"
IBMCLOUD_IAM_API_ENDPOINT=${iam_cloud_endpoint#https://}

if [[ "$IBMCLOUD_IAM_API_ENDPOINT" == "iam.cloud.ibm.com" ]]; then
  if [[ "$ENDPOINT_TYPE" == "private" ]]; then
    IBMCLOUD_IAM_API_ENDPOINT="private.${IBMCLOUD_IAM_API_ENDPOINT}"
  fi
fi

iam_response=$(curl --retry 3 -s -X POST "https://${IBMCLOUD_IAM_API_ENDPOINT}/identity/token" --header 'Content-Type: application/x-www-form-urlencoded' --header 'Accept: application/json' --data-urlencode 'grant_type=urn:ibm:params:oauth:grant-type:apikey' --data-urlencode "apikey=$API_KEY") # pragma: allowlist secret

error_message=$(echo "${iam_response}" | jq 'has("errorMessage")')
if [[ "${error_message}" != false ]]; then
  echo "${iam_response}" | jq '.errorMessage' >&2
  echo "Could not obtain an IAM access token" >&2
  exit 1
fi
iam_token=$(echo "${iam_response}" | jq -r '.access_token')

# --- Snapshot Expiry Update ---
if [[ -n "$REGISTRATION_ID" ]]; then
  echo "Fetching snapshots for registration ID: ${REGISTRATION_ID}"

  # Fetch and iterate through snapshot IDs
  snapshots=$(curl --retry 3 -s -X GET "${URL}/v2/data-protect/objects/${REGISTRATION_ID}/snapshots" \
    -H "Authorization: Bearer ${iam_token}" \
    -H "X-IBM-Tenant-Id: ${TENANT}" \
    -H "Accept: application/json")

  echo "$snapshots" | jq -r '.snapshots[]?.id' | while read -r snapshot_id; do
    [[ -z "$snapshot_id" ]] && continue

    echo "Updating snapshot ID: ${snapshot_id} to expire immediately"
    curl --retry 3 -s -o /dev/null -w "%{http_code}" -X PUT "${URL}/v2/data-protect/objects/${REGISTRATION_ID}/snapshots/${snapshot_id}" \
      -H "Authorization: Bearer ${iam_token}" \
      -H "X-IBM-Tenant-Id: ${TENANT}" \
      -H "Content-Type: application/json" \
      -d '{
        "setLegalHold": false,
        "dataLockType": "Compliance",
        "expiryTimeSecs": 0
      }'
    echo " (Updated)"
  done
fi

# --- Protection Group Deletion ---
if [[ -n "$PROTECTION_GROUP_ID" ]]; then
  echo "Deleting protection group ID: ${PROTECTION_GROUP_ID}..."
  http_code=$(curl --retry 3 -s -o /dev/null -w "%{http_code}" -X DELETE "${URL}/v2/data-protect/protection-groups/${PROTECTION_GROUP_ID}?deleteSnapshots=true" \
    -H "Authorization: Bearer ${iam_token}" \
    -H "X-IBM-Tenant-Id: ${TENANT}")

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    echo "Successfully deleted protection group (Status: $http_code)"
  else
    echo "Failed to delete protection group. Status code: $http_code" >&2
    exit 1
  fi
fi

echo "Cleanup complete."
