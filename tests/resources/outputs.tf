##############################################################################
# Outputs
##############################################################################

output "region" {
  value       = var.region
  description = "Region where OCP Cluster is deployed."
}

output "workload_cluster_id" {
  value       = module.ocp_base.cluster_id
  description = "ID of the workload cluster."
}

output "workload_cluster_crn" {
  value       = module.ocp_base.cluster_crn
  description = "CRN of the workload cluster."
}

output "cluster_resource_group_id" {
  value       = module.ocp_base.resource_group_id
  description = "Resource group ID of the workload cluster."
}
