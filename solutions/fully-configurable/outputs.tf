##############################################################################
# Outputs
##############################################################################

output "id" {
  description = "ID of the Backup Recovery Service instance"
  value       = module.backup_recovery.id
}

output "crn" {
  description = "CRN of the Backup Recovery Service instance"
  value       = module.backup_recovery.crn
}

output "guid" {
  description = "GUID of the Backup Recovery Service instance"
  value       = module.backup_recovery.guid
}

output "brs_instance_id" {
  description = "ID of the Backup Recovery Service instance"
  value       = module.backup_recovery.brs_instance_id
}

output "data_source_connector_id" {
  description = "ID of the Data Source Connector"
  value       = module.backup_recovery.data_source_connector_id
}

output "protection_group_ids" {
  description = "Map of protection group names to their IDs"
  value       = module.backup_recovery.protection_group_ids
}

output "latest_snapshot_ids" {
  description = "Map of protection group names to their latest snapshot IDs (for recovery operations)"
  value       = module.backup_recovery.latest_snapshot_ids
}

output "available_snapshots" {
  description = "Map of protection group names to all available snapshots with details"
  value       = module.backup_recovery.available_snapshots
}

output "recovery_ids" {
  description = "Map of recovery names to their IDs"
  value       = module.backup_recovery.recovery_ids
}