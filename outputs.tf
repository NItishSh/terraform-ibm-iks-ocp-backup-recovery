output "protection_policy_name" {
  description = "Name of the created protection policy"
  value       = ibm_backup_recovery_protection_policy.protection_policy.name
}
output "source_registration_id" {
  description = "ID of the registered Kubernetes source"
  value       = ibm_backup_recovery_source_registration.source_registration.id
}