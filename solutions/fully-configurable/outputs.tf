##############################################################################
# Outputs
##############################################################################

# BRS Instance Outputs
output "brs_instance_guid" {
  description = "GUID of the Backup & Recovery Service instance"
  value       = module.protect_cluster.brs_instance_guid
}

output "brs_instance_crn" {
  description = "CRN of the Backup & Recovery Service instance"
  value       = module.protect_cluster.brs_instance_crn
}

output "brs_tenant_id" {
  description = "Tenant ID for the Backup & Recovery Service instance"
  value       = module.protect_cluster.brs_tenant_id
}

# Source Cluster Outputs
output "source_registration_id" {
  description = "Registration ID of the source cluster in BRS"
  value       = module.protect_cluster.source_registration_id
}

output "source_connection_id" {
  description = "Connection ID for the source cluster"
  value       = module.protect_cluster.connection_id
  sensitive   = true
}

# Protection Group Outputs
output "protection_group_ids" {
  description = "Map of protection group names to their IDs"
  value       = module.protect_cluster.protection_group_ids
}

# Note: protection_policy_ids, dsc_namespace, and dsc_release_name are internal to the module
# and not exposed as outputs. These are managed automatically by the module.

##############################################################################
# Recovery Outputs (when enabled)
##############################################################################

output "recovery_type" {
  description = "Type of recovery configured (`same-cluster` or `cross-cluster`)"
  value       = var.enable_recovery ? var.recovery_type : null
}

output "recovery_protection_group_name" {
  description = "Name of the protection group used for recovery"
  value       = var.enable_recovery ? local.recovery_pg_name : null
}

output "recovery_snapshot_id" {
  description = "Snapshot ID used for recovery"
  value       = var.enable_recovery ? try(local.snapshot_data.snapshot_id, null) : null
  sensitive   = true
}

output "recovery_namespace_prefix" {
  description = "Prefix used for recovered namespaces"
  value       = var.enable_recovery ? var.recovery_namespace_prefix : null
}

# Cross-Cluster Recovery Outputs
output "target_cluster_registration_id" {
  description = "Registration ID of the target cluster (cross-cluster recovery only)"
  value       = var.enable_recovery && var.recovery_type == "cross-cluster" ? module.target_cluster_registration[0].source_registration_id : null
}

output "target_cluster_connection_id" {
  description = "Connection ID for the target cluster (cross-cluster recovery only)"
  value       = var.enable_recovery && var.recovery_type == "cross-cluster" ? module.target_cluster_registration[0].connection_id : null
  sensitive   = true
}

output "recovery_status" {
  description = "Status message about recovery configuration"
  value = var.enable_recovery ? (
    var.recovery_type == "same-cluster" ?
    "Same-cluster recovery enabled. Namespaces will be restored with prefix '${var.recovery_namespace_prefix}' to the source cluster." :
    "Cross-cluster recovery enabled. Namespaces will be restored with prefix '${var.recovery_namespace_prefix}' to target cluster '${var.target_cluster_id}'."
  ) : "Recovery is disabled. Set 'enable_recovery = true' to enable automatic recovery testing."
}
