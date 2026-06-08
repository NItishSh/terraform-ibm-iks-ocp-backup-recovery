#!/bin/bash

set -e

# Wait for BRS to clean up runtime resources after source deregistration.
# BRS cleans brs-backup-agent-* namespaces asynchronously via the DSC pod.
# This script polls until they are gone before allowing helm_release to be destroyed.
#
# Usage:
#   wait_for_namespace_cleanup.sh <dsc_namespace> [max_attempts] [binaries_path]
#
# Environment variables:
#   KUBECONFIG - Path to kubeconfig file created by the terraform provider

DSC_NAMESPACE="${1:-ibm-brs-data-source-connector}"
MAX_ATTEMPTS="${2:-20}"
SLEEP_DURATION=30

# The binaries downloaded by install-binaries are placed in binaries_path (default: /tmp)
export PATH=$PATH:${3:-"/tmp"}

echo "Waiting for BRS-managed resources to be cleaned up..."
echo "DSC Namespace: $DSC_NAMESPACE"
echo "Max attempts: $MAX_ATTEMPTS (checking every ${SLEEP_DURATION}s)"

# Verify cluster connectivity using the kubeconfig created by the terraform provider.
if ! kubectl version --request-timeout=15s >/dev/null 2>&1; then
  echo "kubectl cannot reach cluster with stored kubeconfig; skipping namespace wait."
  exit 0
fi

COUNTER=0
while [[ $COUNTER -lt $MAX_ATTEMPTS ]]; do
  COUNTER=$((COUNTER + 1))
  echo "Attempt $COUNTER/$MAX_ATTEMPTS: Checking for BRS-managed resources..."

  VELERO_BACKUPS=$(kubectl get backups.velero.io -n "$DSC_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
  VELERO_RESTORES=$(kubectl get restores.velero.io -n "$DSC_NAMESPACE" --no-headers 2>/dev/null | wc -l || echo "0")
  PROTECTED_NS=$(kubectl get namespaces -l cohesity.com/backup-enabled=true --no-headers 2>/dev/null | wc -l || echo "0")
  BRS_AGENT_NS=$(kubectl get namespaces --no-headers 2>/dev/null | awk '{print $1}' | grep -c '^brs-backup-agent-' || echo "0")

  TOTAL=$((VELERO_BACKUPS + VELERO_RESTORES + PROTECTED_NS + BRS_AGENT_NS))

  if [ "$TOTAL" -eq 0 ]; then
    echo "All BRS-managed resources cleaned up."
    exit 0
  fi

  echo "  BRS-agent namespaces (brs-backup-agent-*): $BRS_AGENT_NS"
  echo "  Velero backups: $VELERO_BACKUPS"
  echo "  Velero restores: $VELERO_RESTORES"
  echo "  Protected namespaces: $PROTECTED_NS"

  if [[ $COUNTER -lt $MAX_ATTEMPTS ]]; then
    echo "Waiting ${SLEEP_DURATION}s before next check..."
    sleep $SLEEP_DURATION
  fi
done

echo "Warning: BRS-managed resources still present after $((MAX_ATTEMPTS * SLEEP_DURATION / 60)) minutes. Proceeding anyway."
exit 0
