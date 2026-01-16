#!/bin/bash
set -euo pipefail

# --- Configuration & Validation ---
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 URL TENANT ENDPOINT_TYPE [PROTECTION_GROUP_ID] [REGISTRATION_ID]"
    exit 1
fi

URL=$1
TENANT=$2
ENDPOINT_TYPE=$3
PROTECTION_GROUP_ID=${4:-}
REGISTRATION_ID=${5:-}

# --- Internal Functions ---

call_api() {
    local method=$1
    local path=$2
    shift 2
    local response
    response=$(curl --retry 3 -s -w "\n%{http_code}" -X "$method" "${URL}${path}" \
        -H "Authorization: Bearer ${iam_token}" \
        -H "X-IBM-Tenant-Id: ${TENANT}" \
        -H "Accept: application/json" \
        -H "Content-Type: application/json" \
        "$@")

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
        echo "API Error: Received HTTP $http_code from $path" >&2
        echo "Response Body: $body" >&2
        exit 1
    fi
    echo "$body"
}

get_iam_token() {
    local iam_endpoint="${IBMCLOUD_IAM_API_ENDPOINT:-"iam.cloud.ibm.com"}"
    iam_endpoint=${iam_endpoint#https://}

    if [[ "$iam_endpoint" == "iam.cloud.ibm.com" && "$ENDPOINT_TYPE" == "private" ]]; then
        iam_endpoint="private.${iam_endpoint}"
    fi

    local response
    # Added pragma to satisfy secret scanners
    response=$(curl --retry 3 -s -X POST "https://${iam_endpoint}/identity/token" --header 'Content-Type: application/x-www-form-urlencoded' --header 'Accept: application/json' --data-urlencode 'grant_type=urn:ibm:params:oauth:grant-type:apikey' --data-urlencode "apikey=$API_KEY") # pragma: allowlist secret

    if echo "$response" | jq -e 'has("errorMessage")' > /dev/null; then
        echo "IAM Error: $(echo "$response" | jq -r '.errorMessage')" >&2
        exit 1
    fi
    echo "$response" | jq -r '.access_token'
}

pause_protection_group() {
    local pg_id=$1
    echo "Fetching details for PG: $pg_id"

    local response body http_code
    response=$(curl --retry 3 -s -w "\n%{http_code}" -X "GET" "${URL}/v2/data-protect/protection-groups/${pg_id}" \
        -H "Authorization: Bearer ${iam_token}" \
        -H "X-IBM-Tenant-Id: ${TENANT}" \
        -H "Accept: application/json")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [ "$http_code" -eq 404 ]; then
        echo "Protection Group $pg_id already gone. Skipping."
        return 1
    elif [ "$http_code" -lt 200 ] || [ "$http_code" -ge 300 ]; then
        echo "Error fetching PG: $body" >&2
        exit 1
    fi

    local name policy obj_id obj_name
    name=$(echo "$body" | jq -r '.name')
    policy=$(echo "$body" | jq -r '.policyId')
    obj_id=$(echo "$body" | jq -r '.kubernetesParams.objects[0].id')
    obj_name=$(echo "$body" | jq -r '.kubernetesParams.objects[0].name')

    echo "Pausing protection group: $name..."
    call_api "PUT" "/v2/data-protect/protection-groups/${pg_id}" --data-raw "{
        \"name\": \"$name\",
        \"policyId\": \"$policy\",
        \"environment\": \"kKubernetes\",
        \"kubernetesParams\": { \"objects\": [ { \"id\": $obj_id, \"name\": \"$obj_name\" } ] },
        \"isPaused\": true
    }" > /dev/null
}

cancel_and_wait_jobs() {
    local pg_id=$1
    local run_data run_id task_id

    run_data=$(call_api "GET" "/v2/data-protect/protection-groups/${pg_id}/runs" -d 'excludeNonRestorableRuns=false')
    run_id=$(echo "$run_data" | jq -r '.runs[0].id // empty')
    task_id=$(echo "$run_data" | jq -r '.runs[0].archivalInfo.archivalTargetResults[0].archivalTaskId // empty')

    if [[ -z "$run_id" || "$run_id" == "null" ]]; then
        echo "No active runs found to cancel."
        return
    fi

    echo "Canceling job $run_id..."
    call_api "POST" "/v2/data-protect/protection-groups/${pg_id}/runs/actions" --data-raw "{
        \"action\": \"Cancel\",
        \"cancelParams\": [ { \"runId\": \"$run_id\", \"localTaskId\": \"$task_id\" } ]
    }" > /dev/null

    while true; do
        local status
        status=$(call_api "GET" "/v2/data-protect/protection-groups/${pg_id}/runs" -d 'excludeNonRestorableRuns=false' | \
                 jq -r '.runs[0].archivalInfo.archivalTargetResults[0].status')

        echo "Job status: $status"
        [[ "$status" == "Canceled" || "$status" == "Succeeded" || "$status" == "Failed" ]] && break
        sleep 10
    done
}

expire_snapshots() {
    local reg_id=$1
    local raw ids

    echo "Fetching snapshots for Registration: $reg_id"
    raw=$(call_api "GET" "/v2/data-protect/objects/${reg_id}/snapshots")
    ids=$(echo "$raw" | jq -r '.snapshots[]?.id // empty')

    for snap_id in $ids; do
        echo -n "Expiring snapshot $snap_id... "
        call_api "PUT" "/v2/data-protect/objects/${reg_id}/snapshots/${snap_id}" --data-raw '{
            "setLegalHold": false,
            "dataLockType": "Compliance",
            "expiryTimeSecs": 0
        }' -o /dev/null -w "Status: %{http_code}\n"
    done
}

delete_protection_group() {
    local pg_id=$1
    echo "Deleting protection group: $pg_id"

    local http_code
    http_code=$(call_api "DELETE" "/v2/data-protect/protection-groups/${pg_id}?deleteSnapshots=true" -o /dev/null -w "%{http_code}")

    echo "API returned status: $http_code"

    # 200-299: Success
    # 404: Already deleted (Target state reached)
    if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]] || [[ "$http_code" -eq 404 ]]; then
        echo "Delete successful or already removed."
    else
        echo "Delete failed with status: $http_code" >&2
        # Optional: Don't exit 1 if the UI shows it's gone anyway
        # exit 1
    fi
}

# --- Main Execution ---

# 1. Obtain Token (Secret scanning pragma applied inside function)
iam_token=$(get_iam_token)

# 2. Handle Protection Group Pause/Cancel
PG_EXISTS=true
if [[ -n "$PROTECTION_GROUP_ID" ]]; then
    pause_protection_group "$PROTECTION_GROUP_ID" || PG_EXISTS=false

    if [ "$PG_EXISTS" = true ]; then
        cancel_and_wait_jobs "$PROTECTION_GROUP_ID"
    else
        echo "Skipping job cancellation because PG does not exist."
    fi
fi

if [[ -n "$REGISTRATION_ID" ]]; then
    expire_snapshots "$REGISTRATION_ID" || echo "Registration not found, skipping snapshots."
fi

if [[ -n "$PROTECTION_GROUP_ID" && "$PG_EXISTS" = true ]]; then
    delete_protection_group "$PROTECTION_GROUP_ID"
else
    echo "Skipping final deletion because PG does not exist."
fi

echo "Cleanup complete."
