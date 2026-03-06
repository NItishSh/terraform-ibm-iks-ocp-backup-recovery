##############################################################################
# Outputs
##############################################################################

output "source_registration_id" {
  description = "ID of the registered source"
  value       = module.backup_recover_protect_iks.source_registration_id
}
