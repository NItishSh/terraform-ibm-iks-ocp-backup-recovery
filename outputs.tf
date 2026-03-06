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

output "protection_policy_id" {
  description = "ID of the protection policy (null if using an existing policy)"
  value       = local.use_existing_policy ? null : ibm_backup_recovery_protection_policy.protection_policy[0].id
}
