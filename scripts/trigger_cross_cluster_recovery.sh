#!/bin/bash
set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/common_utils.sh
source "${SCRIPT_DIR}/common_utils.sh"

if [ "$#" -lt 8 ]; then
  echo "Usage: $0 URL TENANT ENDPOINT_TYPE INSTANCE_ID SOURCE_PG_ID TARGET_SOURCE_ID SNAPSHOT_ID RECOVERY_NAME [NAMESPACE_PREFIX] [BINARIES_PATH]" >&2
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
SOURCE_PG_ID=$5
TARGET_SOURCE_ID=$6
SNAPSHOT_ID=$7
RECOVERY_NAME=$8
NAMESPACE_PREFIX=${9:-restored-}
BINARIES_PATH=${10:-/tmp}

export PATH="${PATH}:${BINARIES_PATH}"

echo "=== Cross-Cluster Recovery ===" >&2
echo "Source PG ID: ${SOURCE_PG_ID}" >&2
echo "Target Source ID: ${TARGET_SOURCE_ID}" >&2
echo "Snapshot ID: ${SNAPSHOT_ID}" >&2

IAM_TOKEN=$(get_iam_token "${IBMCLOUD_API_KEY}" "${ENDPOINT_TYPE}")

# Create recovery request with correct structure based on UI-generated recovery
# The key is: kubernetesParams.recoverNamespaceParams.kubernetesTargetParams.recoveryTargetConfig
RECOVERY_PAYLOAD=$(cat <<PAYLOAD
{
  "name": "${RECOVERY_NAME}",
  "snapshotEnvironment": "kKubernetes",
  "kubernetesParams": {
    "recoveryAction": "RecoverNamespaces",
    "objects": [{
      "snapshotId": "${SNAPSHOT_ID}",
      "protectionGroupId": "${SOURCE_PG_ID}"
    }],
    "recoverNamespaceParams": {
      "targetEnvironment": "kKubernetes",
      "kubernetesTargetParams": {
        "objects": [{
          "snapshotId": "${SNAPSHOT_ID}",
          "protectionGroupId": "${SOURCE_PG_ID}"
        }],
        "recoveryTargetConfig": {
          "recoverToNewSource": true,
          "newSourceConfig": {
            "source": {
              "id": ${TARGET_SOURCE_ID}
            }
          }
        },
        "renameRecoveredNamespacesParams": {
          "prefix": "${NAMESPACE_PREFIX}"
        }
      }
    }
  }
}
PAYLOAD
)

echo "Triggering recovery to target cluster..." >&2

response=$(curl --retry 3 -s -w "\n%{http_code}" -X POST "${URL}/v2/data-protect/recoveries" \
  -H "Authorization: Bearer ${IAM_TOKEN}" \
  -H "X-IBM-Tenant-Id: ${TENANT}" \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d "${RECOVERY_PAYLOAD}")

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
  echo "Recovery API Error: HTTP $http_code" >&2
  echo "Response: $body" >&2
  exit 1
fi

echo "✓ Recovery triggered successfully!" >&2
echo "$body" | jq '.'
