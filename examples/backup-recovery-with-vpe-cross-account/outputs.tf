output "cluster_id" {
  description = "ID of the IKS cluster being protected (source account)."
  value       = local.cluster_id
}

output "brs_instance_crn" {
  description = "CRN of the Backup and Recovery Service instance (target account)."
  value       = module.backup_recovery.brs_instance_crn
}

output "brs_connection_id" {
  description = "ID of the BRS data-source connection."
  value       = module.backup_recovery.connection_id
  sensitive   = true
}

output "brs_private_hostname" {
  description = "BRS private hostname that should resolve to the VPEG reserved IP inside the cluster VPC. Run 'getent hosts <value>' from inside a DSC pod to verify VPE routing."
  value       = "${module.backup_recovery.brs_instance_guid}.private.${var.region}.backup-recovery.cloud.ibm.com"
}

output "brs_vpe_ips" {
  description = "Map of VPEG name → list of reserved IP objects bound to each subnet zone in the source-account VPC."
  value       = module.backup_recovery.brs_vpe_ips
}

output "s2s_auth_policies" {
  description = "S2S IAM authorization policies created in the target account (key = service_map key)."
  value       = module.backup_recovery.s2s_auth_policies
}
