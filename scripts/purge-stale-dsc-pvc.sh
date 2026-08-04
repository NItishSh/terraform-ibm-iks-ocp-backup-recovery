#!/bin/bash
# Delete DSC PersistentVolumeClaims in two distinct situations:
#
#  1. PRE-INSTALL (default, no extra argument)
#     Delete leftover primary-vol-<dsc_name>-* PVCs ONLY when no live DSC pod is
#     currently running — i.e. after a failed first install, not during an upgrade.
#
#  2. DESTROY (called with the argument "destroy")
#     Delete ALL primary-vol-<dsc_name>-* PVCs unconditionally as part of
#     `terraform destroy`.  Helm uninstall and the StatefulSet controller never
#     remove PVCs; this step ensures the underlying storage is properly
#     de-provisioned.
#     - Storage classes with RECLAIMPOLICY=Delete (e.g. ibmc-vpc-block-5iops-tier,
#       the default) will have their PV automatically deleted once the PVC is gone.
#     - Storage classes with RECLAIMPOLICY=Retain will leave the PV behind.
#       The script prints the PV name(s) so the operator can delete them manually.
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
# Guard logic (PRE-INSTALL mode only)
# -----------
# If a DSC pod (named <dsc_name>-0) is currently Running or Pending in the
# namespace, this script exits immediately without touching anything.  Only when
# there is no such pod (first install, or helm uninstalled before retry) will it
# proceed to delete orphaned PVCs.
#
# Usage:
#   purge-stale-dsc-pvc.sh <namespace> <dsc_name> [destroy]
#
# Environment variables:
#   KUBECONFIG - Path to kubeconfig file

set -euo pipefail

NS="${1:-ibm-brs-data-source-connector}"
DSC_NAME="${2:-dsc}"
MODE="${3:-}"

if [[ "$MODE" == "destroy" ]]; then
  # -------------------------------------------------------------------------
  # DESTROY mode — delete all DSC PVCs unconditionally after helm uninstall.
  # -------------------------------------------------------------------------
  echo "Deleting DSC PVCs in namespace $NS after helm uninstall ..."

  pvcs=$(kubectl get pvc -n "$NS" -o name 2>/dev/null \
    | grep "primary-vol-${DSC_NAME}" || true)

  if [[ -z "$pvcs" ]]; then
    echo "No DSC PVCs found in namespace $NS — nothing to delete."
    exit 0
  fi

  echo "Found PVC(s) to delete:"
  echo "$pvcs"

  # Capture the backing PV names before deletion so we can warn about Retain
  # policy volumes that will NOT be automatically removed.
  retain_pvs=""
  while IFS= read -r pvc_ref; do
    pvc_name="${pvc_ref#persistentvolumeclaim/}"
    pv_name=$(kubectl get pvc "$pvc_name" -n "$NS" \
      -o jsonpath='{.spec.volumeName}' 2>/dev/null || true)
    if [[ -n "$pv_name" ]]; then
      reclaim=$(kubectl get pv "$pv_name" \
        -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null || true)
      if [[ "$reclaim" == "Retain" ]]; then
        retain_pvs="${retain_pvs}${pv_name} (PVC: ${pvc_name})"$'\n'
      fi
    fi
  done <<< "$pvcs"

  kubectl delete pvc -n "$NS" \
    -l "app.kubernetes.io/instance=${DSC_NAME}" \
    --wait=false
  echo "DSC PVCs delete request sent (not waiting for finalizers — namespace deletion will complete cleanup)."

  if [[ -n "$retain_pvs" ]]; then
    echo ""
    echo "WARNING: The following PersistentVolume(s) use RECLAIMPOLICY=Retain and"
    echo "  were NOT automatically deleted. You must delete them manually to avoid"
    echo "  leaving orphaned storage:"
    # shellcheck disable=SC2001  # multiline indent needs sed — ${var//pat/rep} can't anchor to line-start
    echo "$retain_pvs" | sed 's/^/    /'
    echo "  Run: kubectl delete pv <pv-name>"
  fi

else
  # -------------------------------------------------------------------------
  # PRE-INSTALL mode — only delete PVCs when no live DSC pod exists.
  # -------------------------------------------------------------------------
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
fi
