# Cross-Cluster Backup and Recovery example

<!-- BEGIN SCHEMATICS DEPLOY HOOK -->
<p>
  <a href="https://cloud.ibm.com/schematics/workspaces/create?workspace_name=iks-ocp-backup-recovery-backup-recovery-cross-cluster-example&repository=https://github.com/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery/tree/main/examples/backup-recovery-cross-cluster">
    <img src="https://img.shields.io/badge/Deploy%20with%20IBM%20Cloud%20Schematics-0f62fe?style=flat&logo=ibm&logoColor=white&labelColor=0f62fe" alt="Deploy with IBM Cloud Schematics">
  </a><br>
  ℹ️ Ctrl/Cmd+Click or right-click on the Schematics deploy button to open in a new tab.
</p>
<!-- END SCHEMATICS DEPLOY HOOK -->

This example demonstrates **single-shot backup and recovery** across two Kubernetes clusters using a **single shared BRS instance**.

An example that will provision the following:

- A new resource group, if an existing one is not passed in.
- Two basic VPCs with subnets and public gateways enabled (if creating new clusters).
- Two single zone kubernetes VPC clusters (source and target), if not using existing clusters.
- A new Backup & Recovery instance (if not using an existing one).
- Data source connections to integrate both clusters with the Backup & Recovery service.
- Protection group configuration for the source cluster with immediate backup schedule.
- Optional automatic cross-cluster recovery after backup completion.
