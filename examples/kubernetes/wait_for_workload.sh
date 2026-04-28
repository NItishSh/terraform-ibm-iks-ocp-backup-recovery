#!/usr/bin/env bash
##############################################################################
# Wait for Workload Deployment to be Ready
##############################################################################
# This script waits for Kubernetes deployments to reach a ready state by
# checking the deployment status rather than using a fixed time delay.
#
# Usage:
#   wait_for_workload.sh <kubeconfig_path> <namespace> <deployment_name> [timeout_seconds]
#
# Arguments:
#   kubeconfig_path  - Path to the kubeconfig file
#   namespace        - Kubernetes namespace where the deployment exists
#   deployment_name  - Name of the deployment to wait for
#   timeout_seconds  - Optional timeout in seconds (default: 300)
#
# Exit codes:
#   0 - Deployment is ready
#   1 - Deployment failed to become ready within timeout
#   2 - Invalid arguments or kubectl not available
##############################################################################

set -e

KUBECONFIG_PATH="${1:-}"
NAMESPACE="${2:-}"
DEPLOYMENT_NAME="${3:-}"
TIMEOUT="${4:-300}"

if [ -z "$KUBECONFIG_PATH" ] || [ -z "$NAMESPACE" ] || [ -z "$DEPLOYMENT_NAME" ]; then
  echo "Error: Missing required arguments."
  echo "Usage: $0 <kubeconfig_path> <namespace> <deployment_name> [timeout_seconds]"
  exit 2
fi

export KUBECONFIG="$KUBECONFIG_PATH"

echo "Waiting for deployment '$DEPLOYMENT_NAME' in namespace '$NAMESPACE' to be ready..."

# Check if kubectl is available
if ! command -v kubectl >/dev/null 2>&1; then
  echo "Error: kubectl not found."
  exit 2
fi

# Check cluster connectivity
if ! kubectl version --request-timeout=15s >/dev/null 2>&1; then
  echo "Error: kubectl cannot reach the target cluster."
  exit 2
fi

# Wait for the deployment to be ready
if kubectl wait --for=condition=available \
  --timeout="${TIMEOUT}s" \
  deployment/"$DEPLOYMENT_NAME" \
  -n "$NAMESPACE" 2>/dev/null; then
  echo "Deployment '$DEPLOYMENT_NAME' is ready."
  exit 0
else
  echo "Error: Deployment '$DEPLOYMENT_NAME' did not become ready within ${TIMEOUT} seconds."
  kubectl get deployment "$DEPLOYMENT_NAME" -n "$NAMESPACE" -o wide || true
  exit 1
fi
