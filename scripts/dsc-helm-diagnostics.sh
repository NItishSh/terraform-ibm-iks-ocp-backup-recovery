#!/bin/bash
# Collect DSC pod, event, PVC, and node diagnostics when a Helm install fails.
# Called by the local-exec provisioner on helm_release.data_source_connector
# with on_failure = continue so output is visible in the Terraform log.
#
# Usage: dsc-helm-diagnostics.sh <namespace> <storage_class> [dsc_name]
# Required env: KUBECONFIG

set -uo pipefail

NS="${1:-ibm-brs-data-source-connector}"
SC="${2:-}"
DSC_NAME="${3:-dsc}"

echo "=== DSC HELM INSTALL DIAGNOSTICS (namespace: $NS) ==="

echo "--- Pods ---"
kubectl get pods -n "$NS" -o wide || true

echo "--- Pod details ---"
kubectl describe pods -n "$NS" || true

echo "--- Pod logs (Standard & /cohesity_logs) ---"
for pod in $(kubectl get pods -n "$NS" -o name 2>/dev/null); do
  echo ">> Standard stdout/stderr logs for $pod (last 50 lines):"
  kubectl logs "$pod" -n "$NS" --all-containers --tail=50 2>&1 || true

  echo ">> Internal /cohesity_logs/ for $pod (*.ERROR and *.STDOUTERR — deduplicated):"
  # .ERROR files: strip the timestamp+threadid prefix, then deduplicate with a
  # count so "(186x) rigel_handler.cc:756] same message" replaces 186 identical
  # lines. Capped at 30 unique patterns per file. Header (first 5 lines) is kept
  # verbatim for version/machine context.
  #
  # .STDOUTERR files: these use mixed/non-standard formats so timestamp stripping
  # is unreliable — just show the last 20 lines which captures the most recent state.
  #
  # Fails gracefully if the pod is Pending or CrashLoopBackOff.
  # shellcheck disable=SC2016  # single quotes intentional: script runs inside the pod via sh -c
  kubectl exec "$pod" -n "$NS" -- sh -c '
    if [ -d "/cohesity_logs" ]; then
      for file in /cohesity_logs/*.ERROR; do
        [ -f "$file" ] || continue
        echo "--- $file (deduplicated) ---"
        head -n 5 "$file"
        tail -n +6 "$file" \
          | sed "s/^[IWEF][0-9]* [0-9:.]*  *[0-9]* //" \
          | sort | uniq -c | sort -rn \
          | head -n 30 \
          | awk "{printf \"  (%dx) %s\n\", \$1, substr(\$0, index(\$0,\$2))}"
        echo ""
      done
      for file in /cohesity_logs/*.STDOUTERR; do
        [ -f "$file" ] || continue
        echo "--- $file (last 20 lines) ---"
        tail -n 20 "$file"
        echo ""
      done
    else
      echo "Directory /cohesity_logs not found in this pod."
    fi
  ' 2>/dev/null || echo "Could not exec into $pod (may be crashing or still initializing)."
done

echo "--- PersistentVolumeClaims ---"
kubectl get pvc -n "$NS" -o wide || true
# Warn when a PVC survives from a previous failed install. Helm never deletes
# StatefulSet PVCs on rollback/uninstall — the stale volume contains old gandalf
# state and an expired registration token that will cause the next install to
# fail immediately (gandalf SIGABRT / is_rigel_config_populated: 0).
# The purge_stale_dsc_pvc terraform_data resource should have removed it before
# this Helm install; if it still exists, that pre-install step likely did not run
# or failed silently.
stale_pvcs=$(kubectl get pvc -n "$NS" -o name 2>/dev/null | grep "primary-vol-" || true)
if [[ -n "$stale_pvcs" ]]; then
  echo ""
  echo "WARNING: The following PVC(s) already exist in namespace $NS."
  echo "  These are orphaned from a previous failed install and contain stale"
  echo "  gandalf state / expired registration tokens. If the DSC fails to register"
  echo "  (is_rigel_config_populated: 0, HTTP 500 from BRS), delete these PVCs"
  echo "  and re-run 'terraform apply' to get a clean volume:"
  # shellcheck disable=SC2001  # multiline indent needs sed — ${var//pat/rep} can't anchor to line-start
  echo "$stale_pvcs" | sed 's/^/    /'
  echo ""
fi
kubectl describe pvc -n "$NS" || true

echo "--- StorageClass check ---"
# Verify the storage class that was passed to the Helm chart exists in the cluster.
# A missing StorageClass leaves the DSC PVC Pending indefinitely and is a common
# root cause for Helm install timeouts.
if [[ -z "$SC" ]]; then
  echo "No storage class provided — skipping check."
elif kubectl get storageclass "$SC" &>/dev/null; then
  echo "StorageClass '$SC': EXISTS"
else
  echo "StorageClass '$SC': NOT FOUND — this is likely why the DSC PVC is Pending and Helm timed out."
  echo "Available StorageClasses in this cluster:"
  kubectl get storageclass 2>/dev/null || true
fi

echo "--- BRS control plane connectivity check ---"
# The DSC must reach rt.cohesity.com on ports 22 and 443 to complete registration.
# A timeout here means the worker node has no outbound internet access — check
# the subnet's public gateway, security group egress rules, and network ACLs.
# Run from a pod on the same node as dsc-0 to test the actual data-path.
DSC_NODE=$(kubectl get pod "${DSC_NAME}-0" -n "$NS" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
if [[ -n "$DSC_NODE" ]]; then
  echo "DSC is scheduled on node: $DSC_NODE"
  for port in 443 22; do
    echo ">> Testing rt.cohesity.com:$port from a pod on $DSC_NODE ..."
    kubectl run --rm -i --restart=Never --overrides="{\"spec\":{\"nodeName\":\"$DSC_NODE\",\"tolerations\":[{\"operator\":\"Exists\"}]}}" \
      dsc-connectivity-check-$port \
      --image=busybox:1.36 \
      -n "$NS" \
      -- sh -c "nc -zw5 rt.cohesity.com $port && echo 'REACHABLE' || echo 'UNREACHABLE — check public gateway / security group egress / network ACL'" \
      2>/dev/null || echo "Could not run connectivity check pod (may lack permissions)."
  done
else
  echo "Could not determine DSC node — skipping connectivity check."
fi

echo "--- Namespace events (sorted by time) ---"
kubectl get events -n "$NS" --sort-by='.lastTimestamp' || true

echo "--- Node summary ---"
kubectl get nodes -o wide || true

echo "=== END DIAGNOSTICS ==="
