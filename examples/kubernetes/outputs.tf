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
  value = merge(
    module.backup_recover_protect_iks.recovery_ids,
    contains(["auto", "selective", "full", "cross"], var.recovery_mode) ? {
      for recovery in ibm_backup_recovery.discovered_recover_snapshot : recovery.name => recovery.id
    } : {}
  )
}

output "recovery_status" {
  description = "Map of recovery operation names to status details"
  value = merge(
    module.backup_recover_protect_iks.recovery_status,
    contains(["auto", "selective", "full", "cross"], var.recovery_mode) ? {
      for recovery in ibm_backup_recovery.discovered_recover_snapshot : recovery.name => {
        id     = recovery.id
        status = recovery.status
        name   = recovery.name
      }
    } : {}
  )
}
