##############################################################################
# Outputs
##############################################################################

output "source_registration_id" {
  description = "ID of the registered Kubernetes source"
  value       = ibm_backup_recovery_source_registration.source_registration.id
}

output "brs_instance_crn" {
  description = "CRN of the Backup & Recovery Service instance"
  value       = module.backup_recovery_instance.brs_instance_crn
}

output "brs_instance_guid" {
  description = "GUID of the Backup & Recovery Service instance"
  value       = local.brs_instance_guid
}

output "brs_tenant_id" {
  description = "Tenant ID of the Backup & Recovery Service instance"
  value       = local.brs_tenant_id
}

output "connection_id" {
  description = "ID of the data source connection to the Backup & Recovery Service instance"
  value       = local.connection_id
}

output "protection_group_ids" {
  description = "Map of protection group names to their IDs"
  value       = { for k, v in ibm_backup_recovery_protection_group.protection_group : k => v.id }
}

output "protection_sources" {
  description = "List of protection sources"
  value       = data.ibm_backup_recovery_protection_sources.sources
}

output "recovery_ids" {
  description = "Map of recovery operation names to their IDs"
  value       = { for k, v in ibm_backup_recovery.recover_snapshot : k => v.id }
}

output "recovery_status" {
  description = "Map of recovery operation names to their status information"
  value = {
    for k, v in ibm_backup_recovery.recover_snapshot : k => {
      id     = v.id
      status = v.status
      name   = v.name
    }
  }
}
