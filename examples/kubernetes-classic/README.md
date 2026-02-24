# Kubernetes Classic example

<!-- BEGIN SCHEMATICS DEPLOY HOOK -->
<a href="https://cloud.ibm.com/schematics/workspaces/create?workspace_name=iks-ocp-backup-recovery-kubernetes-classic-example&repository=https://github.com/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery/tree/main/examples/kubernetes-classic"><img src="https://img.shields.io/badge/Deploy%20with IBM%20Cloud%20Schematics-0f62fe?logo=ibm&logoColor=white&labelColor=0f62fe" alt="Deploy with IBM Cloud Schematics" style="height: 16px; vertical-align: text-bottom;"></a>
<!-- END SCHEMATICS DEPLOY HOOK -->


This example provisions a Classic infrastructure Kubernetes cluster and a fully integrated Backup & Recovery environment with policies, source registration, connectivity, and data source connector deployment.

A kubernetes classic example that will provision the following:

- A new resource group, if an existing one is not passed in.
- Public and private VLANs for the classic cluster.
- A single zone Kubernetes Classic cluster.
- A new Backup & Recovery instance.
- A data source connection to integrate the cluster with the Backup & Recovery service.

<!-- BEGIN SCHEMATICS DEPLOY TIP HOOK -->
:information_source: Ctrl/Cmd+Click or right-click on the Schematics deploy button to open in a new tab
<!-- END SCHEMATICS DEPLOY TIP HOOK -->
