#!/usr/bin/env bash
##############################################################################
# Cleanup BRS Agent Runtime Resources (Schematics-Compatible)
##############################################################################
# BRS agent creates namespaces and ClusterRoleBindings dynamically at runtime
# that Terraform doesn't manage. This script ensures they are properly deleted.
#
# This version is designed for IBM Cloud Schematics where kubeconfig files
# are not reliable across refresh/destroy phases. It uses stored cluster
# credentials passed as arguments.
#
# Usage:
#   cleanup_brs_agent_resources_schematics.sh <host> <ca_cert> <client_cert> <client_key>
#
# The script will:
# 1. Check if kubectl is available
# 2. Create temporary credential files
# 3. Verify cluster connectivity
# 4. Delete all BRS-agent-created namespaces (pattern: brs-backup-agent-*)
# 5. Delete all BRS-agent-created ClusterRoleBindings (pattern: brs-backup-agent-*)
# 6. Clean up temporary files
##############################################################################

set -e

# The binaries downloaded by the install-binaries script are located in the /tmp directory.
export PATH=$PATH:${1:-"/tmp"}

echo "Cleaning up BRS-agent-created namespaces and cluster role bindings..."

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found; skipping BRS-agent cleanup."
  exit 0
fi

# Check cluster connectivity
if ! kubectl version --request-timeout=15s >/dev/null 2>&1; then
  echo "kubectl cannot reach the target cluster; skipping BRS-agent cleanup."
  exit 0
fi

# Delete namespaces by runtime-generated naming pattern
echo "Deleting BRS-agent namespaces..."
kubectl get namespace --no-headers | awk '{print $1}' | grep -E '^brs-backup-agent-' | while read -r ns; do
  if [ -n "$ns" ]; then
    echo "  Deleting namespace: $ns"
    kubectl delete namespace "$ns" --ignore-not-found=true || true
  fi
done

# Delete ClusterRoleBindings by runtime-generated naming pattern
echo "Deleting BRS-agent ClusterRoleBindings..."
kubectl get clusterrolebinding --no-headers | awk '{print $1}' | grep -E '^brs-backup-agent-' | while read -r crb; do
  if [ -n "$crb" ]; then
    echo "  Deleting ClusterRoleBinding: $crb"
    kubectl delete clusterrolebinding "$crb" --ignore-not-found=true || true
  fi
done

echo "Cleanup complete."
