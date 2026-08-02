output "brs_instance_crn" {
  description = "CRN of the Backup and Recovery Service instance."
  value       = module.backup_recovery.brs_instance_crn
}

output "brs_connection_id" {
  description = "ID of the BRS data source connection."
  value       = module.backup_recovery.connection_id
}

output "brs_vpe_ips" {
  description = "Map of VPEG name to list of reserved IP objects. Each IP object contains the private IP address bound to a subnet zone."
  value       = module.backup_recovery.brs_vpe_ips
}
