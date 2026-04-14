# Kubernetes example

<!-- BEGIN SCHEMATICS DEPLOY HOOK -->
<p>
  <a href="https://cloud.ibm.com/schematics/workspaces/create?workspace_name=iks-ocp-backup-recovery-kubernetes-example&repository=https://github.com/terraform-ibm-modules/terraform-ibm-iks-ocp-backup-recovery/tree/main/examples/kubernetes">
    <img src="https://img.shields.io/badge/Deploy%20with%20IBM%20Cloud%20Schematics-0f62fe?style=flat&logo=ibm&logoColor=white&labelColor=0f62fe" alt="Deploy with IBM Cloud Schematics">
  </a><br>
  ℹ️ Ctrl/Cmd+Click or right-click on the Schematics deploy button to open in a new tab.
</p>
<!-- END SCHEMATICS DEPLOY HOOK -->

This example provisions VPC, kubernetes cluster, and a fully integrated Backup & Recovery environment with policies, source registration, connectivity, and data source connector deployment.

A kubernetes example that will provision the following:

- A new resource group, if an existing one is not passed in.
- A basic VPC and subnet with public gateway enabled.
- A single zone kubernetes VPC cluster.
- A new Backup & Recovery instance.
- A data source connection to integrate the cluster with the Backup & Recovery service.
