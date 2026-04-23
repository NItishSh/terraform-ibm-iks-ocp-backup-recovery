#!/bin/bash

set -e

# Script to wait for BRS-managed namespaces to be cleaned up during destroy
# This replaces the time_sleep resource with active polling of namespace status

DSC_NAMESPACE="${1:-cohesity-dataprotect}"
MAX_ATTEMPTS="${2:-20}"  # Default 20 attempts = ~10 minutes with 30s sleep
# The binaries downloaded by the install-binaries script are located in the /tmp directory.
export PATH=$PATH:${3:-"/tmp"}
SLEEP_DURATION=30

echo "Waiting for BRS-managed namespaces to be cleaned up..."
echo "DSC Namespace: $DSC_NAMESPACE"
echo "Max attempts: $MAX_ATTEMPTS (checking every ${SLEEP_DURATION}s)"

# Create temporary files for credentials
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

CA_FILE="$TEMP_DIR/ca.crt"
CERT_FILE="$TEMP_DIR/client.crt"
KEY_FILE="$TEMP_DIR/client.key"

echo "$KUBE_CA" | base64 -d > "$CA_FILE"
echo "$KUBE_CERT" | base64 -d > "$CERT_FILE"
echo "$KUBE_KEY" | base64 -d > "$KEY_FILE"

COUNTER=0

while [[ $COUNTER -lt $MAX_ATTEMPTS ]]; do
    COUNTER=$((COUNTER + 1))

    echo "Attempt $COUNTER/$MAX_ATTEMPTS: Checking for BRS-managed resources..."

    # Check for velero backup resources in the DSC namespace
    VELERO_BACKUPS=$(kubectl get backups.velero.io \
        --server="$KUBE_HOST" \
        --certificate-authority="$CA_FILE" \
        --client-certificate="$CERT_FILE" \
        --client-key="$KEY_FILE" \
        -n "$DSC_NAMESPACE" \
        --no-headers 2>/dev/null | wc -l || echo "0")

    # Check for velero restore resources in the DSC namespace
    VELERO_RESTORES=$(kubectl get restores.velero.io \
        --server="$KUBE_HOST" \
        --certificate-authority="$CA_FILE" \
        --client-certificate="$CERT_FILE" \
        --client-key="$KEY_FILE" \
        -n "$DSC_NAMESPACE" \
        --no-headers 2>/dev/null | wc -l || echo "0")

    # Check for any namespaces with BRS labels (protected namespaces)
    PROTECTED_NAMESPACES=$(kubectl get namespaces \
        --server="$KUBE_HOST" \
        --certificate-authority="$CA_FILE" \
        --client-certificate="$CERT_FILE" \
        --client-key="$KEY_FILE" \
        -l cohesity.com/backup-enabled=true \
        --no-headers 2>/dev/null | wc -l || echo "0")

    TOTAL_RESOURCES=$((VELERO_BACKUPS + VELERO_RESTORES + PROTECTED_NAMESPACES))

    if [ "$TOTAL_RESOURCES" -eq 0 ]; then
        echo "✓ All BRS-managed resources cleaned up"
        echo "  - Velero backups: 0"
        echo "  - Velero restores: 0"
        echo "  - Protected namespaces: 0"
        exit 0
    else
        echo "⏳ BRS-managed resources still present:"
        echo "  - Velero backups: $VELERO_BACKUPS"
        echo "  - Velero restores: $VELERO_RESTORES"
        echo "  - Protected namespaces: $PROTECTED_NAMESPACES"
    fi

    if [[ $COUNTER -lt $MAX_ATTEMPTS ]]; then
        echo "Waiting ${SLEEP_DURATION}s before next check..."
        sleep $SLEEP_DURATION
    fi
done

echo "⚠ Warning: BRS-managed resources still present after $((MAX_ATTEMPTS * SLEEP_DURATION / 60)) minutes"
echo "Proceeding with destroy anyway to avoid blocking terraform destroy"
echo "Manual cleanup may be required for:"
echo "  - Velero backups: $VELERO_BACKUPS"
echo "  - Velero restores: $VELERO_RESTORES"
echo "  - Protected namespaces: $PROTECTED_NAMESPACES"
exit 0  # Exit with success to allow destroy to proceed
