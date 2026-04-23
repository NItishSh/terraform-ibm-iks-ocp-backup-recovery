#!/bin/bash

set -e

# Script to wait for BRS source registration to refresh and discover namespaces
# This replaces the time_sleep resource with active polling of the BRS API

TENANT_ID="$1"
INSTANCE_GUID="$2"
REGION="$3"
ENDPOINT_TYPE="$4"
MAX_ATTEMPTS="${5:-20}"  # Default 20 attempts = ~10 minutes with 30s sleep
# The binaries downloaded by the install-binaries script are located in the /tmp directory.
export PATH=$PATH:${6:-"/tmp"}
SLEEP_DURATION=30

if [ -z "$TENANT_ID" ] || [ -z "$INSTANCE_GUID" ] || [ -z "$REGION" ]; then
    echo "Error: TENANT_ID, INSTANCE_GUID, and REGION are required"
    echo "Usage: $0 <tenant_id> <instance_guid> <region> <endpoint_type> [max_attempts]"
    exit 1
fi

# Set default endpoint type if not provided
ENDPOINT_TYPE="${ENDPOINT_TYPE:-public}"

echo "Waiting for BRS source registration to refresh and discover namespaces..."
echo "Tenant ID: $TENANT_ID"
echo "Instance GUID: $INSTANCE_GUID"
echo "Region: $REGION"
echo "Endpoint Type: $ENDPOINT_TYPE"
echo "Max attempts: $MAX_ATTEMPTS (checking every ${SLEEP_DURATION}s)"

COUNTER=0

while [[ $COUNTER -lt $MAX_ATTEMPTS ]]; do
    COUNTER=$((COUNTER + 1))

    echo "Attempt $COUNTER/$MAX_ATTEMPTS: Checking for discovered protection sources..."

    # Use ibmcloud CLI to get protection sources
    # The command will return sources if the refresh has completed
    SOURCES_OUTPUT=$(ibmcloud brs protection-sources \
        --x-ibm-tenant-id "$TENANT_ID" \
        --instance-id "$INSTANCE_GUID" \
        --region "$REGION" \
        --endpoint-type "$ENDPOINT_TYPE" \
        --environment kKubernetes \
        --output json 2>/dev/null || echo "[]")

    # Check if we got any protection sources
    SOURCE_COUNT=$(echo "$SOURCES_OUTPUT" | jq '. | length' 2>/dev/null || echo "0")

    if [ "$SOURCE_COUNT" -gt 0 ]; then
        echo "✓ Source refresh complete - discovered $SOURCE_COUNT protection source(s)"

        # Additional check: verify that sources have nodes (namespaces discovered)
        NODES_COUNT=$(echo "$SOURCES_OUTPUT" | jq '[.[] | select(.nodes != null) | .nodes | length] | add // 0' 2>/dev/null || echo "0")

        if [ "$NODES_COUNT" -gt 0 ]; then
            echo "✓ Namespaces discovered: $NODES_COUNT namespace(s) found"
            exit 0
        else
            echo "⏳ Protection sources found but no namespaces discovered yet"
        fi
    else
        echo "⏳ No protection sources discovered yet, waiting for source refresh..."
    fi

    if [[ $COUNTER -lt $MAX_ATTEMPTS ]]; then
        echo "Waiting ${SLEEP_DURATION}s before next check..."
        sleep $SLEEP_DURATION
    fi
done

echo "✗ Error: Source refresh did not complete within $((MAX_ATTEMPTS * SLEEP_DURATION / 60)) minutes"
echo "This may indicate an issue with the source registration or data source connector"
exit 1
