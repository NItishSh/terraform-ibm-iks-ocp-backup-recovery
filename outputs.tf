##############################################################################
# Outputs
##############################################################################

output "source_registration_id" {
  description = "ID of the registered Kubernetes source"
  value       = ibm_backup_recovery_source_registration.source_registration.id
}

output "brs_instance_crn" {
  description = "CRN of the Backup & Recovery Service instance"
  value       = module.backup_recovery_instance.brs_instance_crn
}

output "brs_instance_guid" {
  description = "GUID of the Backup & Recovery Service instance"
  value       = local.brs_instance_guid
}

output "brs_tenant_id" {
  description = "Tenant ID of the Backup & Recovery Service instance"
  value       = local.brs_tenant_id
}

output "connection_id" {
  description = "ID of the data source connection to the Backup & Recovery Service instance"
  value       = local.connection_id
}

output "protection_group_ids" {
  description = "Map of protection group names to their IDs"
  value       = { for k, v in ibm_backup_recovery_protection_group.protection_group : k => v.id }
}

output "protection_sources" {
  description = "List of protection sources"
  value       = data.ibm_backup_recovery_protection_sources.sources
}

output "recovery_ids" {
  description = "Map of recovery operation names to their IDs"
  value       = { for k, v in ibm_backup_recovery.recover_snapshot : k => v.id }
}

output "recovery_status" {
  description = "Map of recovery operation names to their status information"
  value = {
    for k, v in ibm_backup_recovery.recover_snapshot : k => {
      id     = v.id
      status = v.status
      name   = v.name
    }
  }
}

output "brs_tags" {
  description = "BRS tags that should be added to the cluster to prevent tag drift. Include these in your cluster's tags input."
  value       = ["brs-region:${local.brs_instance_region}", "brs-guid:${local.brs_instance_guid}"]
}

output "available_snapshots" {
  description = "Available snapshots from protection groups that can be used for recovery. Each protection group shows its latest snapshots with IDs."
  value = {
    for pg_name, pg_data in data.ibm_backup_recovery_protection_group_run.snapshots :
    pg_name => {
      protection_group_id = pg_data.protection_group_id
      runs = try([
        for run in pg_data.runs : {
          id                = run.id
          snapshot_id       = try(run.local_backup_info[0].snapshot_info[0].snapshot_id, null)
          start_time        = run.local_backup_info[0].start_time_usecs
          end_time          = run.local_backup_info[0].end_time_usecs
          status            = run.local_backup_info[0].run_type
          is_successful     = run.is_local_snapshots_deleted == false
        }
      ], [])
    }
  }
}

output "latest_snapshot_ids" {
  description = "Latest snapshot ID for each protection group - use these for recovery"
  value = {
    for pg_name, pg_data in data.ibm_backup_recovery_protection_group_run.snapshots :
    pg_name => try(
      pg_data.runs[0].local_backup_info[0].snapshot_info[0].snapshot_id,
      "No snapshots available yet"
    )
  }
}
