##############################################################################
# Outputs
##############################################################################

output "protection_policy_name" {
  description = "Name of the created protection policy"
  value       = module.backup_recover_protect_ocp.protection_policy_name
}

output "source_registration_id" {
  description = "ID of the registered source"
  value       = module.backup_recover_protect_ocp.source_registration_id
}
