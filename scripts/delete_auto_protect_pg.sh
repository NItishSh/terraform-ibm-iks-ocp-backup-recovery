#!/bin/bash
set -euo pipefail

URL=$1
TENANT=$2
ENDPOINT_TYPE=$3
PROTECTION_GROUP_ID=$4

# IAM endpoint handling (unchanged)
iam_cloud_endpoint="${IBMCLOUD_IAM_API_ENDPOINT:-"iam.cloud.ibm.com"}"
IBMCLOUD_IAM_API_ENDPOINT=${iam_cloud_endpoint#https://}

if [[ "$IBMCLOUD_IAM_API_ENDPOINT" == "iam.cloud.ibm.com" ]]; then
  if [[ "$ENDPOINT_TYPE" == "private" ]]; then
    IBMCLOUD_IAM_API_ENDPOINT="private.${IBMCLOUD_IAM_API_ENDPOINT}"
  fi
fi

# Get IAM token (unchanged, with error handling)
iam_response=$(curl --retry 3 -s -X POST "https://${IBMCLOUD_IAM_API_ENDPOINT}/identity/token" --header 'Content-Type: application/x-www-form-urlencoded' --header 'Accept: application/json' --data-urlencode 'grant_type=urn:ibm:params:oauth:grant-type:apikey' --data-urlencode "apikey=$API_KEY") # pragma: allowlist secret

error_message=$(echo "${iam_response}" | jq 'has("errorMessage")')
if [[ "${error_message}" != false ]]; then
  echo "${iam_response}" | jq '.errorMessage' >&2
  echo "Could not obtain an IAM access token" >&2
  exit 1
fi
iam_token=$(echo "${iam_response}" | jq -r '.access_token')


if [[ -n "$PROTECTION_GROUP_ID" ]]; then
  http_code=$(curl --retry 3 -s -o /dev/null -w "%{http_code}" -X DELETE "${URL}/v2/data-protect/protection-groups/${PROTECTION_GROUP_ID}" \
    -H "Authorization: Bearer ${iam_token}" \
    -H "X-IBM-Tenant-Id: ${TENANT}" \
    -d 'deleteSnapshots=true')

  if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
    echo "Successfully deleted protection group ID: ${PROTECTION_GROUP_ID} (Status: $http_code)"
  else
    echo "Failed to delete protection group. Status code: $http_code" >&2
    exit 1
  fi
fi

echo "Cleanup complete."
