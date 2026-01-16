##############################################################################
# Outputs
##############################################################################
output "source_registration_id" {
  description = "ID of the registered source"
  value       = module.backup_recover_protect_ocp.source_registration_id
}
