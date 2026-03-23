##############################################################################
# Outputs
##############################################################################

output "source_registration_id" {
  description = "ID of the registered source"
  value       = module.backup_recover_protect_iks.source_registration_id
}

output "protection_group_ids" {
  description = "Map of protection group names to IDs"
  value       = module.backup_recover_protect_iks.protection_group_ids
}

output "recovery_ids" {
  description = "Map of recovery operation names to IDs"
  value       = module.backup_recover_protect_iks.recovery_ids
}

output "recovery_status" {
  description = "Map of recovery operation names to status details"
  value       = module.backup_recover_protect_iks.recovery_status
}

# output "protection_sources" {
#   description = "List of protection sources"
#   value       = module.backup_recover_protect_iks.protection_sources
# }
