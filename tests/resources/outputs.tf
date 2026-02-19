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
output "brs_instance_crn" {
  value       = module.backup_recovery_instance.brs_instance_crn
  description = "CRN of the Backup and Recovery Service instance."
}

output "brs_connection_name" {
  value       = module.backup_recovery_instance.connection_name
  description = "Name of the Backup and Recovery Service connection."
}

output "protection_policy_name" {
  value       = ibm_backup_recovery_protection_policy.existing_policy.name
  description = "Name of the protection policy."
}
