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

KUBE_HOST="${1:-}"
KUBE_CA="${2:-}"
KUBE_CERT="${3:-}"
KUBE_KEY="${4:-}"

if [ -z "$KUBE_HOST" ] || [ -z "$KUBE_CERT" ] || [ -z "$KUBE_KEY" ]; then
  echo "Error: Host, client certificate, and client key are required."
  echo "Usage: $0 <host> <ca_cert> <client_cert> <client_key>"
  echo "Note: ca_cert can be empty for clusters that don't require it"
  exit 1
fi

echo "Cleaning up BRS-agent-created namespaces and cluster role bindings..."

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl not found; skipping BRS-agent cleanup."
  exit 0
fi

# Build a temporary directory for credentials
TMPDIR=$(mktemp -d /tmp/brs-cleanup-XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# Only create CA file if CA certificate is provided
if [ -n "$KUBE_CA" ]; then
  printf '%s\n' "$KUBE_CA" > "$TMPDIR/ca.pem"
  CA_ARG="--certificate-authority=$TMPDIR/ca.pem"
else
  # Use insecure-skip-tls-verify if no CA certificate provided
  CA_ARG="--insecure-skip-tls-verify=true"
fi

printf '%s\n' "$KUBE_CERT" > "$TMPDIR/client.crt"
printf '%s\n' "$KUBE_KEY" > "$TMPDIR/client.key"

# Helper function to run kubectl with stored credentials
kctl() {
  kubectl \
    --server="$KUBE_HOST" \
    $CA_ARG \
    --client-certificate="$TMPDIR/client.crt" \
    --client-key="$TMPDIR/client.key" \
    "$@"
}

# Check cluster connectivity
if ! kctl version --request-timeout=15s >/dev/null 2>&1; then
  echo "kubectl cannot reach the target cluster; skipping BRS-agent cleanup."
  exit 0
fi

# Delete namespaces by runtime-generated naming pattern
echo "Deleting BRS-agent namespaces..."
kctl get namespace --no-headers | awk '{print $1}' | grep -E '^brs-backup-agent-' | while read -r ns; do
  if [ -n "$ns" ]; then
    echo "  Deleting namespace: $ns"
    kctl delete namespace "$ns" --ignore-not-found=true || true
  fi
done

# Delete ClusterRoleBindings by runtime-generated naming pattern
echo "Deleting BRS-agent ClusterRoleBindings..."
kctl get clusterrolebinding --no-headers | awk '{print $1}' | grep -E '^brs-backup-agent-' | while read -r crb; do
  if [ -n "$crb" ]; then
    echo "  Deleting ClusterRoleBinding: $crb"
    kctl delete clusterrolebinding "$crb" --ignore-not-found=true || true
  fi
done

echo "Cleanup complete."
