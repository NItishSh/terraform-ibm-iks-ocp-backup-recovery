#!/usr/bin/env bash
# check-existing-registration.sh
#
# Check if the cluster already has a brs-backup-agent-* namespace, which indicates
# the cluster is already registered (or was registered) to SOME BRS instance.
#
# If a brs-backup-agent-* namespace is found, exit 1 with a clear explanation
# rather than attempting to overwrite or silently detach the cluster.
#
# NOTE: The brs_instance_guid and the <guid> in brs-backup-agent-<guid> are
# different values (instance GUID vs. agent registration UUID). We cannot match
# them directly. We only check for the presence of ANY brs-backup-agent-* namespace
# to detect if the cluster is already connected to ANY BRS instance.
#
# Usage:
#   check-existing-registration.sh
#
# Environment variables:
#   KUBECONFIG - Path to kubeconfig file

set -euo pipefail

echo "Checking cluster for existing BRS agent namespaces..."

# Find all namespaces matching brs-backup-agent-
agent_namespaces=$(kubectl get ns -o name 2>/dev/null | grep "namespace/brs-backup-agent-" || true)

if [[ -z "$agent_namespaces" ]]; then
  echo "No existing BRS agent namespaces found — cluster is clean for registration."
  exit 0
fi

# A brs-backup-agent-* namespace exists, which means the cluster is already
# registered to a BRS instance (or was registered in a previous apply).
echo -e "\n================================================================================" >&2
echo -e "ERROR: Cluster is already registered to a BRS instance!" >&2
echo -e "Found namespace(s):" >&2
while IFS= read -r ns_ref; do
  [[ -z "$ns_ref" ]] && continue
  echo -e "  - ${ns_ref#namespace/}" >&2
done <<< "$agent_namespaces"
echo -e "--------------------------------------------------------------------------------" >&2
echo -e "The presence of a 'brs-backup-agent-*' namespace indicates that this cluster" >&2
echo -e "has an active or leftover registration to a BRS instance." >&2
echo -e "" >&2
echo -e "To register this cluster to a (new) BRS instance, you must first:" >&2
echo -e "  1. Deregister the cluster from the current BRS instance" >&2
echo -e "  2. Wait for BRS to remove the 'brs-backup-agent-*' namespace" >&2
echo -e "  3. Then proceed with the new registration" >&2
echo -e "" >&2
echo -e "If the cluster should remain connected to the same BRS instance," >&2
echo -e "no action is needed — the registration will be re-used." >&2
echo -e "================================================================================\n" >&2
exit 1
