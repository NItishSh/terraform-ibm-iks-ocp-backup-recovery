##############################################################################
# Outputs
##############################################################################

output "source_registration_id" {
  description = "ID of the registered Kubernetes source"
  value       = ibm_backup_recovery_source_registration.source_registration.id
}
