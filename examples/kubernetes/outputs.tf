##############################################################################
# Outputs
##############################################################################

output "source_registration_id" {
  description = "ID of the registered source"
  value       = module.backup_recover_protect_iks.source_registration_id
}

# output "protection_sources" {
#   description = "List of protection sources"
#   value       = module.backup_recover_protect_iks.protection_sources
# }
