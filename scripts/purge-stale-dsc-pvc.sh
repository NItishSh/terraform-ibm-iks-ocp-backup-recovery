#!/bin/bash
# Delete leftover primary-vol-<dsc_name>-* PVCs in the DSC namespace ONLY when
# no live DSC pod is currently running — i.e. after a failed first install, not
# during an upgrade.
#
# Background
# ----------
# Helm and the Kubernetes StatefulSet controller never delete PVCs on
# helm uninstall / rollback — this is intentional to prevent data loss.
#
# For a FRESH INSTALL that previously failed, this is harmful: the orphaned PVC
# contains stale gandalf state and an expired registration token. Re-mounting it
# on the next install causes an immediate crash (gandalf SIGABRT /
# is_rigel_config_populated: 0 / HTTP 500 from BRS on every registration retry).
#
# For an UPGRADE, however, the PVC holds live production data.  Deleting it
# would cause permanent, unrecoverable data loss.  The official DSC docs
# explicitly warn that helm rollbacks are unsupported for this reason.
#
# Guard logic
# -----------
# If a DSC pod (named <dsc_name>-0) is currently Running or Pending in the
# namespace, this script exits immediately without touching anything.  Only when
# there is no such pod (first install, or helm uninstalled before retry) will it
# proceed to delete orphaned PVCs.
#
# Usage:
#   purge-stale-dsc-pvc.sh <namespace> <dsc_name>
#
# Environment variables:
#   KUBECONFIG - Path to kubeconfig file

set -euo pipefail

NS="${1:-ibm-brs-data-source-connector}"
DSC_NAME="${2:-dsc}"

echo "Checking for stale DSC PVCs in namespace $NS ..."

# Check whether a live DSC pod exists. A pod in Running or Pending state means
# this is an upgrade — do not touch the PVC.
live_pod=$(kubectl get pod "${DSC_NAME}-0" -n "$NS" \
  --ignore-not-found \
  -o jsonpath='{.status.phase}' 2>/dev/null || true)

if [[ -n "$live_pod" ]]; then
  echo "DSC pod ${DSC_NAME}-0 is ${live_pod} — this is an upgrade, not a fresh install."
  echo "PVCs will NOT be deleted (live production data must be preserved)."
  exit 0
fi

# No live pod — safe to look for orphaned PVCs from a previous failed install.
stale=$(kubectl get pvc -n "$NS" -o name 2>/dev/null \
  | grep "primary-vol-${DSC_NAME}" || true)

if [[ -n "$stale" ]]; then
  echo "WARNING: Stale PVC(s) found from a previous failed install — deleting before re-install:"
  echo "$stale"
  kubectl delete pvc -n "$NS" \
    -l "app.kubernetes.io/instance=${DSC_NAME}" \
    --wait=true --timeout=120s
  echo "Stale PVCs deleted."
else
  echo "No stale PVCs found — proceeding."
fi
