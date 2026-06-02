##############################################################################
# Outputs
##############################################################################

output "source_cluster_id" {
  description = "ID of the source cluster"
  value       = local.source_cluster_id
}

output "target_cluster_id" {
  description = "ID of the target cluster"
  value       = local.target_cluster_id
}

output "brs_instance_crn" {
  description = "CRN of the shared Backup & Recovery Service instance"
  value       = module.source_backup_recovery.brs_instance_crn
}

output "brs_instance_guid" {
  description = "GUID of the shared Backup & Recovery Service instance"
  value       = module.source_backup_recovery.brs_instance_guid
}

output "brs_instance_url" {
  description = "URL of the BRS instance API endpoint"
  value       = "https://${module.source_backup_recovery.brs_instance_guid}.${var.region}.backup-recovery.cloud.ibm.com"
}

output "source_connection_id" {
  description = "Connection ID for source cluster"
  value       = module.source_backup_recovery.connection_id
  sensitive   = true
}

output "target_connection_id" {
  description = "Connection ID for target cluster"
  value       = module.target_backup_recovery.connection_id
  sensitive   = true
}

output "source_protection_group_ids" {
  description = "Protection group IDs on source cluster"
  value       = module.source_backup_recovery.protection_group_ids
}

output "source_registration_id" {
  description = "Source registration ID for source cluster"
  value       = module.source_backup_recovery.source_registration_id
}

output "target_registration_id" {
  description = "Source registration ID for target cluster"
  value       = module.target_backup_recovery.source_registration_id
}

output "recovery_ids" {
  description = "Recovery operation IDs (empty if enable_recovery is false)"
  value       = module.source_backup_recovery.recovery_ids
}

output "recovery_status" {
  description = "Recovery operation status (empty if enable_recovery is false)"
  value       = module.source_backup_recovery.recovery_status
}

output "latest_snapshots" {
  description = "Latest snapshot IDs per protection group (empty if enable_recovery is false)"
  value       = module.source_backup_recovery.latest_snapshots
}

output "backup_runs_summary" {
  description = "Summary of backup runs per protection group (empty if enable_recovery is false)"
  value       = module.source_backup_recovery.backup_runs_summary
}

output "source_workload_namespace" {
  description = "Name of the test workload namespace on source cluster"
  value       = local.source_namespace
}

output "cross_cluster_recovery_status" {
  description = "Status of cross-cluster recovery operation"
  value       = var.enable_recovery ? "Recovery triggered via API - check BRS UI for detailed status" : "Recovery disabled"
}

output "recovery_script_path" {
  description = "Path to the cross-cluster recovery script for manual execution"
  value       = "${path.module}/../../scripts/trigger_cross_cluster_recovery.sh"
}

output "recovery_command_example" {
  description = "Example command to manually trigger cross-cluster recovery"
  value = var.enable_recovery ? format(
    "%s '%s' '%s' 'public' '%s' '%s' '%s' 'latest' '$IBMCLOUD_API_KEY' 'manual-recovery' '/tmp'",
    "${path.module}/../../scripts/trigger_cross_cluster_recovery.sh",
    "https://${module.source_backup_recovery.brs_instance_guid}.${var.region}.backup-recovery.cloud.ibm.com",
    module.source_backup_recovery.brs_tenant_id,
    module.source_backup_recovery.brs_instance_guid,
    split("::", module.source_backup_recovery.protection_group_ids["${var.prefix}-source-pg"])[1],
    split("::", module.target_backup_recovery.source_registration_id)[1]
  ) : "Recovery disabled"
  sensitive = false
}
