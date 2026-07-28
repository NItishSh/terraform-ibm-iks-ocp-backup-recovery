#!/bin/bash
# Collect DSC pod, event, PVC, and node diagnostics when a Helm install fails.
# Called by the local-exec provisioner on helm_release.data_source_connector
# with on_failure = continue so output is visible before Helm atomic rollback.
#
# Usage: dsc-helm-diagnostics.sh <namespace>
# Required env: KUBECONFIG

set -uo pipefail

NS="${1:-ibm-brs-data-source-connector}"

echo "=== DSC HELM INSTALL DIAGNOSTICS (namespace: $NS) ==="

echo "--- Pods ---"
kubectl get pods -n "$NS" -o wide || true

echo "--- Pod details ---"
kubectl describe pods -n "$NS" || true

echo "--- Pod logs (Standard & /cohesity_logs) ---"
for pod in $(kubectl get pods -n "$NS" -o name 2>/dev/null); do
  echo ">> Standard stdout/stderr logs for $pod:"
  kubectl logs "$pod" -n "$NS" --all-containers --tail=200 2>&1 || true

  echo ">> Internal /cohesity_logs/ for $pod (*.ERROR and *.STDOUTERR only):"
  # Use exec to read directly from the pod's filesystem.
  # Fails gracefully if the pod is Pending or CrashLoopBackOff.
  # shellcheck disable=SC2016  # single quotes intentional: script runs inside the pod via sh -c
  kubectl exec "$pod" -n "$NS" -- sh -c '
    if [ -d "/cohesity_logs" ]; then
      for file in /cohesity_logs/*.ERROR /cohesity_logs/*.STDOUTERR; do
        [ -f "$file" ] || continue
        echo "--- Content of $file ---"
        tail -n 200 "$file"
      done
    else
      echo "Directory /cohesity_logs not found in this pod."
    fi
  ' 2>/dev/null || echo "Could not exec into $pod (may be crashing or still initializing)."
done

echo "--- PersistentVolumeClaims ---"
kubectl get pvc -n "$NS" -o wide || true
kubectl describe pvc -n "$NS" || true

echo "--- Namespace events (sorted by time) ---"
kubectl get events -n "$NS" --sort-by='.lastTimestamp' || true

echo "--- Node summary ---"
kubectl get nodes -o wide || true

echo "=== END DIAGNOSTICS ==="
