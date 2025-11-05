output "helm_release_name" {
  description = "Name of the deployed Helm release"
  value       = helm_release.dsc_chart.name
}

output "helm_release_status" {
  description = "Status of the Helm release"
  value       = helm_release.dsc_chart.status
}


output "protection_policy_name" {
  description = "Name of the created protection policy"
  value       = ibm_backup_recovery_protection_policy.protection_policy.name
}