# variables.tf
variable "deploy_dsc" {
  type        = bool
  description = "Set to true to deploy the BRS DSC via Helm. Set to false to only register the cluster and create policy."
  default     = true
}
variable "dsc" {
  type = object({
    release_name     = string
    chart_name       = string
    chart_repository = string
    namespace        = string
    create_namespace = bool
    chart_version    = string
    image = object({
      namespace  = string
      repository = string
      tag        = string
      pullPolicy = string
    })
    registration_token = string
    replica_count      = optional(number, 1)
    timeout            = optional(number, 1800)
  })

  description = "All configuration for the Cohesity DSC Helm chart"
}

variable "connection_id" {
  type        = string
  description = "Connection ID for the backup service"
}

variable "cluster_id" {
  type        = string
  description = "IKS/ROKS cluster id that needs to be registered with the Backuu and recovery service."
}
variable "registration" {
  type = object({
    name = string
    cluster = object({
      id                = string
      resource_group_id = string
      endpoint          = string
      distribution      = string
      images = object({
        data_mover              = string
        velero                  = string
        velero_aws_plugin       = string
        velero_openshift_plugin = string
        init_container          = string
      })
    })
  })
  description = "Kubernetes cluster registration details"
  sensitive   = true
}
variable "brsintance" {
  type = object({
    endpoint_type = optional(string, "public")
    guid          = string
    region        = string
    tenant_id     = string
  })
  description = "Backup recovery instance details to crete the policies and suorce registration."
  sensitive   = true
}
variable "policy" {
  type = object({
    name = string
    schedule = object({
      unit      = string # Minutes, Hours, Days, Weeks, Months, Years, Runs
      frequency = number # required when unit is Minutes/Hours/Days

      # Optional extra layers (allowed even when unit = Minutes)
      minute_schedule = optional(object({ frequency = number }))
      hour_schedule   = optional(object({ frequency = number }))
      day_schedule    = optional(object({ frequency = number }))
      week_schedule   = optional(object({ day_of_week = list(string) }))
      month_schedule = optional(object({
        day_of_week   = optional(list(string))
        week_of_month = optional(string) # First, Second, Third, Fourth, Last
        day_of_month  = optional(number)
      }))
      year_schedule = optional(object({ day_of_year = string })) # First, Last
    })

    retention = object({
      duration = number
      unit     = string # Days, Weeks, Months, Years

      data_lock_config = optional(object({
        mode                           = string # Compliance, Administrative
        unit                           = string # Days, Weeks, Months, Years
        duration                       = number
        enable_worm_on_external_target = optional(bool, false)
      }))
    })

    use_default_backup_target = optional(bool, true)
  })

  description = "IBM Backup & Recovery Protection Policy – fully validated"
}