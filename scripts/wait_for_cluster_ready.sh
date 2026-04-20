#!/bin/bash

set -e

# Script to wait for IBM Cloud cluster to be ready before downloading config
# This replaces the time_sleep resource with active polling

CLUSTER_ID="$1"
RESOURCE_GROUP_ID="$2"
MAX_ATTEMPTS="${3:-40}"  # Default 40 attempts = ~20 minutes with 30s sleep
SLEEP_DURATION=30

if [ -z "$CLUSTER_ID" ] || [ -z "$RESOURCE_GROUP_ID" ]; then
    echo "Error: CLUSTER_ID and RESOURCE_GROUP_ID are required"
    echo "Usage: $0 <cluster_id> <resource_group_id> [max_attempts]"
    exit 1
fi

echo "Waiting for cluster $CLUSTER_ID to be ready..."
echo "Resource Group: $RESOURCE_GROUP_ID"
echo "Max attempts: $MAX_ATTEMPTS (checking every ${SLEEP_DURATION}s)"

COUNTER=0

while [[ $COUNTER -lt $MAX_ATTEMPTS ]]; do
    COUNTER=$((COUNTER + 1))

    echo "Attempt $COUNTER/$MAX_ATTEMPTS: Checking cluster state..."

    # Get cluster state using ibmcloud CLI
    CLUSTER_STATE=$(ibmcloud ks cluster get --cluster "$CLUSTER_ID" --output json 2>/dev/null | jq -r '.state // "unknown"')

    if [ "$CLUSTER_STATE" = "normal" ]; then
        echo "✓ Cluster is ready (state: $CLUSTER_STATE)"
        exit 0
    elif [ "$CLUSTER_STATE" = "unknown" ] || [ -z "$CLUSTER_STATE" ]; then
        echo "⚠ Unable to retrieve cluster state, retrying..."
    else
        echo "⏳ Cluster state: $CLUSTER_STATE (waiting for 'normal')"
    fi

    if [[ $COUNTER -lt $MAX_ATTEMPTS ]]; then
        echo "Waiting ${SLEEP_DURATION}s before next check..."
        sleep $SLEEP_DURATION
    fi
done

echo "✗ Error: Cluster did not become ready within $((MAX_ATTEMPTS * SLEEP_DURATION / 60)) minutes"
echo "Last known state: $CLUSTER_STATE"
exit 1
